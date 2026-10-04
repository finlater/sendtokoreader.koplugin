# Development / 开发说明

The repository root is the plugin directory. Runtime files are `_meta.lua`, `main.lua`, `sendtokoreader/` and `icons/`. Settings, test profiles, logs and generated ZIP files are not tracked.

仓库根目录就是插件目录。运行文件位于 `_meta.lua`、`main.lua`、`sendtokoreader/` 和 `icons/`。邮箱配置、测试档案、日志及生成的安装包不会提交到仓库。

## Local checks / 本地检查

```sh
luacheck main.lua _meta.lua sendtokoreader tests
python3 -m py_compile scripts/*.py tests/*.py
python3 scripts/package_release.py
python3 tests/run.py /path/to/built/koreader
```

The last command needs an existing KOReader runtime with `luajit`, `reader.lua`, `frontend`, `libs` and the data files. It starts a loopback-only TLS IMAP fixture, creates a temporary KOReader profile, installs the packaged plugin, and exercises the real PluginLoader, widgets, subprocess downloads and EPUB reader. Tests never send email or use a real account. OpenSSL and Python 3 are required. Artifacts are written to `tests/evidence/`.

最后一条命令使用已构建的 KOReader 运行目录，启动仅监听本机的 TLS IMAP 测试邮箱，创建临时配置，安装打包后的插件，并测试原生 PluginLoader、界面、下载子进程和 EPUB 阅读器。测试不会发邮件或使用真实账号。需要 OpenSSL 和 Python 3；截图及日志保存在 `tests/evidence/`。

## Pinned emulator / 固定版本模拟器

KOReader commit: `1e2fa5f1239028ab4b37acae833cdc86a71e5258`.

CI uses the official `koreader/kobase:1.0.0-22.04` Linux build container and caches the build output:

```sh
git clone --recurse-submodules https://github.com/koreader/koreader.git /tmp/koreader
cd /tmp/koreader
git checkout 1e2fa5f1239028ab4b37acae833cdc86a71e5258
git submodule update --init --recursive
cd /path/to/sendtokoreader.koplugin
bash scripts/build_koreader.sh /tmp/koreader
python3 tests/run.py /tmp/koreader/install/koreader
```

`build_koreader.sh` verifies the commit and replaces the unreliable Lua-Spore download URL with the author's identical LuaRocks source archive, checked against SHA-256. It does not patch KOReader's runtime behavior. A macOS build also needs KOReader's development dependencies and Homebrew Bash/GNU tools; a previously built runtime can be passed directly to `tests/run.py`.

构建脚本校验固定 commit，并将不稳定的 Lua-Spore 下载地址替换为作者在 LuaRocks 发布的相同源码，使用 SHA-256 校验，不修改 KOReader 的运行逻辑。macOS 还需要 KOReader 构建依赖及 Homebrew Bash/GNU 工具；已有运行目录可以直接用于测试。

Headless native rendering is separate from manual input, real provider authentication and Kindle hardware verification. Do not describe the local fixture as a tested QQ/163 account.

无窗口原生渲染、手动输入、真实服务商登录和 Kindle 真机是不同的验证范围，不能将测试邮箱结果描述为 QQ/163 实测。

## CI/CD and releases / 自动检查与发布

One workflow runs on pull requests, `main` pushes and manual dispatch:

1. Lua lint/syntax, Python syntax, changelog validation and deterministic ZIP packaging.
2. A source-built Linux KOReader emulator runs the TLS and native UI checks.
3. Only after both jobs succeed, a `main` push or manual run creates a GitHub Release if the version is new. Pull requests cannot publish.

修改 `_meta.lua` 中的 `X.Y.Z` 版本号，并在 `CHANGELOG.md` 添加对应中英文说明后推送到 `main`。两项检查通过后，Actions 自动创建 `vX.Y.Z` 标签、Release、ZIP 和 SHA-256 校验文件，不需要手动打标签。`0.x` 为预发布。同一版本已发布时跳过，不覆盖已有资产。

The version in `_meta.lua` is the release source of truth. Add matching bilingual notes to `CHANGELOG.md`, then push to `main`. Actions creates the tag and release; do not create tags manually. Existing releases are left unchanged. `0.x` releases are prereleases.

To verify a downloaded release:

```sh
sha256sum --check sendtokoreader.koplugin-v0.1.0.zip.sha256
unzip -l sendtokoreader.koplugin-v0.1.0.zip
```

On macOS, use `shasum -a 256 -c` instead of `sha256sum --check`. The archive has one top-level `sendtokoreader.koplugin/` directory and only runtime files, bilingual READMEs and licenses. `scripts/package_release.py` uses an allowlist and verifies every archived file against its source.
