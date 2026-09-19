# Agent response language

The context writer now emits an explicit agent response-language instruction from the recording manifest locale. It asks the receiving agent to generate responses and descriptions directly in that language, unless the user explicitly requests another language. Structural labels remain English; speech, OCR, paths and identifiers are unchanged. There is no LLM-generated summary inside the application and no translation pass.

The instruction is written when a new context package is generated. Existing context files are not rewritten. The app interface locale is not consulted. Updated the context-reader skill and README accordingly.

Validation: deterministic core/package checks passed, including Polish speech preservation and Polish/German recording-language instructions. Native/privacy checks and git diff whitespace checks passed. App build and signed bundle verification passed with the installed macOS 26.5 SDK. XCTest remains unavailable without full Xcode. Agent compliance with the instruction depends on the receiving agent; this does not force another application's model settings.
