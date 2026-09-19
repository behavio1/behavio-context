#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if find "$ROOT_DIR" \
  -path "$ROOT_DIR/.git" -prune -o \
  -type d -name .build -prune -o \
  -path "$ROOT_DIR/dist" -prune -o \
  -type f \( \
    -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o \
    -name 'package.json' -o -name 'package-lock.json' -o -name 'yarn.lock' -o \
    -name 'pnpm-lock.yaml' \
  \) -print -quit | grep -q .; then
  echo "Native-only check failed: JavaScript or TypeScript artifact found." >&2
  exit 1
fi

if find "$ROOT_DIR" \
  -path "$ROOT_DIR/.git" -prune -o \
  -type d -name .build -prune -o \
  -path "$ROOT_DIR/dist" -prune -o \
  -type d -name node_modules -print -quit | grep -q .; then
  echo "Native-only check failed: node_modules found." >&2
  exit 1
fi

if rg -i --glob '!README.md' --glob '!check_native_only.sh' \
  --glob '!.git/**' --glob '!**/.build/**' --glob '!dist/**' \
  '\b(electron|wkwebview|webview|ffmpeg)\b' "$ROOT_DIR" >/dev/null; then
  echo "Native-only check failed: forbidden runtime reference found." >&2
  exit 1
fi

if rg -q 'com\.apple\.security\.(network\.server|device\.camera)' \
  "$ROOT_DIR/BehavioContext.entitlements"; then
  echo "Privacy check failed: release entitlements include server or camera access." >&2
  exit 1
fi

if ! rg -q 'requiresOnDeviceRecognition = true' \
  "$ROOT_DIR/Sources/BehavioContextCore/Services/SmartContextCaptureCoordinator.swift"; then
  echo "Privacy check failed: local speech recognition is not enforced." >&2
  exit 1
fi

if ! rg -q 'SFSpeechURLRecognitionRequest' \
  "$ROOT_DIR/Sources/BehavioContextCore/Services/SmartContextCaptureCoordinator.swift" \
  || ! rg -q 'VNRecognizeTextRequest' \
  "$ROOT_DIR/Sources/BehavioContextCore/Services/AgentContextVisionAnalyzer.swift"; then
  echo "Post-processing check failed: finalized-file speech or local pointer OCR is missing." >&2
  exit 1
fi

if ! rg -q 'Menu \{' \
  "$ROOT_DIR/Sources/BehavioContext/Panels/RecordingFeedbackPanelController.swift" \
  || ! rg -q 'selectMicrophoneDevice' \
  "$ROOT_DIR/Sources/BehavioContextCore/Services/ScreenCaptureRecordingPipeline.swift"; then
  echo "Microphone UX check failed: capsule picker or live device switching is missing." >&2
  exit 1
fi

if ! rg -q 'CGPreflightScreenCaptureAccess' \
  "$ROOT_DIR/Sources/BehavioContextCore/Services/ScreenCaptureKitScreenCatalog.swift" \
  || ! rg -q 'dismissFeedback' \
  "$ROOT_DIR/Sources/BehavioContext/Panels/RecordingFeedbackPanelController.swift"; then
  echo "Permission UX check failed: launch preflight or dismissible error capsule is missing." >&2
  exit 1
fi

if ! rg -q 'keyCode: UInt16\(kVK_ANSI_R\)' \
  "$ROOT_DIR/Sources/BehavioContextCore/Models/GlobalShortcut.swift" \
  || ! rg -q 'modifiers: UInt32\(cmdKey \| controlKey\)' \
  "$ROOT_DIR/Sources/BehavioContextCore/Models/GlobalShortcut.swift"; then
  echo "Shortcut check failed: the original Control-Command-R default changed." >&2
  exit 1
fi

if ! rg -q 'SCContentFilter\(desktopIndependentWindow:' \
  "$ROOT_DIR/Sources/BehavioContextCore/Services/ScreenCaptureKitContentFilterFactory.swift"; then
  echo "Capture check failed: active-window filtering is missing." >&2
  exit 1
fi

echo "Native-only, privacy, shortcut, and active-window checks passed."
