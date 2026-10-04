#!/usr/bin/env python3
"""Check catalog coverage, format placeholders and compiled translations (requires gettext)."""
import argparse
from pathlib import Path
import subprocess
import re
import tempfile

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--update', action='store_true', help='update template and compile translated catalogs')
args = parser.parse_args()
files = ['main.lua', '_meta.lua'] + sorted(str(p.relative_to(ROOT)) for p in (ROOT/'sendtokoreader').glob('*.lua'))
with tempfile.TemporaryDirectory() as tmp:
    template = Path(tmp)/'messages.pot'
    subprocess.run(['xgettext', '--language=Lua', '--from-code=UTF-8', '--keyword=gettext', '--keyword=N_',
                    '--no-location', '--sort-output', '-o', str(template), *files], cwd=ROOT, check=True)
    template.write_text(re.sub(r'POT-Creation-Date: [^\\]+', 'POT-Creation-Date: 2026-10-04 00:00+0000', template.read_text()))
    saved_template = ROOT/'l10n/sendtokoreader.pot'
    if args.update:
        saved_template.write_bytes(template.read_bytes())
    else:
        for current, expected in ((saved_template, template), (template, saved_template)):
            subprocess.run(['msgcmp', '--use-untranslated', '--no-fuzzy-matching', str(current), str(expected)], check=True)
    for po in sorted((ROOT/'l10n').glob('*/*.po')):
        subprocess.run(['msgcmp', '--no-fuzzy-matching', str(po), str(template)], check=True)
        compiled = Path(tmp)/'messages.mo'
        subprocess.run(['msgfmt', '--check', '--check-format', '-o', str(compiled), str(po)], check=True)
        mo = po.with_suffix('.mo')
        if args.update:
            mo.write_bytes(compiled.read_bytes())
        else:
            assert mo.read_bytes() == compiled.read_bytes(), f'Recompile {po}'
        print(f'PASS complete and compiled catalog: {po.parent.name}')
