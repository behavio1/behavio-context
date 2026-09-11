# Behavio Context

Talk to the active window, point with the cursor, and give an AI agent a compact folder instead of a full screen recording.

Behavio Context is a native macOS utility built for bug reports, UI feedback, and agent-assisted work. It records one active window, transcribes Polish speech locally, tracks relevant pointer activity, detects visual changes, and compiles the result into a small text-first package.

## How it works

1. Put the window you want to explain in front.
2. Press **⌃⌘R**.
3. Confirm or change the active microphone from the picker in the Recording Capsule.
4. Speak naturally, point, pause over text, click, and scroll.
5. Stop with **Esc**, **⌃⌘R**, or the Stop button beside the timer.
6. Paste the resulting `context/` folder path into your agent. Post-processing is already complete.

The floating Recording Capsule stays outside the captured window and shows elapsed time, the selected microphone with a live device picker, microphone level, live transcription, the selected window, and a clear Stop action. Changing the microphone while recording switches the live input and persists the choice for the next session.

## Agent package

```text
Behavio Context YYYY-MM-DD HH-MM-SS/
├── recording.mp4              # local source, not part of agent input
└── context/
    ├── context.md             # read this first
    ├── manifest.json          # synchronized timeline with local OCR targets
    ├── transcript.json        # final local transcript
    ├── recommended/           # up to 8 first-pass images
    └── on-demand/             # additional indexed evidence when needed
```

After Stop, the app retries missing speech against the finalized local recording, detects pointer dwell as well as clicks, and runs Apple Vision OCR near the pointer. `context.md` is an agent-ready timeline that joins speech with the visible text being indicated. Images are selected from clicks, pointer dwell, pointing language, transcript boundaries, visual changes, and sparse coverage. Near-duplicate OCR targets are collapsed. The first pass is capped at eight images with a 1280 px long edge; pointer-focused crops are capped at 768 px. No audio or video is written inside `context/`.

## Privacy

- Captures only the window that was active when recording started.
- Polish transcription requests on-device recognition and never falls back to cloud recognition.
- Does not record keystrokes. Escape exists only as a temporary stop hotkey while recording.
- Does not upload recordings, transcripts, screenshots, or analytics.
- Keeps raw MP4 material outside the folder supplied to the agent.

See the [privacy policy](docs/privacy.md).

## Requirements

- macOS 15 or newer; local live transcription requires the Polish on-device speech model available on the Mac.
- Screen Recording and Microphone permissions.
- Input Monitoring is optional but required for pointer-aware moments outside the app.
- Swift 6.0+ for command-line builds, or Xcode for the Xcode project.

The app keeps recording and produces visual context if speech recognition or Input Monitoring is unavailable. `manifest.json` reports the real transcript status instead of pretending transcription succeeded.

## Build

Create an app bundle with the command-line toolchain:

```sh
./script/build_app.sh
open ".build/app/Behavio Context.app"
```

The script uses `BEHAVIO_CONTEXT_SIGNING_IDENTITY` when supplied, or the local
`Behavio Context Local Development` identity when installed. Otherwise it falls
back to ad-hoc signing. macOS binds Screen Recording permission to the code
identity, so an ad-hoc build needs its permission refreshed after the binary is
rebuilt; ordinary relaunches of the same binary do not.

Or open `BehavioContext.xcodeproj` in Xcode and select the `BehavioContext` scheme.

## Test

```sh
./script/test_core.sh          # deterministic compiler/package test
./script/check_native_only.sh # dependency and privacy contract
./script/test_unit.sh          # XCTest suite (requires full Xcode)
./script/test_integration.sh   # media integration suite (requires full Xcode)
```

`test_core.sh` generates a real H.264 fixture, compiles a complete context folder, validates its JSON contract and image limits, rejects audio/video leakage, and checks at least 80% first-pass image reduction against naive 1 fps sampling.

## Architecture

- SwiftUI and AppKit provide the menu bar app and nonactivating Recording Capsule.
- ScreenCaptureKit captures a frozen `SCWindow` through `desktopIndependentWindow`.
- Speech performs local Polish partial/final transcription, with a local finalized-file retry when live recognition has no result.
- A short-lived global pointer monitor records normalized mouse events only during recording.
- AVFoundation extracts and downsizes selected frames after the MP4 is finalized; Vision resolves nearby text at pointer dwell and click moments.
- The package writer validates a temporary directory before publishing `context/` atomically.

The implementation design and requirement mapping live in [docs/smart-agent-context-design.md](docs/smart-agent-context-design.md).

## License and attribution

Apache-2.0. Behavio Context is a modified derivative of [ScreenContext](https://github.com/marcusschiesser/screencontext). The original copyright and required notices are preserved in [NOTICE](NOTICE). Behavio Context does not use the ScreenContext name or branding.
