#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ "$#" -ne 2 ]; then
    echo 'Usage: script/convert_existing_whisper.sh /path/to/model.pt /path/to/output-folder' >&2
    exit 2
fi
converter="$PWD/.build/whisper-native/source/models/convert-pt-to-ggml.py"
if [ ! -f "$converter" ]; then
    echo 'Build the native runtime first with script/build_whisper.sh (source code only, no model weights).' >&2
    exit 1
fi
assets="$(python3 -c 'import pathlib, whisper; print(pathlib.Path(whisper.__file__).parent.parent)')"
mkdir -p "$2"
python3 "$converter" "$1" "$assets" "$2"
echo 'Conversion complete. Choose the output folder using Use Existing Model in the app.'
