# UI Screen Context Privacy Policy

by Behavio

Effective date: 11 September 2026.

UI Screen Context is an open-source macOS application published by Behavio. Privacy questions and problems can be reported through the public [GitHub repository](https://github.com/behavio1/behavio-context/issues).

## Data processed on your Mac

UI Screen Context follows the active window as you switch apps and windows, recording one window at a time. It can process microphone audio for live speech transcription and mouse activity for visual references. It does not record keyboard input.

Apple transcription explicitly requires on-device speech recognition. Local Whisper is an alternative that transcribes after recording. The app does not fall back to cloud speech recognition. Recordings, screenshots, transcripts, pointer events, history, and preferences stay on your Mac unless you deliberately share them.

## Agent context

The generated `context/` folder contains text, JSON, and selected images. It does not contain audio or video. A source MP4 remains beside that folder for local recovery and frame extraction, but its path is not included in the agent package.

Copying context puts only the local `context/` path on the macOS clipboard. UI Screen Context does not attach it, upload it, or send it to another app automatically.

## Permissions

- Screen Recording: capture the active window.
- Microphone: create local speech input.
- Speech Recognition: Apple speech recognition only; local Whisper does not require this permission.
- Input Monitoring: observe mouse movement, clicks, and scrolling while recording. The app does not observe keystrokes.

You can revoke permissions in System Settings → Privacy & Security.

## Retention and deletion

Recordings and their context folders remain in local Application Support until you delete them from the application. Deletion does not remove copies you exported, pasted, shared, or backed up elsewhere.

## Network and analytics

The application does not upload user content. An explicitly requested model download makes an HTTPS request to Hugging Face and its file-delivery services; those services receive normal connection metadata such as the IP address. Only public model weights are downloaded. Audio and transcripts are never sent. An existing compatible model can instead be imported locally.

Build tools access GitHub for open-source dependencies and the pinned native Whisper runtime. The application has a network-client entitlement for model downloads; this is not used for remote recognition.
