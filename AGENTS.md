# Contributor guidance

- Keep changes narrowly tied to Behavio Context's active-window, text-first workflow.
- Preserve `⌃⌘R` as the default start/stop shortcut and `Esc` as a recording-only stop action.
- Do not add full-display fallback, cloud transcription, analytics, or audio/video to `context/`.
- Prefer native SwiftUI controls; use AppKit only for behavior SwiftUI does not expose, such as the nonactivating floating panel.
- Preserve accessibility, localization, and privacy behavior.
- Run `./script/test_core.sh`, `./script/check_native_only.sh`, and `swift build` before submitting changes. Run XCTest suites with full Xcode when available.

## Reading recordings

When the user supplies Behavio Context output (a context path, pasted `# Behavio Context` timeline, or context attachments), use [.agents/skills/read-behavio-context/SKILL.md](.agents/skills/read-behavio-context/SKILL.md). It defines the clipboard modes and how to distinguish spoken intent from OCR evidence.
