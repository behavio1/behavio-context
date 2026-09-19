# UI Screen Context

by Behavio

Talk to the active window, point with the cursor, and give an AI agent a compact folder instead of a full screen recording.

UI Screen Context is a native macOS utility built for bug reports, UI feedback, and agent-assisted work. It follows the active window as you switch apps and windows, transcribes speech locally in the selected language, tracks relevant pointer activity, detects visual changes, and compiles the result into a small text-first package.

## How it works

1. Put the window you want to explain in front.
2. Press **⌃⌘R**.
3. Confirm or change the active microphone from the picker in the Recording Capsule.
4. Speak naturally, point, pause over text, click, and scroll.
5. Stop with **Esc**, **⌃⌘R**, or the Stop button beside the timer.
6. Paste the resulting `context/` folder path into your agent. Post-processing is already complete.

The floating Recording Capsule shows elapsed time, a microphone picker, microphone level, live transcription, the current window, and a Stop action. Use its collapse/expand button to switch to a compact 300 × 44 pt bar with the timer, Stop, audio level, and a warning indicator. The compact view hides transcription and window/device names without changing what is recorded. The app remembers the selected view; hover over a warning indicator for details. Changing the microphone while recording switches the live input and persists the choice for the next session.

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

After Stop, the app retries missing speech against the finalized local recording, detects pointer dwell as well as clicks, and runs Apple Vision OCR near the pointer. `context.md` is an agent-ready timeline that joins speech with the visible text being indicated. Images are selected from clicks, pointer dwell, pointing language, transcript boundaries, visual changes, and sparse coverage. Near-duplicate OCR targets within the same window are collapsed. Schema 3 includes `window_timeline` with app, window ID, title and time intervals, plus window attribution for images and pointer events. Transitions are sampled; short visits and gaps are explicitly not evidence of continuous interaction. The first pass is capped at eight images with a 1280 px long edge; pointer-focused crops are capped at 768 px. No audio or video is written inside `context/`.

## Using the output with an AI agent

This repository includes the [read-behavio-context skill](.agents/skills/read-behavio-context/SKILL.md). It teaches an agent how to interpret speech, cursor targets, OCR uncertainty, missing images, and the difference between copied text and a local folder path. Agents in this project can discover it under `.agents/skills/`; using it in another project requires making the skill available there. Pasting the recording alone does not install the skill.

**Copy Path** and **Copy Path & Return** copy the local context folder path; **Copy Context Text** copies the Markdown text. If context compilation fails, the path can instead point to the saved MP4. **Copy Video & Return** places a video file URL on the clipboard. “Return” brings the previous app forward; it does not send a message. The latter does not attach the referenced images. For an agent without access to your Mac's files, attach the relevant context files explicitly.

In Settings, **Recordings and contexts folder** controls where new recordings are saved. Earlier recordings remain in their original folders and stay available in the recording list. **Show icon in menu bar** controls the menu containing start/stop, recordings, the recording folder, and settings.

## Language and settings

The interface supports English, Polish, Spanish, and German. **Follow System** matches the preferred languages and falls back to English. The separate **Spoken language** control selects English, Polish, Spanish or German for recognition. Choose Apple on-device recognition or local Whisper Small / Large v3 Turbo. The recording bar has the same language menu; changing it reprocesses the whole recording in that language when recording stops. Missing Apple models show setup instructions and a recheck action. The audio meter indicates input level independently of transcription.

**More Settings** expands by clicking its entire header. It contains the recording folder and menu-bar icon toggle with a matching icon preview. The menu provides Start/Stop, Recordings, Open Recordings Folder, and Settings. The app uses a simplified template version of its logo for the menu bar and its full icon in the Dock.

If context compilation fails after video capture succeeds, the saved MP4 remains available in Recordings with a separate context error.

## Privacy

