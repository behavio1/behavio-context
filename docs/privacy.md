# Behavio Context Privacy Policy

Effective date: 11 September 2026.

Behavio Context is an open-source macOS application published by Behavio. Privacy questions and problems can be reported through the public [GitHub repository](https://github.com/behavio1/behavio-context/issues).

## Data processed on your Mac

Behavio Context captures only the window active when you start recording. It can process microphone audio for live speech transcription and mouse activity for visual references. It does not record keyboard input.

Transcription explicitly requires on-device speech recognition. The app does not fall back to cloud speech recognition. Recordings, screenshots, transcripts, pointer events, history, and preferences stay on your Mac unless you deliberately share them.

## Agent context

The generated `context/` folder contains text, JSON, and selected images. It does not contain audio or video. A source MP4 remains beside that folder for local recovery and frame extraction, but its path is not included in the agent package.

Copying context puts only the local `context/` path on the macOS clipboard. Behavio Context does not attach it, upload it, or send it to another app automatically.

## Permissions

- Screen Recording: capture the active window.
- Microphone: create local speech input.
- Speech Recognition: transcribe speech locally.
- Input Monitoring: observe mouse movement, clicks, and scrolling while recording. The app does not observe keystrokes.

You can revoke permissions in System Settings → Privacy & Security.

## Retention and deletion

Recordings and their context folders remain in local Application Support until you delete them from the application. Deletion does not remove copies you exported, pasted, shared, or backed up elsewhere.

## Network and analytics

The application contains no analytics client and does not upload user content. Build tools can access GitHub to download the declared open-source Logboard dependency.
