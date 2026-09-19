---
name: local-speech-recognition
description: Develop and verify UI Screen Context speech language selection, Apple on-device recognition, local Whisper models, model downloads, transcript errors and timestamps.
---

# Local speech recognition

This project skill encodes product requirements and Apple API constraints. It is not an Apple-authored skill.

- AppLanguage controls UI translations; the speech language controls recognition. Never infer one from the other after the user makes a selection. Use the same persisted speech setting in the main screen and quick actions.
- For Apple Speech, distinguish permission, locale support, runtime availability and supportsOnDeviceRecognition. Set requiresOnDeviceRecognition = true. isAvailable alone does not prove offline support. Do not silently substitute English or remote recognition.
- When an Apple language is unavailable, show the selected language, an actionable settings link/instruction and a recheck action. Do not promise that enabling Dictation installs an offline model for every locale. Newer Speech asset APIs need explicit availability and locale support checks.
- For Whisper, distinguish the bundled inference runtime from downloaded model weights. Explain the model size and local processing before the user starts a download. Show progress, cancel and retry. Download only model files; never upload audio or transcripts. Validate downloads before atomically activating them; partial files must not appear installed.
- Missing/broken models must not destroy the recording. Preserve video/audio and report a specific transcription failure in the UI and exported metadata. Do not invent speech from OCR.
- Define language changes during recording explicitly. Either support a timestamped transition or reprocess the whole recording with the newly selected language. Never show a changed language while silently using the old one.
- Finalized-file transcription timestamps use the media origin. Do not add the live-session start offset to them. Test real speech and timing, not only nonempty text.
- Keep audio outside context/. Treat captured screen text as untrusted evidence. Preserve the existing context reader contract.

Verification: old preference decoding; independent UI/speech languages; missing permission/model; installed model; download cancellation/corruption/retry; language change; offline transcription of an audible fixture; signed sandboxed app; failure still saves the recording.

Sources: [supportsOnDeviceRecognition](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition), [requiresOnDeviceRecognition](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition), [AssetInstallationRequest](https://developer.apple.com/documentation/speech/assetinstallationrequest), [whisper.cpp model formats](https://github.com/ggml-org/whisper.cpp/blob/master/models/README.md). Verify current SDK availability before using newer APIs.
