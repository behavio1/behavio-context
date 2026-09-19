#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Pinned native offline runtime. Model weights are selected separately by the user.
root="$PWD/.build/whisper-native"
if [ ! -f "$root/source/CMakeLists.txt" ]; then
    mkdir -p "$root"
    curl --fail --location --retry 2 https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.9.4.tar.gz -o "$root/source.tar.gz"
    mkdir -p "$root/source"
    tar -xzf "$root/source.tar.gz" --strip-components=1 -C "$root/source"
fi
cmake -S "$root/source" -B "$root/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DGGML_NATIVE=OFF -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON
cmake --build "$root/build" --config Release --target whisper-cli -j 4
