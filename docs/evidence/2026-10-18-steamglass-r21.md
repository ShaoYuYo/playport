# SteamGlass r21 candidate

IPA SHA256: `7edae432a9517e4506f9b05b72d55cb7326cfa5a6e6b097dbbee0b467697f789`

This candidate addresses the follow-up about missing cloud progress, settings
FPS and Files access. The [native reader investigation](2026-10-18-senren-save-reader.md)
verifies that the nine manual records parse, have matching game IDs and become
valid bookmarks at indices 120--128: manual page 10. The sync UI now reports the
actual page and separate quick-save tab. This is stronger evidence than matching
download hashes, but does not establish successful phone loading. The previously
fixed full-snapshot direction, retry persistence and backup recovery are retained.

The startup engine ceiling now follows the panel for capped sessions, preventing
a 30 FPS startup from defeating a later 60 FPS presentation selection. The live
limiter, unlimited setting and explicit arguments are preserved. No repeat
presentation, fake FPS or forced rewriting of game settings is used. The static
settings scene's phone performance remains unverified without a newer report.

[Files access](2026-10-18-files-access.md) enables the two required declarations
for the existing Documents tree, documents the game path and makes the package
verifier require both flags. Existing game files and saves are not relocated.

Validation: 51 HostIOKit, 46 selected Cloud/Steam API and 24 selected PlayportKit
tests pass (121 total). Release compilation and 88 IPA checks pass. The final
package is checked independently for revision and timing markers, Files booleans,
production-source copy equality and unchanged native/runtime hashes. The
1615-file native checkpoint is unchanged; audio and Metal binaries are preserved.
No phone connection, public IPA upload, download link or usage reset occurs.
UI/Files appearance, actual phone save loading and phone settings FPS still need
the owner's sideload test.
