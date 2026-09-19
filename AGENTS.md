# Contributor guidance

- Keep changes narrowly tied to Behavio Context's active-window, text-first workflow.
- Preserve `⌃⌘R` as the default start/stop shortcut and `Esc` as a recording-only stop action.
- Do not add full-display fallback, cloud transcription, analytics, or audio/video to `context/`.
- Prefer native SwiftUI controls; use AppKit only for behavior SwiftUI does not expose, such as the nonactivating floating panel.
- Preserve accessibility, localization, and privacy behavior.
- Run `./script/test_core.sh`, `./script/check_native_only.sh`, and `swift build` before submitting changes. Run XCTest suites with full Xcode when available.

## Reading recordings

When the user supplies Behavio Context output (a context path, pasted `# Behavio Context` timeline, or context attachments), use [.agents/skills/read-behavio-context/SKILL.md](.agents/skills/read-behavio-context/SKILL.md). It defines the clipboard modes and how to distinguish spoken intent from OCR evidence.

## YouTube materials

For promotional video preparation, follow [docs/youtube-publication.md](docs/youtube-publication.md) and its global skill reference. Keep uploads private until the user approves publication in YouTube.

## Native macOS and speech development

For Swift/SwiftUI implementation and review, use [.agents/skills/macos-swift-development/SKILL.md](.agents/skills/macos-swift-development/SKILL.md). For speech languages, offline engines and model downloads, also use [.agents/skills/local-speech-recognition/SKILL.md](.agents/skills/local-speech-recognition/SKILL.md). These are project-authored guides grounded in Apple and Swift documentation, not official Apple skills.
