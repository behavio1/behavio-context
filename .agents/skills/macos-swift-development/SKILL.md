---
name: macos-swift-development
description: Implement or review this native macOS app in Swift and SwiftUI, including observable state, concurrency, settings, accessibility, localization, sandboxed files, and release verification.
---

# Native macOS development

Use for changes to UI Screen Context. Read the repository AGENTS.md first. This is a project-authored skill, not an official Apple skill.

1. Check Package.swift, the active Swift compiler/SDK, and deployment target. This project uses Swift 6 language mode and macOS 15 minimum. Gate newer APIs; do not raise the target merely to simplify a feature.
2. Keep UI state on MainActor and use the existing Observation store. Use @Bindable for editing an injected @Observable model. Avoid duplicate state between settings, menu bar, and recording capsule.
3. Keep media decoding, model loading, copying, hashing and inference off MainActor. An async function is not proof that synchronous work runs off the UI actor. Give long operations progress, cancellation and a bounded failure path.
4. Preserve actor isolation. Use structured tasks when possible. Review every unchecked Sendable conformance for actual locking/ownership; do not silence compiler warnings with annotations.
5. Prefer native Picker, Menu, Button, Toggle and DisclosureGroup semantics. Entire accordion headers must be clickable. Icon-only actions need accessibility labels; tooltips alone are insufficient. Test keyboard navigation, VoiceOver labels, contrast, long translated strings and small screens.
6. Keep the spoken language separate from the app locale. Persist preferences compatibly with older snapshots. Read the companion local-speech-recognition skill for speech/model changes.
7. Preserve App Sandbox and least-privilege entitlements. Balance security-scoped resource access; use bookmarks for persistent external folders. Test the signed .app, not only an unsandboxed command-line build.
8. Put UI strings in Localizable.xcstrings with en/pl/es/de translations. Do not bypass localization checks with verbatim text except actual user/system data.
9. Run the checks required by AGENTS.md. Report missing Xcode/UI/runtime evidence explicitly. A successful build is not proof of usable recording or transcription.

Read [references/sources.md](references/sources.md) for authoritative sources and Context7 lookup identifiers. Consult current docs only for the APIs touched by the task; avoid unrelated modernization.
