# Background recording completion

Requested behavior: remain in the user's current application after stopping, copy agent context automatically once it is ready, and show a brief notice without opening a player.

AppDelegate now copies the generated document through the same directory-aware clipboard formatter used for manual copying. A nonactivating existing recording panel displays completion feedback and dismisses automatically. The result window opens only through the explicit Recordings action. Player loading leaves playback paused. A missing context does not overwrite the clipboard or announce successful copying. Context failures use existing warning feedback without automatically opening Settings. No system notification permission or new preference is introduced.

Build and signed bundle verification completed. Core/native checks are recorded in .build/clipboard-ux-tests.log. Live completion/clipboard/focus behavior must be verified separately; build success alone does not prove end-to-end behavior.
