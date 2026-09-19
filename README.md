# UI Screen Context

by Behavio

Show an AI agent what you want changed: point at the screen, explain it aloud, then paste the recorded context.

UI Screen Context records the active window as you switch between apps. It combines local speech transcription, cursor positions and selected screenshots into a context package for your agent. Use it to explain a UI change or show how to reproduce a bug.

## Watch the demo

[Watch UI Screen Context on YouTube](https://www.youtube.com/watch?v=K5U635NP1BM) — a 42-second demo of recording spoken UI feedback, pointing at an element and passing the context to OpenCode.

Shorts: [full workflow](https://www.youtube.com/shorts/Bh-CaUKFr-k) · [UI change example](https://www.youtube.com/shorts/rKlTONIWrDc) · [quick demo](https://www.youtube.com/shorts/4r4s55Erzgc).

The videos use a staged workflow and AI-generated presenters. The before-and-after screens show a real local UI change.

## How it works

1. Put the window you want to explain in front.
2. Before your first recording, review the [permissions](#permissions-before-your-first-recording), then choose your microphone, spoken language and local speech engine in Settings.
3. Press **⌃⌘R**. The Recording Capsule lets you change the microphone and spoken language during recording.
4. Speak naturally, point, pause over text, click, and scroll.
5. Stop with **Esc**, **⌃⌘R**, or the Stop button beside the timer.
6. Wait for **“Context copied. Share it with your agent.”** The completed context text and its local image-directory reference are now in your clipboard. Paste into your agent; the app stays in the background.

Open **Recordings** when you want to review a saved recording. Results do not open automatically, and playback waits for you to press Play.

The floating Recording Capsule shows elapsed time, microphone selection and level, the spoken-language menu, the current window, and Stop. Apple recognition can show live transcription; Whisper transcribes after you stop. The compact bar keeps the timer, Stop, audio level, spoken-language menu and warning indicator, while hiding transcription and window/device names. The app remembers the selected view. Changing the microphone switches the live input and persists the choice for the next session.

## Permissions before your first recording

macOS asks for access as you enable recording features. Review these before starting a recording you want to keep:

| Access | When you need it | What the app uses it for |
| --- | --- | --- |
| **Screen Recording** | Required to capture a window. | Records the active window as you switch apps. Without it, the app cannot capture your screen evidence. |
| **Microphone** | When the microphone is enabled. | Records your spoken explanation for local transcription. You can leave the microphone off to capture visual context only. |
| **Speech Recognition** | When using **Apple · On this Mac**. | Lets Apple's on-device recognizer transcribe your speech. A supported offline language model must also be available. Local Whisper does not require this permission. |
| **Input Monitoring** | Requested when recording starts; recommended for pointer evidence. | Captures mouse movement, clicks and scrolling outside the app while recording. Without access, pointer-event coverage may be incomplete. The app does not record typed keys. |
| **Selected files and folders** | When you choose a recording folder or import an existing Whisper model. | The macOS file picker grants access to the location you select. Model import makes a local copy; changing the recording folder affects new recordings. |

If you deny a permission, open **System Settings → Privacy & Security** and enable UI Screen Context in the relevant category. Screen capture may appear under **Screen & System Audio Recording**, depending on your macOS version. Follow any macOS instruction to quit and reopen the app, then try a short recording.

**Accessibility**, **Full Disk Access** and **Camera** access are not required for this workflow.

After Stop, the app writes the completed context to your clipboard and shows an in-app confirmation. This replaces the previous clipboard contents. A separate AI agent still needs access to the referenced local files, or you need to attach them yourself; granting this app folder access does not grant access to another app.

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

After Stop, Whisper transcribes the finalized local recording; Apple recognition can retry missing speech locally. The app detects pointer dwell as well as clicks, and runs Apple Vision OCR near the pointer. `context.md` is an agent-ready timeline that associates speech with nearby pointer evidence by time. This association does not prove which element the user meant. When OCR finds no label, the timeline retains selected pointer positions with full-canvas images instead of inventing a target name. Images are selected from clicks, pointer dwell, pointing language, transcript boundaries, visual changes, and sparse coverage. Near-duplicate OCR targets within the same window are collapsed. Schema 3 includes `window_timeline` with app, window ID, title and time intervals, plus window attribution for images and pointer events. Transitions are sampled; short visits and gaps are explicitly not evidence of continuous interaction. The first pass is capped at eight images with a 1280 px long edge; pointer-focused crops are capped at 768 px. No audio or video is written inside `context/`.

## Using the output with an AI agent

This repository includes the [read-behavio-context skill](.agents/skills/read-behavio-context/SKILL.md). It teaches an agent how to interpret speech, cursor targets, OCR uncertainty, missing images, and the difference between copied text and a local folder path. Agents in this project can discover it under `.agents/skills/`; using it in another project requires making the skill available there. Pasting the recording alone does not install the skill.

Context text is copied automatically once processing finishes. **Copy Context Text** copies it again, including the current local context directory. Neither action attaches images. A local agent can resolve image paths using that directory; for an agent without access to your Mac, attach the referenced images or context files explicitly.

**Copy Path** and **Copy Path & Return** copy only the local context folder path; if context compilation fails, the path can instead point to the saved MP4. **Copy Video & Return** places a video file URL on the clipboard; the receiving app determines whether it becomes an attachment. “Return” brings the previous app forward without sending a message.

In Settings, **Recordings and contexts folder** controls where new recordings are saved. Earlier recordings remain in their original folders and stay available in the recording list. **Show icon in menu bar** controls the menu containing start/stop, recordings, the recording folder, and settings.

## Language and settings

The interface supports English, Polish, Spanish, and German. **Follow System** matches preferred languages and falls back to English. Interface language and spoken language are independent.

### Configure speech recognition

1. Open **Settings → Speech Recognition**.
2. Set **Spoken language** to the language you will speak: English, Polish, Spanish or German.
3. Choose **Recognition engine** and follow its readiness message:

| Engine | Setup | When transcription appears |
| --- | --- | --- |
| **Apple · On this Mac** | Requires speech permission and an available Apple offline model for the selected language. | During recording, with a local recovery attempt after stopping when needed. |
| **Whisper Small · Local** | Import the supported model or explicitly download about **488 MB**. | After stopping. |
| **Whisper Large v3 Turbo · Local** | Import the supported model or explicitly download about **1.63 GB**. | After stopping. |

Whisper is a speech-recognition model. It transcribes your audio on your Mac; the app assembles the context from that transcript and screen evidence. Audio is not sent to an online transcription service.

For an unavailable Apple language, use **Open Dictation Settings**, add the language in **System Settings → Keyboard → Dictation**, allow any offered download, then return and choose **Check Again**. Availability depends on Apple's offline support on your Mac; selecting a language in macOS does not guarantee this app can use it offline. Choose local Whisper if Apple remains unavailable.

For Whisper, **Download Model…** asks for confirmation before downloading public weights from Hugging Face. The app shows progress, supports cancellation and retry, and verifies the model's size and SHA-256 checksum. A valid model already installed for this app is reused.

If you already have weights, choose the matching engine and **Use Existing Model…**. Select the supported `ggml-small.bin` or `ggml-large-v3-turbo.bin` file, or a folder containing that file or `ggml-model.bin`. The app verifies the selected weights and imports a **local copy** into its sandbox; this avoids another download but uses additional disk space. Arbitrary quantized or modified `.bin` variants are not accepted by the pinned checksum validation. OpenAI `.pt` weights need offline conversion with `script/convert_existing_whisper.sh`; MLX weights cannot be imported directly. Choose the existing model yourself; the app does not scan your disk for weights.

The recording bar also has a spoken-language menu. Changing it during a recording reprocesses the whole recording using the newly selected language after Stop; it does not create separate language segments. The language is saved with the recording.

### Language of copied context

Speech remains in the selected spoken language, without translation into English. Structural headings remain English, and screen quotes, filenames and identifiers stay in their original form. The context asks the receiving agent to generate responses in the recording's language unless the user explicitly requests another language. The receiving agent decides how to follow this instruction. Changing app settings does not rewrite previously saved packages.

The audio meter confirms input level, not successful recognition. A `complete` transcript can still contain recognition errors. Short phrases can be misrecognized; inspect the transcript and referenced frames before making ambiguous changes.

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
- Screen Recording permission; Microphone access for spoken feedback. See [permissions](#permissions-before-your-first-recording) for Apple speech recognition, pointer monitoring and folder access.
- Swift 6.0+ for command-line builds, or Xcode for the Xcode project.

The app can save video and visual context when speech recognition is unavailable. Pointer-event coverage may be limited without Input Monitoring. `manifest.json` records transcript status, language, engine and any captured recognition error; a successful recognition status is not an accuracy score.

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

The script defaults to **release**. Pass `debug` explicitly for development. Both the command-line packager and the Xcode app target use `script/package_resources.sh` to bundle and sign Whisper, generate the app icon and export translations. Packaging requires Python 3, CMake and a C++ compiler.

You can also open `BehavioContext.xcodeproj` in Xcode and select the `BehavioContext` scheme. The shared packaging step builds Whisper if needed; its first build downloads the pinned runtime source. Model weights are downloaded only through the app after user confirmation.

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
- A short-lived global pointer monitor and 250 ms position sampler record normalized positions only during recording, including an initially stationary cursor. Repeated stationary samples preserve the beginning of a dwell.
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
