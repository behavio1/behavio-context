# Behavio Context design guidance

Behavio Context is a compact native macOS utility for explaining one application window to an AI agent. It converts a short interaction into a local, text-first evidence folder instead of asking the agent to process a full video.

## Product rules

- Write the product name as **Behavio Context** in user-facing copy.
- Keep the original default shortcut: **Control–Command–R** starts and stops recording.
- **Escape** is an additional stop command only while recording.
- Freeze the active external window at start. Never fall back to the entire display.
- Keep capture, transcription, frame selection, and packaging local.
- The agent-facing `context/` directory must not contain audio or video.
- Raw `recording.mp4` remains a local recovery source outside `context/`.
- Do not imply that copying a folder uploads it or gives an agent access automatically.

## Interaction model

1. The user focuses the window they want to explain.
2. They press `⌃⌘R`.
3. A floating, nonactivating Recording Capsule appears outside the captured window.
4. The user speaks, points, clicks, and scrolls.
5. They stop with `Esc`, `⌃⌘R`, or the Stop button beside the timer.
6. The app compiles and exposes the resulting `context/` directory.

The capsule must keep the recording state and next action obvious. In the recording state it shows a red status dot, monospaced timer, Stop button, `Esc` hint, microphone level, live transcript, and the selected application/window. During finalization it replaces recording controls with honest progress text.

## Visual character

- Use native SwiftUI/AppKit controls, system typography, SF Symbols, adaptive colors, and vibrancy.
- Keep the utility visually quiet outside the active recording state.
- Use system red for recording and destructive actions; do not rely on color alone.
- Keep Stop adjacent to the timer so the relationship is immediate.
- Use a four-point spacing rhythm and an 18-point continuous corner radius for the floating capsule.
- Avoid dashboards, decorative gradients in application UI, nested cards, pulsing indicators, and promotional copy.
- Respect Reduce Motion, Increase Contrast, light/dark appearance, localization, and VoiceOver.

## Evidence package

`context.md` is the first-read entry point. JSON contains the synchronized machine-readable timeline. `recommended/` is limited to eight initial images; `on-demand/` contains optional additional evidence. Full-window images have a 1280 px maximum long edge, and pointer crops have a 768 px maximum long edge.

Image selection is event-driven: clicks, pointing language, transcript boundaries, significant visual changes, and sparse coverage. Fixed-rate frame dumping is not the product model.

## Privacy boundaries

- Only the frozen target window is captured.
- Speech recognition must require on-device execution and must not fall back to cloud recognition.
- Pointer monitoring exists only during recording and stores events inside the target window.
- No keystroke content is recorded; the temporary Escape registration is only a stop action.
- No analytics or upload service is initialized in the release application.

## Acceptance scenarios

- Start from another application with `⌃⌘R`; the capsule names that application and window.
- Move or resize the target window without switching capture to the display.
- Stop independently with `Esc`, the same shortcut, and the capsule button.
- Verify that the capsule is not present in extracted evidence images.
- Verify limits and file types for short, long, silent, and transcription-unavailable recordings.
- Verify that a failure leaves the local source recording intact and never exposes a partial `context/` directory.

Implementation details and requirement mapping are documented in [docs/smart-agent-context-design.md](docs/smart-agent-context-design.md).
