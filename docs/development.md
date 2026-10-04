# Development

[Chinese documentation](development_CN.md)

The repository root is the plugin directory. Runtime files are `_meta.lua`, `main.lua`, `sendtokoreader/`, `l10n/` and `icons/`. Settings, test profiles, logs and generated packages are not tracked.

## Local checks

Install LuaJIT, Luacheck, Python 3, OpenSSL and GNU gettext, then run:

```sh
luacheck main.lua _meta.lua sendtokoreader tests
python3 -m py_compile scripts/*.py tests/*.py
python3 scripts/check_translations.py
python3 scripts/package_release.py
python3 tests/run.py /path/to/built/koreader
```

The final command needs an existing KOReader runtime containing `luajit`, `reader.lua`, `frontend`, `libs` and data files. It creates a loopback TLS mailbox and isolated profiles, installs the packaged plugin, and exercises the real PluginLoader, widgets, subprocess downloads and EPUB reader in English and Simplified Chinese. It also checks every provider page and captures example screenshots. Tests do not use real accounts or send email. Screenshots and logs go to `tests/evidence/`.

Headless rendering and handler tests do not establish physical touch behavior, real provider authentication or Kindle compatibility.

## Translations

User-facing strings use English message IDs passed to `gettext()` or marked with `N_()` in provider definitions. Keep format placeholders unchanged. Dates use numeric year-month-day notation. Attachment filenames and mailbox addresses are user data and are not translated.

The plugin uses KOReader's MO reader, captures its own translation table, and immediately restores KOReader's catalog and plural rules. It follows the current KOReader language; missing languages fall back to English. Add translations in `l10n/<KOReader language code>/sendtokoreader.po`, with the correct language, encoding and plural headers. No language-specific code branches are needed.

After editing source strings or catalogs:

```sh
python3 scripts/check_translations.py --update
python3 scripts/check_translations.py
```

The update command refreshes the template and compiles catalogs. It will report missing translations; complete the PO file, then rerun it. Commit the PO, MO and POT files. CI checks complete coverage, format placeholders and matching compiled catalogs. Only compiled MO files are included in release packages.

## Pinned emulator

KOReader commit: `1e2fa5f1239028ab4b37acae833cdc86a71e5258`.

CI uses the official `koreader/kobase:1.0.0-22.04` Linux container and caches build output:

```sh
git clone --recurse-submodules https://github.com/koreader/koreader.git /tmp/koreader
cd /tmp/koreader
git checkout 1e2fa5f1239028ab4b37acae833cdc86a71e5258
git submodule update --init --recursive
cd /path/to/sendtokoreader.koplugin
bash scripts/build_koreader.sh /tmp/koreader
python3 tests/run.py /tmp/koreader/install/koreader
```

The build script verifies the commit and uses the author's identical LuaRocks source archive for Lua-Spore, verified by SHA-256, to avoid an unreliable download host. KOReader's runtime behavior is not patched. macOS also needs KOReader's build dependencies and Homebrew Bash/GNU tools; an existing runtime can be passed directly to the test runner.

## CI/CD and releases

Pull requests, pushes to `main` and manual runs execute static checks, translation checks, deterministic packaging and native integration. Only after both check jobs pass can a new version on `main` create a release. Pull requests cannot publish.

Set `version` in `_meta.lua`, update `CHANGELOG.md` and `CHANGELOG_CN.md`, and push to `main`. Actions creates the version tag, release, ZIP and SHA-256 file; do not create tags manually. Existing releases are left unchanged. Versions beginning with `0.` are prereleases.

Verify downloaded assets:

```sh
sha256sum --check sendtokoreader.koplugin-v0.1.0.zip.sha256
unzip -l sendtokoreader.koplugin-v0.1.0.zip
```

On macOS, use `shasum -a 256 -c`. The archive has one `sendtokoreader.koplugin/` directory containing only runtime files, compiled catalogs, the two READMEs and licenses. Packaging uses an allowlist and verifies every archived file against its source.
