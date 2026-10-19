# Worker, artwork and storage economy

IPA SHA256: `51ef853f7c5a04ab0d6284e8f573ab8de418b2ec6a7acd810f7a7aecb98aae44`

The owner's r29 report for Steam app 2458530 passes the signed executable
readback path, but neither attempt produces a first frame. The later run
reports a fatal access violation and exits zero after about 39 seconds.
Its peak footprint is 1,566 MiB; the other attempt peaks at 1,629 MiB.
No memory-safety commitments were denied and neither JIT pool exhausted.
The later allocator census reports 33 threads, roughly 122 MiB in L1 heaps,
and a 512 MiB JIT pool with a 26 MiB head and 161 MiB tail. Thermal state
is serious at launch. These are startup observations, not a gameplay FPS
benchmark or proof that memory pressure caused the access violation.

## Changes

The existing RAM economy switch now applies optional CPU worker reduction
to every title, including imports without a Steam ID and 64-bit games.
Explicit per-title cpu-count settings win, and opting out restores existing
behavior. General titles retain their normal JIT pool and arguments: engine
switches and smaller pools are not safe to apply indiscriminately.

The measured 32-bit KiriKiri profile now includes app 2458530 as well as
1144400. It defaults to a 256 MiB pool, two advertised processors, normal
engine memory mode, a 64 MiB graphics cache and two drawing workers. Panel
cadence bounds continuous updates even with unlimited presentation. Player
arguments win. The pool capacity reduction is exactly 256 MiB for app
2458530; this does not predict a 256 MiB measured footprint reduction or
promise lower RAM for every later scene. Smaller worker fleets may hurt
CPU-parallel games, so the all-game option remains reversible.

All stores' artwork now shares NSCache with a 24 MiB estimated decoded-RGBA
cost budget and 48-entry limit, replacing permanent decoded-image dictionaries.
The budget is advisory, not a process memory cap. Starting a title releases
cached artwork references. Views may retain their currently displayed image;
disk images remain available. Eviction can reload GOG/Epic/local art from disk
without being blocked by the old permanent loading-key sets.

Settings exposes one storage cleanup action, with progress and counts of
removed logical bytes/files. When idle it clears only the app-owned DXMT,
KosmicKrisp and FEX DiskCache locations and exported report ZIPs older than a
day. While a game is running, including startup or pause, only those old
exports qualify. Main-actor exclusion prevents a new title from starting
between the idle check and completion of detached file I/O. The scan is
bounded to 20,000 entries and rejects symbolic roots, ancestors and descendants.
It does not recurse through Games, general Wine temporary files, saves,
Cloud Backups or account data. The old FEX helper also now targets DiskCache
rather than its parent containing configuration. Cache removal can increase
first-load work; it does not optimize FPS. Logical removed bytes need not
equal immediately freed APFS storage. There is no lossy audio recompression
or speculative asset/name-based deduplication.

The required publisher originals remain: the r29 phone report confirms the
executable readback is used during startup. Deleting that roughly 4.6 MB
file would reinstate the known signature failure. No live user data was cleaned.

No no-JIT execution backend exists in this runtime. Its actual launch must
acquire executable memory before Wine/FEX starts; disabling it does not make
x86 games run. Upstream [JIT documentation](https://github.com/willfaust/Madeira/blob/main/docs/JIT.md)
and the helper's [integration guide](https://github.com/StikDebug/StikJIT/blob/main/INTEGRATION.md)
describe a cellular/local-loopback limitation. Settings now explains the
network-switch workaround and the restart dependency. The app does not claim
to enable JIT while the same cellular route remains active or to control the
system cellular/airplane-mode switches.

## Validation and remaining limits

- Complete production memory/cleanup models and unchanged public fixtures:
  13 XCTest cases pass via `build/test-storage-memory.py`. Cases include
  active-play pinning, recent/old exports, untouched saves/backups/configuration,
  symbolic cache roots/nested links, bounded scans, opt-out, unrelated engines,
  explicit parameters and panel pacing. Test input hashes match production.
- A private Windows game copy accepts the new KiriKiri arguments and has a
  responding game window at 15 seconds. The sample working set is 245 MiB,
  private bytes 239 MiB. These Windows values are not iOS/FEX estimates.
  The live installation's 90 file metadata records remain unchanged. No
  live cloud, phone connection or foreground game window is used.
- Release SwiftUI compilation and 88 IPA checks pass.
  All 219 production source files match
  the reviewed bytes. The ZIP CRC, Files App flags and native artifact
  records are independently checked. Native artifacts are byte-identical
  to r29; no pin, native translation code, save sync or audio changes.

The new IPA is not tested on an iPhone. Device RAM savings, FPS, heat,
later-scene pool headroom and the new startup access violation remain
unverified. In particular this optimization release does not establish that
the access violation has been fixed or that every game can sustain 60 FPS.
