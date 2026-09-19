# Local speech recognition — verification

Scope: separate spoken language, Apple readiness, local Whisper Small / Large v3 Turbo, model download/import, toolbar language selection, and exported speech metadata.

## Implemented

- Spoken language is independent of interface locale. Main settings and both recording-bar sizes share the setting.
- Apple recognition explicitly requires offline support. Unavailable languages show setup/recheck instructions. A language change during recording reprocesses the saved audio in the selected language.
- Whisper runs in a bundled native, sandbox-inheriting helper. Downloads fetch model weights only. Audio never goes to a remote recognizer.
- Downloads show size, confirmation, progress, cancellation and retry. SHA-256 and size are checked before activation.
- Existing compatible files/folders can be imported. `.pt`/MLX formats do not trigger automatic downloads. A local conversion script is provided for installed OpenAI `.pt` weights.
- Language, engine and transcription failure are persisted in context metadata. Finalized-file timestamps use the media origin and are clamped to the extracted audio duration.

## Computer Use checks

PASS:
- Changing spoken English to Polish leaves the interface unchanged.
- Apple Polish unavailable-state explanation and the link to System Settings → Keyboard → Dictation.
- German interface with Polish speech selected; restore Follow System.
- Import existing converted Turbo from a selected folder; ready-state survives restart; no Turbo download.
- Small download disclosure (488 MB, local processing), cancel, retry and successful completion inside the sandbox.
- Actual UI start/stop and microphone recording followed by successful Small transcription of the spoken test phrase.
- Actual UI start/stop with Turbo: `transcript_status=complete`, `speech_engine=whisperTurbo`, `locale=pl_PL`; recovered the spoken Turbo test phrase.
- Recording-bar language changes PL → EN → PL; compact bar displays PL clearly.
- Main settings fit without an unnecessary scroll bar at the tested size.

The recorded window followed the user's actual foreground app during testing. Do not treat this as an isolated Calculator-only capture test. Private captured screen/transcript content is not copied into this report.

## Issues found and corrected during QA

1. Recursive codesigning replaced the helper's inheritance entitlements with the parent app's permissions; the helper failed only inside the sandbox. Sign the helper explicitly, then the containing app without recursive re-signing. Packaging now asserts the helper entitlements.
2. Local import misleadingly showed “Cancel Download”; import now shows local verification and a neutral cancel action.
3. App reopen always opened Settings during recording; it now keeps the recording controls available.
4. The native helper inherited the host deployment target. Its build now explicitly targets macOS 15 and avoids host-specific CPU instruction selection.

## Automated checks and limits

- `script/test_core.sh` with native build system and SDK 26.5: PASS, including preference compatibility, independent languages, Whisper JSON timing, incomplete-file rejection, recording preservation, window attribution and package regression checks.
- `script/check_native_only.sh`: PASS. Network client access is now permitted for explicit model downloads; server/camera access remains prohibited.
- Swift build with native build system and SDK 26.5: PASS.
- Signed app packaging and signature verification: PASS.
- Real existing Polish recording: both local Whisper models recovered speech. Turbo used already-installed weights converted locally; checksum matched the published native model.
- XCTest: BLOCKED by missing full Xcode (`no such module XCTest`). Default SDK 27 CLT build also lacks SwiftUI macro/asset tooling. No Xcode installation was performed by this task.
- No claim of complete language/accent coverage, network-outage simulation, older-macOS hardware execution or accessibility certification.

## Development guidance

Project skills: `.agents/skills/macos-swift-development` and `.agents/skills/local-speech-recognition`; both passed skill-creator validation. Apple/Swift sources and the Context7 SwiftUI identifier are recorded in the native-development skill's references.
