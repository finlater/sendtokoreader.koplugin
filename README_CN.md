# Send to KOReader · 邮件收书

[🇬🇧 English](README.md)

[![CI](https://github.com/finlater/sendtokoreader.koplugin/actions/workflows/ci.yml/badge.svg)](https://github.com/finlater/sendtokoreader.koplugin/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/finlater/sendtokoreader.koplugin?include_prereleases)](https://github.com/finlater/sendtokoreader.koplugin/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

在 KOReader 中通过自己的邮箱接收电子书。将电子书作为普通附件发到邮箱，在阅读器上刷新、选择并下载，即可开始阅读。

## 功能特性

- **使用自己的邮箱**：支持 QQ、163 和自定义 IMAP over TLS，无需中转服务。
- **简洁的绑定引导**：未绑定时只显示引导文案和「绑定邮箱」按钮。
- **手动刷新收信**：首次扫描最近 30 天的邮件，包含已读邮件；后续按 UID 增量检查。
- **多选下载**：逐本勾选或全选本页，显示所选大小，仅多页时显示分页控件。
- **后台传输**：显示下载进度，支持取消和单独重试失败项。
- **保留原邮件**：使用只读 IMAP 命令，不删除邮件、不改变已读状态。
- **保留本地文件**：已下载且文件仍存在时跳过；不同附件同名时自动加序号，不覆盖原文件。
- **直接阅读**：点击已下载附件，使用 KOReader 打开电子书。

## 界面截图

以下为 KOReader 原生模拟器使用示例数据渲染的页面。当前插件界面为中文。

| 绑定引导 | 附件列表 | 下载进度 |
|:---:|:---:|:---:|
| ![绑定引导](screenshots/welcome.png) | ![附件列表](screenshots/inbox.png) | ![下载进度](screenshots/progress.png) |

## 安装

1. 前往 [GitHub Releases](https://github.com/finlater/sendtokoreader.koplugin/releases)，下载 `sendtokoreader.koplugin-vX.Y.Z.zip`。
2. 解压得到 `sendtokoreader.koplugin` 文件夹。
3. 将整个文件夹复制到 KOReader 的插件目录：

```text
koreader/plugins/sendtokoreader.koplugin/
```

4. 重启 KOReader，打开 **工具 → Send to KOReader · 邮件收书**。

也可以将仓库源码克隆到上述插件目录，并将文件夹命名为 `sendtokoreader.koplugin`。更新时覆盖插件文件并重启 KOReader；邮箱设置和下载记录保存在独立目录。

## 绑定与收书

1. 在邮箱设置中开启 IMAP，生成客户端授权码或应用专用密码。
2. 点击 **绑定邮箱**，选择服务商，填写邮箱地址和授权码。
3. 自定义邮箱需在 **服务器设置** 中填写 IMAP 主机名和 TLS 端口。
4. 点击 **验证并保存**。
5. 将电子书作为普通附件发送到该邮箱，返回列表点击刷新图标，勾选附件后点击 **下载所选**。

| 服务商 | IMAP 服务器 | TLS 端口 | 登录凭据 |
|---|---|---|---|
| QQ 邮箱 | `imap.qq.com` | `993` | 客户端授权码 |
| 163 邮箱 | `imap.163.com` | `993` | 客户端授权码 |
| 自定义 | 服务商提供的主机名 | 通常为 `993` | IMAP 密码或应用专用密码 |

当前只支持一个邮箱及其收件箱。在 **设置 → 下载目录** 中选择保存位置；默认保存到 KOReader 下载目录或主目录下的 `收书` 文件夹。

## 支持格式与范围

识别以下附件扩展名：`epub`、`pdf`、`mobi`、`azw`、`azw3`、`fb2`、`txt`、`djvu`、`djv`、`cbz`、`cbr`。实际阅读能力由 KOReader 决定。

- 支持 Base64、Quoted-Printable 和未编码 MIME 附件、中文编码文件名及 RFC2231 参数；无法转换的字符集会回退为安全的 ASCII 文件名。
- 不获取网盘链接和服务商专用的超大附件，不解压 ZIP、不转换格式、不发送邮件。
- 要求 IMAP over TLS 和密码／授权码认证，暂不支持 OAuth、STARTTLS、自动轮询和断点续传。
- 取消后重新下载该附件；之前已完成的电子书会保留。
- 根据邮箱 UIDVALIDITY、邮件 UID 和 MIME 部分编号去重。重新发送同一本书会被视为新附件，不比较文件内容哈希。

## 配置保存

客户端授权码未加密保存在 KOReader 数据目录下的 `settings/sendtokoreader-account.json`。插件请求 `0600` 文件权限，但 FAT 分区可能不执行这些权限，建议使用专用收书邮箱。请勿分享该配置文件；安装包不会包含它。

下载记录保存在 `settings/sendtokoreader-state.json`。切换邮箱会重置附件列表和下载记录，已经保存的电子书仍然保留。

## 兼容性与开发

当前为早期预览版本。已验证本地 TLS IMAP 通信和 macOS 无窗口 KOReader 原生模拟器；QQ/163 真实账号、Kindle 真机和手动触控仍待验证。

CI 会执行静态检查、构建固定版本的 Linux KOReader 模拟器、测试 TLS 收信和原生界面，并上传测试截图与日志。`main` 分支的新版本仅在检查通过后自动发布；`0.x` 版本标记为预发布。

开发、测试和发布方式见 [开发说明](docs/development.md)，版本变化见 [更新日志](CHANGELOG.md)。

## 许可证与致谢

使用 [MIT 许可证](LICENSE)。刷新图标来自 [Lucide](https://github.com/lucide-icons/lucide/blob/0.468.0/icons/refresh-cw.svg)，遵循 [ISC 许可证](icons/LICENSE)。

基于 [KOReader](https://github.com/koreader/koreader) 插件接口实现。文档结构参考 [weread.koplugin](https://github.com/finlater/weread.koplugin) 和 [kindlebtcontroller.koplugin](https://github.com/finlater/kindlebtcontroller.koplugin)。
