"""Check the distributable bundle, including files compiler-only checks miss."""
import plistlib
import sys
from pathlib import Path

app = Path(sys.argv[1])
contents = app / 'Contents'
info = plistlib.loads((contents / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'one.behavio.context'
for relative in ('MacOS/BehavioContext', 'Helpers/whisper-cli'):
    data = (contents / relative).read_bytes()
    assert b'/Users/' not in data, f'Local developer path in {relative}'
for name in ('BehavioContext.icns', 'Whisper-LICENSE', 'LICENSE', 'NOTICE'):
    assert (contents / 'Resources' / name).is_file(), f'Missing {name}'
for locale in ('en', 'pl', 'es', 'de'):
    assert (contents / 'Resources' / f'{locale}.lproj' / 'Localizable.strings').is_file()
for path in app.rglob('*'):
    if path.is_file():
        assert path.suffix not in ('.swift', '.xcstrings', '.mp4', '.bin'), f'Unexpected distribution file: {path.name}'
        assert path.name not in ('.env', 'SKILL.md', 'translations.valid'), f'Unexpected distribution file: {path.name}'
print('PASS: release bundle identity, helper, licenses, locales and internal-file exclusions')
