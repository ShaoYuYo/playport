# SteamGlass r20 release candidate

IPA SHA256: `d898add448ec814e3a228a207ae3602b833187b046e25a2415523ea73572efd0`

This candidate follows the owner's r19 report. The report verifies matching
manual/quick slot bytes in both storage locations, successful system-file
opens, changing system/continue files after launch, unlimited presentation
and variable 20.4--58.1 FPS at 2338x1080. It does not prove that every saved
scene or prior read-history flag was semantically loaded.

## Save correctness

The reproduced game-wide Steam-choice bug and its regression are recorded
in [snapshot choice](2026-10-18-cloud-snapshot-choice.md). Steam's full
observed set is restored without uploading fresh phone system data.
[Backup recovery](2026-10-18-cloud-backup-recovery.md) provides an explicit
route to prior versions if Steam already contains overwritten progress.

Recovery now canonicalizes names to Steam's spelling before persisting the
conflict gate; an uppercase backup cannot bypass that gate on the next sync.
Ambiguous case aliases with different bytes are rejected before replacement.
The recovery reason survives an unresolved sync, uses the backup's timestamp,
and is shown separately from divergence between local storage backends.
The UI explicitly names the recovered phone version and explains which
choice would upload it or replace it with the current cloud snapshot.
Only recognized manual/quick counts are shown; filename groups are not
assumed to correspond directly to the game's displayed save pages.

A second failing regression proves that a failed Steam download could be
retried as a fresh phone upload. The Steam restore direction is now persisted
before remote requests and file changes, retained across failures and cleared
only after complete verification or an explicit phone/backup choice. Failure
to persist intent prevents replacement; failure to persist agreement fails the
sync. Unchanged phone-only files remain local after a Steam snapshot restore.
Recovered version timestamps and reasons survive an unresolved retry.

## Rendering and controls

The [engine cadence record](2026-10-18-engine-cadence-metal.md) contains the
actual hidden Windows engine probe and the bounded performance diagnostics.
DX12 uses the existing verified vkd3d-proton/Vulkan/Metal stack; this release
does not claim a new direct DX12 compiler or universal feature compatibility.
All native runtime outputs, including the confirmed audio fix, are unchanged.

Launcher and in-game drawer rows now use the same native glass controls,
pressed feedback and selected tint. Separate controls share a sampling
container with zero merge spacing so neighboring rows keep distinct outlines.
Settings retain row spacing and controller focus. The option picker uses a
rounded glass panel, a lighter backdrop, adaptive width and multiline labels
and descriptions. Recovery/conflict choices use matching glass surfaces and
clear version wording. Reduced transparency/motion preferences are retained.
The memory reminder rounds its approximate figure to 50 MiB steps instead
of rebuilding the text for tiny one-second fluctuations; allocation safety
policy and the configured headroom remain unchanged.

The problem report now includes the fixed native KiriKiri console log when
present, regular, unlinked and at most 2 MiB. It lives outside the game install
folder and was absent from the previous report collection. The report records
whether that log qualifies; save payloads and account INIs remain excluded.

## Validation and limits

- 51 HostIOKit, 46 Cloud/Steam API and 23 selected PlayportKit tests pass:
  120 total, covering real corruption/restore scenarios rather than UI snapshots.
- Release compilation and 87 IPA checks pass. Packaged runtime hashes,
  DX12 DLL architecture, Metal driver presence, code markers and all changed
  production-source copies are independently checked at delivery.
- The 1615-file native checkpoint remains unchanged. No lossy asset/audio
  conversion, device connection, phone control or public IPA upload occurs.
- Name, secret, patch-series and whitespace checks pass before commit.

The delivery check initially caught an incorrect new A641-only availability
rule before shipment. Microsoft documents A641 as an intermediate COFF
identifier; final ARM64EC DLLs use an AMD64 header with hybrid metadata
([Arm64EC](https://learn.microsoft.com/en-us/windows/arm/arm64ec)). The check
now validates the PE32+ load configuration, bounded section/RVA mapping and
CHPE metadata. A plain x64 DLL without that metadata fails. The host test
also exercises the exact seven packaged hybrid DLLs and i386 D3D9 DLL,
not just synthetic headers. No broken candidate was delivered.

Actual phone UI appearance, title/settings FPS improvement and successful
loading of the owner's old progress still require the owner's sideload test.
The desktop continuous-handler probe is not a phone/gameplay FPS benchmark.
The availability of recoverable old progress depends on preserved backups.
