"""Local TLS IMAP test mailbox. No real accounts or outgoing email."""
import argparse, base64, io, json, pathlib, shutil, socketserver, ssl, subprocess, time, zipfile


def epub():
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w') as z:
        z.writestr('mimetype', 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
        z.writestr('META-INF/container.xml', '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="book.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
        z.writestr('book.opf', '<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">sendtokoreader-test</dc:identifier><dc:title>邮件收书测试</dc:title><dc:language>zh-CN</dc:language></metadata><manifest><item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="chapter"/></spine></package>')
        z.writestr('chapter.xhtml', '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>邮件收书测试</title></head><body><h1>邮件收书测试成功</h1><p>这本电子书经过 TLS 邮箱连接、附件下载和本地保存，现在由 KOReader 原生阅读器打开。</p><p>测试内容由本项目生成。</p></body></html>')
    return output.getvalue()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', required=True)
    parser.add_argument('--port', type=int, default=19993)
    args = parser.parse_args()
    root = pathlib.Path(args.directory); root.mkdir(parents=True, exist_ok=True)
    cert, key = root/'cert.pem', root/'key.pem'
    if not cert.exists():
        subprocess.run([shutil.which('openssl'), 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2', '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost', '-keyout', str(key), '-out', str(cert)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    sample = epub(); (root/'expected.epub').write_bytes(sample)
    content = {1: sample, 2: sample, 3: '中文文件名测试\n'.encode()*100, 4: b'cancel-me\n'*400000, 5: b'retry-success\n'*100, 6: b'not-an-ebook'}
    wire = {uid: base64.encodebytes(data).replace(b'\n', b'\r\n') for uid, data in content.items()}
    names = {1: '"FILENAME" "=?UTF-8?B?' + base64.b64encode('邮件收书测试.epub'.encode()).decode() + '?="', 2: '"FILENAME*" "UTF-8\'\'%E9%82%AE%E4%BB%B6%E6%94%B6%E4%B9%A6%E6%B5%8B%E8%AF%95.epub"', 3: '"FILENAME" "=?GB18030?B?' + base64.b64encode('中文说明.txt'.encode('gb18030')).decode() + '?="', 4: '"FILENAME" "large-cancel.txt"', 5: '"FILENAME" "retry.txt"', 6: '"FILENAME" "unsupported.zip"'}
    config = dict(provider='custom', host='localhost', port=args.port, username='fixture@example.test', password='fixture-only', ca_file=str(cert), download_dir=str(root/'books'))
    (root/'config.json').write_text(json.dumps(config)); (root/'control.json').write_text(json.dumps(dict(max_uid=6, fail_uid=5, slow=True)))
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); context.load_cert_chain(cert, key)

    class Handler(socketserver.StreamRequestHandler):
        def handle(self):
            def send(s): self.wfile.write(s.encode() + b'\r\n'); self.wfile.flush()
            send('* OK Local test mailbox')
            while line := self.rfile.readline():
                text = line.decode().strip(); tag, command = text.split(' ', 1)
                upper = command.upper()
                with (root/'commands.log').open('a') as log: log.write('LOGIN [redacted]\n' if upper.startswith('LOGIN ') else command+'\n')
                control = json.loads((root/'control.json').read_text())
                max_uid = control.get('max_uid', 6)
                if upper.startswith('LOGIN '):
                    send(tag + (' OK authenticated' if command == 'LOGIN "fixture@example.test" "fixture-only"' else ' NO denied')); continue
                if upper == 'CAPABILITY': send('* CAPABILITY IMAP4rev1 ID')
                elif upper.startswith('ID '): send('* ID NIL')
                elif upper == 'EXAMINE INBOX':
                    send(f'* {max_uid} EXISTS'); send('* OK [UIDVALIDITY 987] valid'); send(f'* OK [UIDNEXT {max_uid+1}] next')
                elif upper.startswith('UID SEARCH '):
                    start = int(upper.split()[-1].split(':')[0]) if ' UID ' in upper[4:] else 1
                    # IMAP ranges invert when lower bound exceeds last UID.
                    ids = range(min(start, max_uid), max_uid+1)
                    send('* SEARCH ' + ' '.join(map(str, ids)))
                elif upper.startswith('UID FETCH '):
                    uid = int(command.split()[2]); data = wire[uid]
                    if 'BODYSTRUCTURE' in upper:
                        send(f'* {uid} FETCH (UID {uid} INTERNALDATE "04-Oct-2026 09:00:00 +0800" BODYSTRUCTURE (("TEXT" "PLAIN" ("CHARSET" "UTF-8") NIL NIL "7BIT" 5 1 NIL NIL)("APPLICATION" "OCTET-STREAM" NIL NIL NIL "BASE64" {len(data)} NIL ("ATTACHMENT" ({names[uid]}))) "MIXED"))')
                    elif 'BODY.PEEK[2]' in upper:
                        send(f'* {uid} FETCH (UID {uid} BODY[2] {{{len(data)}}}')
                        if control.get('fail_uid') == uid:
                            self.wfile.write(data[:50]); self.wfile.flush(); return
                        for i in range(0, len(data), 16384):
                            self.wfile.write(data[i:i+16384]); self.wfile.flush()
                            if uid == 4 and control.get('slow'): time.sleep(.05)
                        send(')')
                    else: send(tag+' BAD Only BODY.PEEK allowed'); continue
                else: send(tag+' BAD Unsupported command'); continue
                send(tag+' OK done')

    class Server(socketserver.ThreadingTCPServer):
        allow_reuse_address = True
        daemon_threads = True
        def get_request(self):
            while True:
                sock, addr = super().get_request()
                try: return context.wrap_socket(sock, server_side=True), addr
                except ssl.SSLError: sock.close()
        def handle_error(self, request, client_address): pass  # client cancellation is intentional
    with Server(('127.0.0.1', args.port), Handler) as server:
        print(f'TLS fixture ready: localhost:{args.port}', flush=True)
        server.serve_forever()

if __name__ == '__main__': main()
