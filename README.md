# Send to KOReader

[🇨🇳 中文文档](README_CN.md)

[![CI](https://github.com/finlater/sendtokoreader.koplugin/actions/workflows/ci.yml/badge.svg)](https://github.com/finlater/sendtokoreader.koplugin/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/finlater/sendtokoreader.koplugin?include_prereleases)](https://github.com/finlater/sendtokoreader.koplugin/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A KOReader plugin for receiving ebooks through your own email account. Send a book as a regular attachment, refresh the inbox on your reader, and download it for reading.

## Features

- **Your own mailbox** — QQ, 163 and custom IMAP over TLS accounts; no relay service required.
- **Simple setup** — A focused account setup screen before connecting your first mailbox.
- **Manual refresh** — Scans the last 30 days on first use, including read messages, then checks new message UIDs.
- **Multiple selection** — Select individual attachments or the current page, with a size summary and pagination only when needed.
- **Background downloads** — Shows progress, supports cancellation and retries failed attachments.
- **Preserves your mail** — Uses read-only IMAP commands and leaves messages and their read state unchanged.
- **Safe local storage** — Skips downloaded attachments that still exist; adds a numbered suffix for different attachments with the same filename.
- **Open and read** — Tap a downloaded attachment to open it in KOReader.

## Screenshots

These are native KOReader emulator renders with example data. The current in-app interface is Chinese.

| Account setup | Attachment list | Download progress |
|:---:|:---:|:---:|
| ![Account setup](screenshots/welcome.png) | ![Attachment list](screenshots/inbox.png) | ![Download progress](screenshots/progress.png) |

## Installation

1. Download `sendtokoreader.koplugin-vX.Y.Z.zip` from [GitHub Releases](https://github.com/finlater/sendtokoreader.koplugin/releases).
2. Extract the archive to get the `sendtokoreader.koplugin` folder.
3. Copy that folder into your KOReader plugins directory:

```text
koreader/plugins/sendtokoreader.koplugin/
```

4. Restart KOReader and open **Tools → Send to KOReader · 邮件收书**.

To install from source, clone this repository into a folder named `sendtokoreader.koplugin` inside the same plugins directory. To update, replace the plugin files and restart KOReader. Mailbox settings and download records are stored separately.

## Connect your mailbox

1. Enable IMAP in your email provider's settings and generate a client authorization code or app password.
2. Tap **绑定邮箱** (Bind mailbox), choose a provider and enter your email address and authorization code.
3. For a custom provider, set the IMAP hostname and TLS port under **服务器设置** (Server settings).
4. Tap **验证并保存** (Verify and save).
5. Email an ebook to that address as a regular attachment. Return to the list, tap the refresh icon, select the attachment and tap **下载所选** (Download selected).

| Provider | IMAP hostname | TLS port | Credential |
|---|---|---|---|
| QQ Mail | `imap.qq.com` | `993` | Client authorization code |
| 163 Mail | `imap.163.com` | `993` | Client authorization code |
| Custom | Your provider's hostname | Usually `993` | IMAP password or app password |

Only one account and the inbox folder are supported. Choose a download folder in **设置 → 下载目录**. The default is a `收书` subfolder of KOReader's download or home directory.

## Supported attachments and limits

Supported filename extensions: `epub`, `pdf`, `mobi`, `azw`, `azw3`, `fb2`, `txt`, `djvu`, `djv`, `cbz`, `cbr`. Actual reading support depends on KOReader.

- Supports Base64, quoted-printable and unencoded MIME attachments, encoded Chinese filenames, and RFC2231 filename parameters. Unsupported character sets fall back to an ASCII-safe filename.
- Does not download cloud-storage links or provider-specific oversized attachments, unpack ZIP files, convert formats, or send mail.
- Requires IMAP over TLS with password/app-password authentication. OAuth, STARTTLS, automatic polling and resuming partial downloads are not supported.
- A cancelled attachment restarts from the beginning on retry. Previously completed books are retained.
- Deduplication uses the mailbox's UIDVALIDITY, message UID and MIME part. Sending the same book again creates a new attachment; content hashes are not compared.

## Account storage

The authorization code is stored locally, unencrypted, in `settings/sendtokoreader-account.json` under KOReader's data directory. The plugin requests `0600` permissions, but FAT storage may not enforce them. A dedicated receiving mailbox is recommended. Do not share that file; it is never part of a release package.

Download records are stored in `settings/sendtokoreader-state.json`. Switching accounts resets the attachment list and records while keeping downloaded books.

## Compatibility and development

This is an early preview. Local TLS IMAP communication and the headless macOS KOReader emulator have been tested. Real QQ/163 accounts, physical Kindle devices and manual touch interaction have not yet been verified.

CI runs static checks, builds a pinned KOReader emulator on Linux, exercises the TLS mailbox and native UI, and uploads test screenshots/logs. New versions on `main` are released only after those checks pass. `0.x` versions are marked as prereleases.

See [development and release instructions](docs/development.md) and [Changelog](CHANGELOG.md).

## License and acknowledgements

[MIT](LICENSE). The refresh icon is from [Lucide](https://github.com/lucide-icons/lucide/blob/0.468.0/icons/refresh-cw.svg) under its [ISC license](icons/LICENSE).

Built for [KOReader](https://github.com/koreader/koreader). Documentation structure follows [weread.koplugin](https://github.com/finlater/weread.koplugin) and [kindlebtcontroller.koplugin](https://github.com/finlater/kindlebtcontroller.koplugin).
