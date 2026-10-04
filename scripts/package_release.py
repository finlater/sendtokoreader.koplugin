#!/usr/bin/env python3
"""Build and verify an installable, deterministic plugin ZIP using an allowlist."""
import argparse
import hashlib
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parent.parent
PLUGIN = 'sendtokoreader.koplugin'


def version():
    match = re.search(r'^\s*version\s*=\s*"(\d+\.\d+\.\d+)"', (ROOT/'_meta.lua').read_text(), re.M)
    if not match:
        raise ValueError('_meta.lua must contain version = "X.Y.Z"')
    return match[1]


def release_notes():
    match = re.search(r'^## \[' + re.escape(version()) + r'\][^\n]*\n(.*?)(?=^## \[|\Z)', (ROOT/'CHANGELOG.md').read_text(), re.M | re.S)
    if not match or not match[1].strip():
        raise ValueError('CHANGELOG.md must have a nonempty section for the current version')
    return match[1].strip() + '\n'


def build(output):
    files = [ROOT/name for name in ('main.lua','_meta.lua','LICENSE','README.md','README_CN.md')]
    files += sorted((ROOT/'sendtokoreader').glob('*.lua'))
    files += sorted((ROOT/'l10n').rglob('*.mo'))
    files += [ROOT/'icons/refresh.svg', ROOT/'icons/LICENSE']
    output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(output,'w',zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(files):
            info = zipfile.ZipInfo(PLUGIN+'/'+file.relative_to(ROOT).as_posix(), (2026,1,1,0,0,0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info,file.read_bytes())
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None or len(archive.namelist()) != len(files):
            raise ValueError('Invalid plugin package')
        for file in files:
            if archive.read(PLUGIN+'/'+file.relative_to(ROOT).as_posix()) != file.read_bytes():
                raise ValueError('Package does not match source: '+str(file))
    checksum = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(output.suffix+'.sha256').write_text(f'{checksum}  {output.name}\n')
    output.with_suffix('.notes.md').write_text(release_notes())
    print(f'Verified {output.name}: {len(files)} files, SHA-256 {checksum}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output',nargs='?',type=Path)
    parser.add_argument('--version',action='store_true')
    args = parser.parse_args()
    if args.version:
        print(version())
    else:
        build(args.output or ROOT/'dist'/f'{PLUGIN}-v{version()}.zip')
