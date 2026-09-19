# Sources checked 2026-09-19

Primary references:
- [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/): clear names at call sites and explicit effects.
- [Swift concurrency migration guide](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/): actor isolation and data-race safety.
- [Apple model data in SwiftUI](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app): Observation and ownership.
- [Migrating to Observation](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro): @Observable and @Bindable. Retrieved via Context7.
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/): macOS controls, settings, accessibility and platform conventions.
- [Apple App Sandbox](https://developer.apple.com/documentation/security/app-sandbox): entitlements and protected resources.
- [Apple Speech](https://developer.apple.com/documentation/speech): verify API availability against deployment target.

Context7 library verified: `/websites/developer_apple_swiftui`. Resolve Speech separately before querying; do not invent an ID. Context7 is a retrieval source, not a replacement for SDK availability checks.

Community skill reviewed as a candidate: [SwiftUI Pro by Paul Hudson](https://github.com/twostraws/SwiftUI-Agent-Skill), MIT. It covers UI, accessibility and performance; it is not an Apple-authored skill. No third-party skill installer or copied instruction bundle was run. This compact project skill avoids importing platform/version assumptions from a general iOS-oriented skill.
