# 开发说明

[英文文档](development.md)

仓库根目录就是插件目录。运行文件位于 `_meta.lua`、`main.lua`、`sendtokoreader/`、`l10n/` 和 `icons/`。邮箱配置、测试档案、日志及生成的安装包不会提交到仓库。

## 本地检查

安装 LuaJIT、Luacheck、Python 3、OpenSSL 和 GNU gettext 后执行：

```sh
luacheck main.lua _meta.lua sendtokoreader tests
python3 -m py_compile scripts/*.py tests/*.py
python3 scripts/check_translations.py
python3 scripts/package_release.py
python3 tests/run.py /path/to/built/koreader
```

最后一条命令需要已构建的阅读器运行目录。脚本启动仅监听本机的加密测试邮箱，创建隔离配置，安装打包后的插件，然后分别使用简体中文和英文测试原生插件加载、界面、下载子进程和电子书阅读器。还会检查所有邮箱配置页并生成示例截图。测试不会使用真实账号或发邮件；截图和日志保存在 `tests/evidence/`。

无窗口渲染及处理函数测试不能替代实际触控、真实服务商登录和阅读器真机验证。

## 国际化

所有用户可见文案以英文作为消息标识，通过 `gettext()` 翻译；邮箱预设使用 `N_()` 标记。翻译时保留格式占位符。日期统一显示为数字年月日。附件文件名和邮箱地址属于用户数据，不作翻译。

插件复用阅读器的翻译文件读取器，取得自己的翻译表后立即还原阅读器原有的翻译表及复数规则。界面跟随阅读器当前语言，缺少翻译时回退为英文。新增语言只需添加 `l10n/<阅读器语言代码>/sendtokoreader.po`，正确填写语言、编码和复数规则，不需要增加语言专用代码。

修改文案或翻译后执行：

```sh
python3 scripts/check_translations.py --update
python3 scripts/check_translations.py
```

更新命令刷新模板并编译翻译。如果提示缺少翻译，补全源翻译文件后重新运行。模板、源翻译及编译结果都需要提交；自动检查会验证覆盖率、占位符及编译结果是否同步。安装包仅包含编译后的翻译文件。

## 固定版本模拟器

阅读器固定提交：`1e2fa5f1239028ab4b37acae833cdc86a71e5258`。

自动检查使用官方 Linux 构建容器 `koreader/kobase:1.0.0-22.04`，并缓存构建结果：

```sh
git clone --recurse-submodules https://github.com/koreader/koreader.git /tmp/koreader
cd /tmp/koreader
git checkout 1e2fa5f1239028ab4b37acae833cdc86a71e5258
git submodule update --init --recursive
cd /path/to/sendtokoreader.koplugin
bash scripts/build_koreader.sh /tmp/koreader
python3 tests/run.py /tmp/koreader/install/koreader
```

构建脚本校验固定提交，将不稳定的依赖下载地址替换为作者在 LuaRocks 发布的相同源码并校验摘要，不修改阅读器运行逻辑。苹果电脑还需要阅读器构建依赖及相应命令行工具；已有运行目录可以直接传给测试脚本。

## 自动检查与发布

拉取请求、主分支推送和手动运行都会执行静态检查、翻译检查、可复现打包和原生集成测试。两项检查通过后，主分支的新版本才会发布；拉取请求不能发布。

修改 `_meta.lua` 中的版本号，更新 `CHANGELOG.md` 和 `CHANGELOG_CN.md` 后推送。流水线自动创建版本标签、发布页、安装包和摘要文件，无需手动打标签。已有版本不会覆盖；`0.x` 版本标记为预发布。

下载后校验安装包：

```sh
sha256sum --check sendtokoreader.koplugin-v0.1.0.zip.sha256
unzip -l sendtokoreader.koplugin-v0.1.0.zip
```

苹果电脑使用 `shasum -a 256 -c`。压缩包只有一个 `sendtokoreader.koplugin/` 顶层目录，仅包含运行文件、编译后的翻译、中英文说明及许可证。打包脚本按允许列表收集文件，并逐个验证内容与源码一致。
