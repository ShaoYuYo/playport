# Signed game data reads after launch preparation

IPA SHA256: `59f50cfde23f3070a6efc49fa023e6cc922d828d4bfce71a3057ff30ad74757c`

The owner's r28 report for Sabbat of the Witch (Steam app 2458530) ends before
the first frame, with `Malformed exe/dll detected: sabbatofthewitch.exe`, then
exit zero after about 20 seconds. The JIT pool reports no exhaustion. The
installed executable has been transformed by launch preparation (4,461,056
bytes), while the retained publisher executable is 4,631,256 bytes. A detached
executable signature is present. This report's failure is an integrity-check
failure, rather than evidence that physical memory ran out.

The engine's [signature checker](https://github.com/jeeb/kirikiri2/blob/master/kirikiri2/src/plugins/win32/sigcheck/main.cpp)
hashes file streams; its [Win32 storage implementation](https://github.com/krkrz/krkrz/blob/master/base/win32/StorageImpl.cpp)
opens local files through Win32 file APIs. Transforming the executable on disk
can therefore break a publisher's signature even when the image can execute.

## Bounded compatibility contract

The launch builds an exact Windows-path allowlist for signed executables and
Steam API DLLs that have kept `.orig` copies. The selected executable must be
inside the game's resolved install root and its Windows path must match the
same relative components. Regular files only, no links, nonempty signatures
and originals, at most 32 entries, the PE reader's 8,191-unit bound, and a
UTF-8 `KEY=VALUE` length below the title transport's 4,096-byte limit. There
is priority for the selected executable before auxiliary images. There
is no per-app-ID exception and no change to game scripts or `.sig` files.

Wine PE patch 0037 makes only matching read-only `CreateFileW` data opens use
the kept publisher bytes. Creates, writes, delete/execute access, reparse-point
opens and unrelated paths retain their original behavior. Absent originals
receive no substitution. Last-error is preserved during the selection.
Wine's [image loader](https://github.com/wine-mirror/wine/blob/wine-11.19/dlls/ntdll/loader.c#L2478)
uses NT file/section calls, outside this Win32 data-open hook. NT image loading
remains unchanged and still uses the prepared image. The
game's actual signature verification runs against actual original bytes;
there is no forced verification result. The environment is cleared before
preparation and is populated only for this launch's emulated API mode.

Existing r28 phone installations already keep the originals, so a fresh game
download is not normally needed. Other engines using this same signed-file
pattern can benefit, but this does not establish compatibility for every GAL.

## Validation

- 18 SteamStub tests: zero failures, one pre-existing optional real-sample
  test skipped. Three current signed-path tests cover signed/unsigned files,
  untouched files, nested and non-ASCII paths, outside-root/name mismatch,
  symlink refusal and many long filenames fitting the actual title-transport
  byte limit. The complete production filter, installer enumeration function
  and unchanged XCTest fixtures run in a small host package through
  `build/test-signed-originals.py`; file contents remain unchanged.
- The complete production C helper was cross-compiled with warnings as errors
  and run against real Windows APIs without visible UI: 14 cases pass, including
  actual original-file contents and error-state preservation.
- A separate private test invoked production Swift transformation on the owner's
  executable and produced 4,461,056 bytes, matching the phone inventory. No game
  executable or asset is committed or published.
- A private Windows desktop comparison used independent copied game files and
  the production helper in a Win32 hook harness. With the mapping absent, it
  reproduced the exact malformed-executable dialog. With the mapping enabled,
  no such dialog appeared, the game window responded at 15 seconds, and the
  engine log recorded completion of its startup script. This tests the
  identified failure on Windows, not ARM translation or presentation on iOS.
- Test saves and settings went into a private folder with the API emulator's
  networking disabled. The live Steam install's 90 file metadata records were
  unchanged; live cloud saves and the phone were not accessed.

The three real kernelbase DLLs were rebuilt from the pinned, series-checked
Wine source. Their records and the 1,615-file checkpoint were updated, with
every other checkpoint output retaining its bytes. The source guard compares
actual native-input bytes to the r28 baseline tree because the cached runner's
older index cannot reliably classify files added by prior releases.

Release compilation and 88 IPA checks pass. All
216 production app source files match the
reviewed source bytes. The archive CRC, three new kernelbase digests, retained
FEX/WoW64/D3D12 digests, artifact records and Files App flags were independently
verified. No component pin, audio, rendering or cloud-transfer change is made.

This unsigned IPA has not been installed or played on an iPhone. The owner's
in-place sideload and next launch must establish device success, later scenes,
performance and any independent engine/plugin failure.
