# 0070: Optional global workers, bounded artwork and storage cleanup

**Status:** accepted, 2026-10-18, at the owner's request. Amends
[0069](0069-title-memory-economy.md), and expands Settings cleanup under
[0056](0056-fex-disk-cache-on.md). See the
[evidence](../evidence/2026-10-18-memory-storage-economy.md).

The existing default-enabled RAM economy switch now advertises two processors
for all games, unless explicit per-title cpu-count overrides it. This limits
automatic worker fleets in engines that use the reported count, not CPU
affinity or every thread a game creates. Games that need parallelism can lose
performance; the switch is reversible. Other titles keep the general 512 MiB
JIT pool and their arguments.

The recognized i386 KiriKiri budget also covers Steam app 2458530. Its supplied
startup pool uses a 26 MiB head and 161 MiB tail, with no refusals, so it selects
the same 256 MiB capacity as 1144400. Both engine profiles use normal memory mode,
64 MiB graphics caching and two drawing workers; normal caching avoids the
repeat decoding caused by the old zero-cache low mode. Continuous work is
bounded to panel cadence even with unlimited presentation. Explicit launch
arguments and pool overrides win. Later-scene headroom remains unverified;
capacity cannot grow during a play. Memory-safety headroom is independent.

A shared NSCache has a 24 MiB estimated decoded-art cost budget and 48 entries.
It may evict under pressure, and title startup releases its cached references.
This is an advisory artwork budget, not a total application RAM limit.

Storage cleanup has one UI action. When idle it removes only rebuildable DXMT,
KosmicKrisp and FEX DiskCache files plus exported report ZIPs older than a day.
During any active title session only those old exports qualify. Launch and
idle cleanup exclude each other on the main actor. Scan bounds and link
rejection prevent an unbounded traversal or redirected deletion. Saves, cloud
backups, account state, game assets and publisher originals stay intact.
There is no asset-name deduplication, lossy audio conversion or live-game
repacking. Cold cache reconstruction can increase loading work. Removed
logical bytes are reported separately from any claim of physical free space.

No new interpreter or cellular VPN capability is claimed. The current runtime
requires JIT; upstream documents limitations of the local loopback on cellular.
Settings explains the supported setup and manual network workaround.

Production-model tests and release compilation validate the implementation.
Device RAM savings, FPS, heat and startup success require owner testing; a
new access violation in the supplied report is not established as fixed.