- Follows the active window sequentially as you switch apps or windows; never falls back to capturing the whole display.
- Apple transcription requires on-device recognition; Whisper runs in a bundled native helper. Neither uploads recordings.
- Model downloads are explicit: Small is about 488 MB; Large v3 Turbo about 1.63 GB. Downloads have progress/cancel/retry and SHA-256 verification.
- **Use Existing Model…** accepts a compatible model file or folder, verifies it and imports a local copy. Existing `.pt` weights can be converted offline with `script/convert_existing_whisper.sh`; MLX files are a different format. No model is downloaded automatically.
- Does not record keystrokes. Escape exists only as a temporary stop hotkey while recording.
- Does not upload recordings, transcripts, screenshots, or analytics.
- Keeps raw MP4 material outside the folder supplied to the agent.

See the [privacy policy](docs/privacy.md).

## Requirements

- macOS 15 or newer; Apple live transcription requires an available offline model for the selected spoken language. Whisper transcribes the saved recording after stopping.
- Screen Recording and Microphone permissions.
- Input Monitoring is optional but required for pointer-aware moments outside the app.
- Swift 6.0+ for command-line builds, or Xcode for the Xcode project.

The app keeps recording and produces visual context if speech recognition or Input Monitoring is unavailable. `manifest.json` reports the real transcript status instead of pretending transcription succeeded.

## Build

Create an app bundle with the command-line toolchain:

```sh
./script/build_app.sh
open ".build/app/UI Screen Context.app"
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
- ScreenCaptureKit captures one `SCWindow` at a time through `desktopIndependentWindow`, replacing the stream when the active window changes. Source intervals identify each recorded window; transitions can contain gaps.
- Speech performs Apple local partial/final transcription in the selected language, with a local finalized-file retry. Whisper uses the finalized audio and preserves media-relative timestamps. Exported transcript metadata includes language, engine and a failure reason.
- A short-lived global pointer monitor records normalized mouse events only during recording.
- AVFoundation extracts and downsizes selected frames after the MP4 is finalized; Vision resolves nearby text at pointer dwell and click moments.
- The package writer validates a temporary directory before publishing `context/` atomically.

The implementation design and requirement mapping live in [docs/smart-agent-context-design.md](docs/smart-agent-context-design.md).

## License

UI Screen Context by Behavio is open-source software licensed under the [Apache License 2.0](LICENSE).

Anyone may download, use, modify, fork, and redistribute the software, including for commercial purposes. You do not have to publish your modifications. When redistributing it, include the license, preserve applicable copyright and attribution notices (including [NOTICE](NOTICE)), and clearly mark modified files.

The software is provided without warranties. Third-party components retain their own licenses; the license does not grant rights to use trademarks. See [LICENSE](LICENSE) for the full terms.

## Speech development checks

The app bundles a pinned native whisper.cpp runtime (v1.9.4), built by `script/build_whisper.sh`; model weights are not bundled or committed. CMake and a C++ compiler are required for packaging. Imported/downloaded models live in the app sandbox under `Application Support/BehavioContext/SpeechModels`.

On this machine, SDK 27 Command Line Tools lack SwiftUI macro/asset tools. The verified local build is:

```sh
./script/build_app.sh debug --build-system native --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
./script/test_core.sh --build-system native --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
```

Full Xcode is required for XCTest here. Project development guidance lives in `.agents/skills/macos-swift-development` and `.agents/skills/local-speech-recognition`, linked from `AGENTS.md`.

The copied context includes an agent response-language instruction derived from the recording’s saved speech language, independently of the app interface language. Structural headings remain English. Agents should generate responses directly in that language unless the user requests otherwise; transcript text, screen quotes, filenames and identifiers remain unchanged. Previously saved packages are not rewritten.

After a recording finishes compiling, its context text and local image-directory reference are copied to the clipboard automatically. A brief nonactivating notice confirms it is ready for ⌘V. The app does not open the results window or start playback; open Recordings to review a saved recording manually. If context generation fails, the recording stays saved and no success notice is shown.
