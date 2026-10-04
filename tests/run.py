#!/usr/bin/env python3
"""Run local TLS and native KOReader checks against an existing emulator build."""
import argparse, os, pathlib, shutil, socket, subprocess, sys, tempfile, time, zipfile

parser = argparse.ArgumentParser()
parser.add_argument('runtime', type=pathlib.Path, help='built koreader directory containing luajit and reader.lua')
args = parser.parse_args()
runtime = args.runtime.resolve(); root = pathlib.Path(__file__).resolve().parent.parent
assert (runtime/'reader.lua').is_file() and (runtime/'luajit').exists(), 'Build KOReader first'
evidence = root/'tests/evidence'; evidence.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='sendtokoreader-check-') as tmp:
    temp = pathlib.Path(tmp); fixture=temp/'mail'; profile=temp/'profile'
    (profile/'books').mkdir(parents=True); (profile/'plugins').mkdir()
    subprocess.run([sys.executable,str(root/'scripts/package_release.py'),str(temp/'plugin.zip')],check=True)
    with zipfile.ZipFile(temp/'plugin.zip') as package: package.extractall(profile/'plugins')
    (profile/'settings.reader.lua').write_text('return {language="zh_CN",color_rendering=false,last_migration_date=20260918}\n')
    with socket.socket() as sock: sock.bind(('127.0.0.1',0)); port=sock.getsockname()[1]
    server=subprocess.Popen([sys.executable,str(root/'tests/imap_fixture.py'),'--directory',str(fixture),'--port',str(port)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    try:
        for _ in range(100):
            if (fixture/'config.json').exists(): break
            if server.poll() is not None: raise RuntimeError(server.communicate()[1])
            time.sleep(.1)
        else: raise RuntimeError('TLS fixture startup timed out')
        env=dict(os.environ,KO_HOME=str(profile),EMULATE_READER_W='600',EMULATE_READER_H='800',EMULATE_READER_DPI='167',SDL_VIDEODRIVER='dummy')
        for name in ('core','native'):
            command=[str(runtime/'luajit'),str(root/f'tests/{name}.lua'),str(root),str(fixture)]
            completed=subprocess.run(command,cwd=runtime,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=80)
            (evidence/f'{name}.log').write_text(completed.stdout)
            for line in completed.stdout.splitlines():
                if line.startswith(('PASS','FAIL','ALL')): print(line)
            if completed.returncode: raise RuntimeError(f'{name} failed; see tests/evidence/{name}.log')
        shutil.copyfile(fixture/'commands.log',evidence/'imap-commands.log')
    finally:
        server.terminate(); server.wait(timeout=5)
print('ALL CHECKS PASSED')
