# All-game file read-ahead and memory capability guide

IPA SHA256: `6b2150c02190267113efe5d9aa41fd8047aa26e7090f0512c38c41921ffc5649`

## Implemented scope

A default-off Graphics switch offers file read-ahead for every game's shared
launch path, with an explanatory confirmation. It replaces the previous
Steam-only, two-title warmup condition and is independent of RAM economy.
The selected executable's resolved parent is the root. Its bytes are read
first, followed by bounded EXE/DLL and resource-container headers (XP3, PAK,
RPA, ARC and VFS). No store session or Steam app ID is required. Existing
shader caches remain unchanged.

Read scheduling stops at 8 MiB or 0.25 seconds, with a maximum of 64 candidate
files and bounded directory listing. A filesystem operation can exceed the
time budget. Unknown or less than 128 MiB of process headroom skips warmup.
The app does not retain decoded assets or write a new cache copy: iOS owns
and may evict its file pages. Save files and symbolic files/plugin directories
are skipped. Startup logs distinguish disabled, insufficient headroom and
actual read count/bytes/time. No startup-speed or FPS improvement is established.

This is explicitly NOT the persistent translated-code cache the owner also
asked about. That full request remains unresolved. Native FEX patch 0022
still disables disk caching for WoW64: generated code contains the per-process
guest-window base. Patch 0021 keys the TEB slot but not that base. Simply
removing the guard would allow stale addresses. The documented warm-start
allocator failure has no new device validation. No ineffective universal FEX
switch is exposed, and no native translation or allocator patch is changed.

## GetMoreRam and signing

The app already requests `com.apple.developer.kernel.increased-memory-limit`
in its entitlements file. The current signature is checked at runtime; asking
for it in an unsigned IPA does not establish that a sideloader grants it.

Setup check now exposes a shared guide showing that signature status and the
installed bundle ID, with actions to copy it or open the official project.
GetMoreRam's [README](https://github.com/hugeBlack/GetMoreRam) requires signing
in with the account used for the target app, enabling its App ID capability,
then reinstalling through the sideloader. Its `AppIDViewModel.swift` calls
`AppleAPI.updateAppID` with `INCREASED_MEMORY_LIMIT`; this is a developer-account
provisioning operation, not an in-process allocator or physical-RAM extension.
The [Apple entitlement reference](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit)
limits the feature to supported devices. No fixed larger budget is promised.

GetMoreRam itself, its Apple login client, anisette service and provisioning
management are NOT embedded. No Apple credential is requested or collected in
Playport, and no account capability or installed app was modified in this work.
The repository tree reviewed did not include a root licence file; third-party
implementation code is not copied. This is a guided external workflow, not a
completed integrated signing subsystem.

## No-JIT and cellular assessment

[UTM's iOS documentation](https://docs.getutm.app/installation/ios/) describes
UTM SE as a slower interpreter-based edition. That execution backend is not
part of Playport. Replacing x86 translation alone also leaves this app's Wine
ARM64EC executable-image pool dependent on JIT preparation. No no-JIT switch
or interpreter backend is added, and compatibility/performance of such a
backend is not established by this release.

The [runtime's JIT guide](https://github.com/willfaust/Madeira/blob/main/docs/JIT.md)
documents that its LocalDevVPN loopback fails while cellular is in use; its
workaround temporarily disables cellular and restores it after pool preparation.
The [helper integration guide](https://github.com/StikDebug/StikJIT/blob/main/INTEGRATION.md)
likewise documents a temporary network switch. Settings explains that the
already prepared pool remains usable while the same app process lives, so
cellular may be restored after the game starts. A new app process still needs
activation. This device-specific workaround has not been tested here.

[Apple's Personal Hotspot guide](https://support.apple.com/en-us/111785)
describes sharing cellular access with other devices. A same-phone self-hotspot
connection is not a supported route for this workflow. The app neither spoofs
iOS's network type nor changes system cellular/airplane-mode settings.

## Validation and limits

- Complete production models plus their public XCTest fixtures pass 17 tests
  via `build/test-storage-memory.py`: four new read-ahead tests and the existing
  13 memory/storage tests. Fixture and source SHA256s match the tested bytes.
- Release compilation and 88 IPA checks pass. All
  219 production source files match the
  reviewed host bytes, with ZIP CRC and Files App flags checked independently.
- Native artifact records and retained runtime DLLs are byte-identical to r30.
  No pin, shader, audio, cloud-save or game-data changes are included.

No phone was connected or controlled. No Windows game was launched for these
read-ahead/settings-only changes. No live saves or cloud data were written,
no IPA was publicly uploaded, and no new public download link was generated.
Actual startup speed, RAM, heat, FPS, restored cellular operation and the prior
startup access violation still require owner testing. These changes do not
establish that every game can launch or run without JIT.
