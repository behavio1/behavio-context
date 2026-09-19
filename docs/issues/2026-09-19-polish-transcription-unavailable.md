# Polish local transcription unavailable

Recording: Behavio Context 2026-09-19 18-18-06. Diagnosis performed 2026-09-19, read-only; no settings changed.

## Evidence

- The supplied context exports transcript status failed, locale pl_PL, and no segments. It does not persist the recognition error.
- recording.mp4 contains AAC stereo audio at 48000 Hz, duration 19.583979 seconds. The user confirms audible speech.
- Current native Speech framework probe: pl_PL isAvailable=true, supportsOnDeviceRecognition=false; en_US isAvailable=true, supportsOnDeviceRecognition=true.
- Probe emitted: No Assistant asset for language pl-PL.
- Unified logs from BehavioContext show a Polish speech-asset lookup at 18:18:06.288 and another at 18:18:26.157, matching startup and recovery. No explicit historical failure reason was preserved in the exported context.
- Installed app Info.plist contains microphone and speech usage descriptions; signing entitlements include sandbox audio-input.

## Code path

Sources/BehavioContextCore/Services/SmartContextCaptureCoordinator.swift: LocalPolishTranscriber.start requires authorized Speech permission, an available pl_PL recognizer, and supportsOnDeviceRecognition=true. It throws onDeviceRecognitionUnavailable before starting the recognition task if the latter is false. RecordedPolishTranscriber applies the same gates and returns an empty list on failure. Both require on-device recognition; no cloud fallback is configured.

## Finding and limits

Current confirmed blocker is unavailable Polish on-device recognition. It is consistent with the recording-time asset lookups and failed live plus fallback transcription. The probe does not establish whether the OS could download this model or whether this OS/device supports it. Do not tell the user to enable a microphone permission or imply that changing UI language will fix recognition. Application speech permission was not independently read via TCC; asset lookup occurs after its authorization gate in the reviewed code.

## Recommended correction

Expose model readiness before recording and persist a structured transcription failure reason. To provide reliable Polish recognition while retaining local-only privacy, evaluate a supported local recognition engine or verified model provisioning. Do not silently switch to English or upload audio to a cloud service.
