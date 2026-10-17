# Authoritative save root and verified replacement

The owner confirms r18 still presents about 30 FPS on the game's settings
page after choosing the app's unlimited FPS setting. The supplied second
screenshot shows 29.75 FPS, 33.62 ms frame interval and 4.48 ms GPU time.
Steam progress still appears fresh. No r18 report ZIP has been supplied yet,
so the actual phone file hashes/open results and engine options are unknown.
No phone was connected or controlled, no game window was shown and no original
Windows game/save files were changed.

## Reproduced storage-path precedence defect

The pinned emulator's
[settings parser](https://raw.githubusercontent.com/Detanup01/gbe_fork/7103add7ca6ef3ef8353279219880068f2494fc8/dll/settings_parser.cpp)
loads game INIs first, then merges the selected save root's `settings/` INIs
with overwrite enabled. A previously persisted `local_save_path` can therefore
replace the path Playport just wrote beside the game's DLL. `parse_local_save`
gives the existing `GseSavePath` variable precedence over both INI sources.

The exact bundled i386 DLL was exercised in a hidden Windows process using
only synthetic files in an isolated save root, with networking disabled:

- With a conflicting persisted root, the probe enumerates zero files, reads
  zero bytes and exits with the expected mismatch code.
- With the authoritative `GseSavePath` launch variable, the same DLL enumerates
  all three files and reads the exact synthetic marker. The game's observed
  Client017/RemoteStorage013 interface also passes existence, read, nullable
  enumeration-size, size and returned-name lifetime checks.
- The scratch INI and process-local environment were restored after the test.

This establishes a real way downloaded files and the game's reader can diverge.
It does not establish that this is the owner's phone failure without its report.

Senren's fixed root now belongs to `SteamAPISwap.Settings` initialization,
including the app-ID-only settings fallback used after a profile timeout.
Preparation returns its authoritative environment only for emulated Steam API
mode. The launch merges it after backend options and passes it through both
the host and the explicit guest environment block, after session-root startup.
It is an internal use of the emulator's existing option, not a new app entry
point or user switch. Other titles retain their existing root behavior.
`steam-save-root-v2` logs activation without paths, account IDs or credentials.

## Replacement and agreement

Verified downloads always go to the canonical cloud path, even when the
locally changed copy used during conflict detection came from the native
backend. The selected source URL is then updated before local placement.
Existing backup and no-upload behavior for forced restoration are preserved.

Before recording agreement, the service reads back transferred files and both
settled title-specific backend placements, checking the expected content hash.
A mismatch becomes a failed sync, prevents the new baseline from accepting
that file and makes the existing launch gate refuse to start with a false
success. No original, losing version or Steam snapshot is deleted.

Regression cases include replacing pre-existing and different system/slot/check
files in both backends, retaining both old copies in backups, and an external
writer changing the first downloaded file while later downloads are underway.
The latter must fail agreement; after interference stops, a retry repairs both
backends. Existing ordinary upload, conflict, case handling and previous-cloud
backup cases remain covered.

## FPS and complete diagnostics

An unlimited app limiter still producing about 30 FPS makes that limiter an
insufficient explanation. GPU and presentation averages alone do not identify
the remaining bottleneck. The known
[KiriKiriZ option handling](https://github.com/krkrz/krkrz/blob/fd5c4baa6a2ef5978db1bd043634351f48667daf/base/win32/SysInitImpl.cpp)
and [continuous handler](https://github.com/krkrz/krkrz/blob/fd5c4baa6a2ef5978db1bd043634351f48667daf/base/win32/EventImpl.cpp)
make stored engine rate/timer settings useful evidence; this is not proof the
title is capped internally. No guessed renderer flags, forced engine rate or
new translation optimization is shipped in this candidate.

The save report now includes only allowlisted scalar engine options from the
fixed `.cf`/`.cfu` files: contfreq, vsync, waitvsync, timerprec, drawthread,
memusage and gclim. UTF-16 and escaped ASCII values are understood; paths,
arbitrary strings and other configuration lines are excluded. Stored values
are explicitly labelled as potentially overridden by runtime scripts.

The retained desktop save set has 22 slot BMPs of roughly 420--430 kB each,
plus small system/check files. The previous 8 MiB total audit allowance could
omit later slots or the second backend. Both report audits now allow 32 MiB
of sequential reads, still capped at 2 MiB per file and 64 names. This changes
report work, not the game's RAM quota or retained asset cache. A regression
checks both backends of a slot set exceeding the old limit. No save payloads
are exported.

## Candidate validation

IPA SHA256: `f36d084dca5388138f111924a2cb263ee000e20e2da169fba549e533453f80a2`

- 50 HostIOKit, 39 Cloud/Steam API and 16 selected PlayportKit tests pass.
- Release compilation and 87 IPA checks pass. Changed production sources match
  the build checkout and the packaged root-authority marker is present.
- The 1615-file native checkpoint is unchanged from r18, including its confirmed
  audio fix and the two compact-heap FEX images. No native rebuild is involved.
- Name, secret, patch-series and whitespace checks pass.

Phone cloud-progress restoration, actual root selection and frame pacing must
still be validated by the owner. A successful host reproduction or matching
download hash is not proof that the game semantically loaded the real save.
