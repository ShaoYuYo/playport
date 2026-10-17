# Senren Banka: r10 aligned-slot exhaustion

## Report

The owner report ending `20261017-123404` contains historical r8/r9 logs and
two new r10 launches. The r10 native hashes match the delivered images.
Both launches still exit `0xc0000017` before a first frame. In the 768 MiB
arena the final census reports 455 MiB used, 313 MiB free, a largest gap of
12 MiB and zero 16 MiB span slots. A 4 MiB request with 16 MiB alignment
fails. The 1,024 MiB launch also fails, with 435 MiB free and 17 threads.
Increasing the arena alone did not remove the alignment problem.

The layout dump shows repeated 4 MiB mappings at 16 MiB boundaries, with
12 MiB holes between them. The retained alignment from r10 prevents the
allocator from using those holes. Reducing reserved bytes was useful but
insufficient. The prior ten-heap test checked class density and total
capacity but did not reproduce this interleaved layout. The new fixture
and regression cover that missing case. The old bad-head diagnostics are
not present in either new r10 launch; their appearances in the report are
from the preserved r9 log.

No physical RAM admission rejection or deliberate non-Windows detection
is established by these failures. The observed failure remains in the
translator's reserved address-space arena. Graphics first-frame behavior
is still unknown.

## Change

`rpmalloc/0009` changes the iOS span size/alignment and lookup mask together
to 4 MiB. Small and medium cached spans remain 4 MiB; the cached large page
also becomes 4 MiB. Cached large classes end at 2 MiB, and requests above
that size take the existing exact-size huge mapping path. All allocation
sizes, including 8 MiB and larger, remain supported. Huge user pointers and
supported aligned pointers lie within the first span unit, preserving
mask-based header lookup even when their payload extends beyond that unit.
The size-class table, counts and realloc large/huge threshold change
together. Non-iOS geometry remains unchanged.

This is not an alignment-only edit: retaining 16 MiB cached pages or their
8 MiB block classes behind a 4 MiB mask would make owner lookup invalid.
It also does not release live allocations, lower game data limits, change
the JIT pool or silently expand the configured arena.

The r11 build marker records `rpm=span4-v1`. The duplicated r10 allocator
marker is removed from the app summary. The standard arena census still
classifies 16 MiB mappings using its old generic labels; use failed request
alignment and total bytes rather than interpreting `spans` as an rpmalloc
span count.

## Reproduction and checks

`build/tests/fixtures/host-arena-r10.json` contains 71 relative mapping
runs derived from the 768 MiB first-refusal dump. Device addresses, account
information, private paths and game bytes are omitted. The model rounds
each mapping to a 64 KiB allocation granule, conservatively occupying about
457 MiB and leaving about 311 MiB free. This differs slightly from the
runtime's byte census, but retains the observed holes and aligned-slot
failure. The arena base is 16 MiB aligned in both old and new tests.

`build/test-ios-rpmalloc.py` compiles the actual allocator core with iOS
geometry, assertions and ASan/UBSan; Windows OS/TLS glue is replaced by Linux
TLS and the bounded mapping backend. The backend zero-fills fresh/reused
mappings and models decommit rather than reusing stale backing bytes.
Pre-existing fixture mappings are unavailable to the allocator and retain
canaries at their boundaries. This models allocator behavior, not the
complete iOS/Wine/FEX execution.

On the r10 tree, `--expect-fragmented` reproduces failure to allocate the
small block that needs the next 4 MiB span despite hundreds of free MiB.
On the patched tree, the same layout supports actual small, medium, large
and 64 KiB-aligned 8 MiB allocations. All fixture canaries remain intact
after freeing and finalizing. A direct 4 MiB request at the old 16 MiB
alignment still fails, confirming that the layout is genuinely restrictive.

Ten live heaps holding 37 size classes each reserve approximately 120 MiB
under the new geometry, versus r10's 240 MiB, with 30 span mappings in both
cases. This is reserved address space in the host model, not game RSS.
Every cached class boundary, allocations around 2 MiB, and explicit 3, 4,
5, 8, 9 and 16 MiB requests pass data-preserving realloc checks. Aligned
large requests through 128 KiB, cross-thread cached and 8 MiB huge frees,
metadata OOM/recovery, failed realloc preservation, list invariants and
bounded diagnostics also pass.

The two production FEX images rebuild from the pinned recipes. The scratch
pool and complete WoW64 initializer failure-injection checks, 120 AArch64
guard cases and CPUID regression pass again. The guarded checkpoint
migration verifies all 1,615 native outputs and permits only those two
images and their manifest records to change.

| Image | SHA256 |
| --- | --- |
| aarch64 xtajit.dll | `3ecc1a5925af7828afa92834b81a3beba2f1b772e792ef4b02c778ab6378c516` |
| ARM64EC xtajit64.dll | `2e8a4f8ae490329379dac1d5dc31dd04f7ce7bf17c01e95626fd1352fdc4075f` |

The arena remains bounded: more live threads, large contiguous requests or
JIT/prediction-stack demand can still exceed its capacity. Once this failure
is passed, graphics and video startup may expose separate compatibility
issues. No renderer change is inferred from this memory failure.

No phone connection/control or Windows game launch was used. Successful
game execution remains unverified pending an owner side-load run; no full
repository-suite or iOS play pass is claimed.

The unsigned `SteamGlass-20261017-r11` IPA passes all 87 package checks.
Its archive is 182,720,107 bytes with lossless ZIP compression. Packaged
FEX hashes match the table above; the prior Wine/host hashes are retained.
IPA SHA256:
`1ff4ed2413e1aada1660682d35628922455e5cb09bd36779532f1c14e814488d`.
