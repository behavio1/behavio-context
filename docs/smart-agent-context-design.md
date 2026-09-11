# Behavio Context: active-window agent context

Status: implemented in the initial public release.

## Problem Statement

A full monitor recording is an expensive and noisy input for an AI agent, especially on an ultrawide display. It also forces the agent to discover the relationship between speech, cursor actions, and visual changes by decoding a complete video.

Behavio Context captures one active window and compiles a small local folder in which timestamps connect Polish speech, pointer events, and selected images. The agent reads text first and opens visual evidence only when needed.

## Accepted assumptions

- The original default shortcut remains `⌃⌘R`; it toggles recording.
- `Esc` also stops recording and is registered only for the active session.
- The target is the external window active at start and remains fixed for the session.
- Polish transcription is local and has no cloud fallback.
- The user sees a persistent native recording indicator with live transcript and Stop beside the timer.
- The agent receives the `context/` directory, not the source MP4 or an audio track.

## Requirement mapping

| ID | Requirement | Implementation | Acceptance evidence |
| --- | --- | --- | --- |
| R1 | Original shortcut plus Escape stop | `GlobalShortcutController`, `AppDelegate` | Real start with `⌃⌘R`; stop with `Esc`, repeat shortcut, and Stop |
| R2 | Active window only | `ActiveWindowResolver`, `SCContentFilter(desktopIndependentWindow:)` | Manifest identifies the target window; extracted frame contains no display area |
| R3 | Speech and pointing synchronization | `SmartContextCaptureCoordinator`, `PointerTimelineRecorder`, `AgentContextVisionAnalyzer` | Final timeline links transcript, pointer dwell/clicks, and locally recognized text by `time_ms` |
| R4 | Clear recording UI | `RecordingFeedbackPanelController` | Capsule shows state, timer, Stop, Escape, selected microphone picker, level, transcript, and source |
| R5 | Minimal model input | `AgentContextMomentSelector`, `AgentContextPackageWriter` | At most 8 first-pass images; 1280/768 px limits; reduction test passes |
| R6 | No audio/video for the agent | Package validation and native-only contract test | Recursive `context/` scan contains only Markdown, JSON, and JPEG |
| R7 | Local processing | `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` | No network entitlement or cloud fallback; honest failed/partial status |

## Current architecture

### Capture boundary

`ActiveWindowResolver.captureHint` reads the frontmost external process before Behavio Context changes focus. It matches the topmost standard Core Graphics window to an `SCWindow`. Failure is explicit; there is no display fallback.

`ScreenCaptureRecordingPipeline` records that `WindowSource` through ScreenCaptureKit. The source MP4 remains in the recording directory as local recovery material and is never placed inside the agent package.

### Synchronized evidence

`SmartContextCaptureCoordinator` owns the in-memory session timeline. Microphone buffers feed two local consumers: the media recorder and an `SFSpeechAudioBufferRecognitionRequest`. Recognition is configured for `pl_PL`, partial results are published to the capsule, and `requiresOnDeviceRecognition` prevents cloud fallback.

`PointerTimelineRecorder` installs a short-lived global mouse monitor only while recording. It stores normalized move, click, right-click, and scroll events that fall inside the selected window. It does not monitor keyboard content.

A lightweight 16×9 luminance signature detects meaningful visual changes without persisting continuous screenshots during recording.

### Moment selection

After stop, the coordinator first closes live recognition and, when needed, retries against the finalized local recording using the Polish on-device recognizer. The selector ranks candidates from clicks, pointer dwell, pointing-language segments, transcript boundaries, visual changes, and sparse coverage. Apple Vision OCR resolves the text nearest the pointer. Similar OCR targets are collapsed before the recommended set is chosen. Recommended evidence is capped at eight images and optional evidence at 48.

`AgentContextPackageWriter` uses AVFoundation to extract only selected moments. Full-window images are resized to a maximum 1280 px long edge; click-focused crops are capped at 768 px. The writer validates a temporary directory and atomically publishes `context/` only after all contracts pass.

### Recording Capsule

`RecordingFeedbackPanelController` owns a floating, nonactivating `NSPanel` positioned outside the target window. The recording layout keeps Stop directly beside the monospaced timer and shows the Escape hint, the actual microphone name and live device picker, microphone level, live transcript, and source chip. A device change restarts only the microphone capture input and persists the successful choice. Finalization uses the same surface for progress. Window-only capture keeps the capsule out of the evidence.

### Lifecycle

`RecordingSessionStore` remains the single owner of `idle → preparing → recording → finalizing` state. It makes shortcut handling available before waiting on first-run privacy UI, so macOS permission prompts cannot make the stop/start affordance appear dead.

## Folder contract

```text
Behavio Context YYYY-MM-DD HH-MM-SS/
├── recording.mp4
└── context/
    ├── context.md
    ├── manifest.json
    ├── transcript.json
    ├── recommended/
    └── on-demand/
```

`context.md` is the complete cheap first read: it states the microphone, transcript status, and an ordered `SAID` / `POINTED AT` timeline. `manifest.json` contains schema version, source and microphone metadata, duration, transcript segments, pointer events, OCR text and confidence, pointer-linked visual moments, recommended IDs, and actual image limits. Paths are relative and remain inside the package.

No `.mp4`, `.mov`, `.m4a`, `.wav`, or other audio/video file is allowed below `context/`.

## Testing strategy

- `script/test_core.sh` creates a real H.264 fixture and compiles a package end to end.
- The deterministic check validates JSON, relative paths, dimensions, file types, selection caps, and at least 80% reduction against naive 1 fps frames.
- `script/check_native_only.sh` checks privacy and dependency boundaries.
- XCTest covers selectors, persistence, media composition, and repository contracts when full Xcode is available.
- UI acceptance uses a real external window, the global shortcut, the capsule, Escape/Stop, and filesystem readback of the final package.

## Risks and limits

- The Polish on-device speech asset must exist on the Mac. If it is unavailable, recording still produces visual context and the manifest reports the real transcription failure.
- Input Monitoring is optional. Without it, visual and speech context still work, but pointer-linked moments are absent.
- The source MP4 is retained for recovery and consumes local disk space; it is intentionally excluded from the agent input.
- `Esc` is consumed globally while recording, which is made visible in the capsule.

## Alternatives rejected

- Full MP4 as agent input: high and unpredictable decoding cost.
- One screenshot per fixed interval: duplicates stable UI and misses semantic timing.
- Full-display capture with later cropping: poor privacy and excessive pixels on ultrawide displays.
- Cloud speech recognition: unnecessary privacy and cost boundary.
- Separate daemon or Python/Whisper helper: avoidable installation and lifecycle complexity for the first release.
