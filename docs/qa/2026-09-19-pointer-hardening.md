# Pointer evidence hardening

The existing context compiler preserves unlabeled pointer evidence instead of requiring OCR success. Dwell candidates no longer receive a recognition-failure penalty or automatic exclusion from recommended images. The existing package image limits still apply. Markdown includes unconfirmed pointer positions, timestamps and referenced images. Unlabeled pointer images retain the full canvas, so normalized coordinates remain usable; the compiler does not invent a label or claim a speech-target association.

Copy Context Text appends the current context directory at copy time, including for old recordings. It explicitly explains that images are not attached and asks agents without local file access to request the images. This helps local agents; it does not upload files or grant access to cloud agents. Historical context files remain unchanged.

Validation: deterministic core/package regression tests PASS, including unlabeled dwell retention, recommended image selection, full-canvas aspect ratio, coordinates and copy-time relocation. Native/privacy checks, app build and signed bundle verification PASS. XCTest still requires unavailable full Xcode.

Reprocessed a separate copy of the reported 2026-09-19 19:29:09 recording under .build/pointer-hardening-replay. Both 00:00.487 and 00:02.260 pointers now occur in the agent timeline and recommended image list despite nil recognized text. Original recording untouched. Transcription remains the original recognizer output; this change does not correct speech recognition. Existing image sampling and limits mean this is not an exhaustive pointer-event export.

No Accessibility integration, new settings, or new user-visible feature was added. Updated the context-reader skill.

## Follow-up: stationary pointer and movement history

The 19:47:03 recording retained only a move at 2850 ms near the browser toolbar, while its first recommended frame visibly shows the pointer in the page. The recorder only listened for mouse events, so an initially stationary pointer was not sampled. Consecutive moves less than 80 ms apart replaced the last event repeatedly, allowing a continuous movement to erase earlier positions.

Added 250 ms position sampling (also at startup), bounded to the actual active captured window. Movement throttling now preserves earlier samples; stationary repeats preserve the beginning of a dwell. Window changes and clicks remain distinct. Regression checks cover continuous movement, stationary repeats, same-position window transitions and clicks. A fresh live recording remains required to verify the user's exact interaction.

User confirmed the spoken phrase was “weź to usuń”. Saved Turbo output was incorrect; a local Small comparison on the same audio also failed. No transcript substitution or claim that speech recognition was fixed. The latest changes address pointer capture only.
