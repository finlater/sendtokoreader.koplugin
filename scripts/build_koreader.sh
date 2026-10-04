#!/usr/bin/env bash
set -euo pipefail

koreader_dir="$(cd "${1:?Usage: build_koreader.sh /path/to/pinned/koreader}" && pwd)"
expected=1e2fa5f1239028ab4b37acae833cdc86a71e5258
if [[ "$(git -C "$koreader_dir" rev-parse HEAD)" != "$expected" ]]; then
    echo "Expected KOReader commit $expected" >&2
    exit 1
fi

# The pinned Lua-Spore source host is unreliable. Use the author's identical
# 0.4.2 LuaRocks source archive, verifying SHA-256 before changing its URL.
python3 - "$koreader_dir" <<'PY'
import hashlib
import io
from pathlib import Path
import re
import sys
import urllib.request
import zipfile
root = Path(sys.argv[1])
archive = root/'base/thirdparty/lua-Spore/build/downloads/lua-spore-0.4.2.tar.gz'
expected = '15d851238abd2243a797d90d5e7f99687f084b63fe5e873131cfddbf4f95e88a'
if not archive.exists() or hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
    with urllib.request.urlopen('https://luarocks.org/lua-spore-0.4.2-1.src.rock',timeout=60) as response:
        with zipfile.ZipFile(io.BytesIO(response.read())) as rock:
            data = rock.read('lua-spore-0.4.2.tar.gz')
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError('Lua-Spore source checksum mismatch')
    archive.parent.mkdir(parents=True,exist_ok=True)
    archive.write_bytes(data)
cmake = root/'base/thirdparty/lua-Spore/CMakeLists.txt'
text, count = re.subn(r'DOWNLOAD (?:GIT|URL) .*?\n\s*\S+', 'DOWNLOAD URL b285fb5b86deac030ccffb4c264d2127\n    '+archive.as_uri(), cmake.read_text(), count=1)
if count != 1:
    raise ValueError('Pinned Lua-Spore download declaration changed')
cmake.write_text(text)
PY

cd "$koreader_dir"
make OUTPUT_DIR=build PARALLEL_JOBS=3 INSTALL_DIR=install all
