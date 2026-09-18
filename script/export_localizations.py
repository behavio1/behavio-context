"""Export the checked string catalog to standard macOS bundle resources.

Used by the command-line packager, including builds without Xcode's catalog compiler.
"""
import json
from pathlib import Path
import sys

catalog = json.loads(Path('Sources/BehavioContext/Resources/Localizable.xcstrings').read_text())
resources = Path(sys.argv[1])
for language in ('en', 'pl', 'es', 'de'):
    directory = resources / f'{language}.lproj'
    directory.mkdir(parents=True, exist_ok=True)
    lines = []
    for key, entry in sorted(catalog['strings'].items()):
        value = entry['localizations'][language]['stringUnit']['value']
        lines.append(f'{json.dumps(key, ensure_ascii=False)} = {json.dumps(value, ensure_ascii=False)};')
    (directory / 'Localizable.strings').write_text('\n'.join(lines) + '\n')
permissions = {
    'en': ['UI Screen Context uses the microphone for local transcription.', 'UI Screen Context follows the active window when you switch apps or windows.', 'UI Screen Context transcribes speech locally to create context for your agent.'],
    'pl': ['UI Screen Context używa mikrofonu do lokalnej transkrypcji.', 'UI Screen Context nagrywa aktywne okno podczas przełączania aplikacji i okien.', 'UI Screen Context transkrybuje mowę lokalnie, aby utworzyć kontekst dla agenta.'],
    'es': ['UI Screen Context usa el micrófono para la transcripción local.', 'UI Screen Context sigue la ventana activa al cambiar de aplicación o ventana.', 'UI Screen Context transcribe la voz localmente para crear contexto para tu agente.'],
    'de': ['UI Screen Context verwendet das Mikrofon für die lokale Transkription.', 'UI Screen Context folgt dem aktiven Fenster beim Wechseln von Apps oder Fenstern.', 'UI Screen Context transkribiert Sprache lokal, um Kontext für deinen Agenten zu erstellen.'],
}
for language, values in permissions.items():
    keys = ['NSMicrophoneUsageDescription', 'NSScreenCaptureUsageDescription', 'NSSpeechRecognitionUsageDescription']
    (resources / f'{language}.lproj' / 'InfoPlist.strings').write_text('\n'.join(f'{json.dumps(k)} = {json.dumps(v, ensure_ascii=False)};' for k, v in zip(keys, values)) + '\n')
