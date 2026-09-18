# UI Screen Context Support

by Behavio

Report bugs and request features in [GitHub Issues](https://github.com/behavio1/behavio-context/issues).

## Recording does not start

Bring a normal application window to the front and press **⌃⌘R**. UI Screen Context deliberately refuses to fall back to the full display. Confirm Screen Recording access in System Settings → Privacy & Security.

If the switch is on but the app reports that access was declined, check how the
app was signed. An ad-hoc development rebuild has a new privacy identity even
when its bundle identifier and filename are unchanged. Install the final build,
remove the stale UI Screen Context entry once, add the installed app again, and do
not replace that binary afterward. A stable development or distribution signing
identity preserves the permission across rebuilt versions.

The app only checks Screen Recording access on launch. It asks macOS to grant it
only after **Allow Screen Recording…** is selected, preventing repeated system
prompts during ordinary startup. Error capsules can be closed with their ×
button and also dismiss automatically.

## No live transcription

Enable Microphone and Speech Recognition access. UI Screen Context requires the Polish on-device recognizer and never falls back to a cloud service. Visual context still works when transcription is unavailable, and the manifest reports that state.

The Recording Capsule shows the microphone currently in use. Open its microphone menu to change the input while recording; the choice is also used for the next recording. If the level stays flat, choose a physical microphone rather than a silent HDMI, DisplayLink, or virtual input.

## Cursor moments are missing

Enable Input Monitoring for UI Screen Context. Only mouse activity within the selected window is retained, and monitoring stops with the recording.

## How to stop

Press **Esc**, press **⌃⌘R** again, or click **Stop** immediately beside the capsule timer.

## Where is the result?

The result panel shows the `context/` path. `context.md` is the agent's first-pass entry point. The source MP4 stays one directory above it and is not part of the recommended agent input.
