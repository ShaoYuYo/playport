# Native Senren save-reader verification

The owner's latest feedback still reports missing progress. No newer report
than the r19 report was available locally for this turn. Transfer hashes alone
cannot establish that the game parsed or displayed a save.

The installed Windows game and Steam userdata were read only. Recognized save
files were copied into an isolated fixture. The existing private-desktop harness
uses a unique desktop, never switches to it, hides startup windows and terminates
only its owned process. `GseSavePath` and `-datapath` point to fixture directories.
No phone connection or game/save changes outside the fixture occurred.

First, the game's own Steam plugin enumerated 25 files and its engine evaluated
the compressed system dictionaries and trailing slot records, including nonzero
play times up to about 18 hours. A full bootstrap reaches `AfterInit.tjs`; a
fixture-only wrapper stops there before the private desktop's unsupported D3D
presentation. No wrapper or game script is included in the product or repository.
An initial full-render attempt hit that desktop's D3D limitation and is not a
successful gameplay/FPS benchmark.

The actual game reported a 12-slot page, quick slot zero mapping to
`data_quick_01.bmp`, manual slot 12 to `data_0001_01.bmp`, and manual slot 120
to `data_0010_01.bmp`. For manual slots 120--128, its `readBookMarkFromFile`
returned parsed records, each record's game ID matched `kag.saveDataID`, and
`updateBookMarkInfo` made `isExistentBookMark` true. All nine manual files map
to page 10; the twelve quick saves use the separate quick-save tab. This resolves
the earlier uncertainty about filename groups without guessing from the names.
The cloud UI now reports those page numbers and distinguishes loading a slot
from the most recent interruption used by Continue. No save file is rewritten to
change the player's selected page or reconstruct history.

The native engine also reported `waitVSync=0` and `-contfreq=60` in this fixture.
KiriKiri's documented continuous handler is a ceiling, not a guarantee that an
unchanged scene submits frames; see the [engine documentation](https://krkrz.github.io/docs/kirikiriz/j/contents/CommandLine.html).
The product's r20 startup cap had another independent problem: starting at 30
froze the engine ceiling at 30 even after the immediate presentation picker was
raised. The default engine ceiling now follows the panel, while FramePacer owns
the live presentation cap. Unlimited and explicit player arguments are preserved.
A regression covers a 30 FPS launch on 60/120 Hz panels.

This verifies Windows parsing, not successful phone loading or a phone settings
FPS improvement. The latest phone-side call paths and timing still need the
owner's report from the updated candidate. Runtime/audio binaries remain unchanged.
