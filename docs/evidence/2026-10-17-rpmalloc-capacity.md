# Senren Banka: allocator capacity, list invariants and diagnostic overflow

## Observed failure

The owner report ending `20261017-001229` contains an r9 launch with matching
runtime hashes. After approximately 5.6 seconds the guest exits with
`0xc0000017` (`STATUS_NO_MEMORY`), with `first_frame=0`. The app survives and
records the exit. The 768 MiB translator arena reports 737 MiB used, 31 MiB
free, zero 16 MiB span slots, 31 span-sized mappings and 11 thread stacks.
Four further 16 MiB aligned requests fail. This is a reserved address-space
capacity/fragmentation failure, distinct from physical RAM pressure.

Sixteen allocator diagnostics also report `bad=0x20`: an available-list
head retains a predecessor. The guard requires that predecessor to be NULL,
but valid head removal and full-to-available insertion did not maintain it.
The check's diagnostic itself writes more than 256 bytes of fixed fields
into a 256-byte stack buffer. ASan reproduces that overflow with the real
function and the real `consume` operation name. The report proves that the
buggy diagnostic was reached; it does not establish which subsequent game
state was changed by its overflowing writes.

The report does not establish an intentional non-Windows detection failure.
The recovered early C++ exceptions, CP932 conversion and prior suspend-gate
behavior do not justify changing successful Windows API contracts.

## Fixes

`rpmalloc/0004` maps 4 MiB small spans and 4 MiB medium spans on iOS, instead
of 16 MiB each. Small pages remain 64 KiB (64 pages per span). Medium pages
are 1 MiB (four per span), retaining four independent medium classes per
span and the full 256 KiB medium class. Large spans/pages remain 16 MiB and
the complete 8 MiB large class remains supported. All span bases retain
16 MiB alignment and the original mask-based owner lookup; page counts
come from the actual requested span size. Non-iOS geometry is unchanged.
This avoids increasing medium span counts merely to save mapped bytes.

`0005` clears the new head's predecessor on available-list removal and
clears the inserted head's predecessor on full-to-available transitions.
`0008` sends a full page through that transition before its last local block
is freed. One-block large pages expose this case in the real allocator.
The corruption guard remains active, including after its logging cap.

`0006` checks a failed thread-heap metadata mapping before commit/initialize,
retains the fallback TLS heap on failure, and returns allocation failure
instead of recursively retrying an uninitialized heap or attaching a huge
allocation to it. A later allocation can retry. Failed realloc leaves the
original block intact.

`0007` increases the diagnostic buffer and bounds every text/hex append,
reserving space for its final newline. Logging remains allocation-free.
This removes the diagnostic's own overwrite without hiding a bad list.

## Validation

`build/test-ios-rpmalloc.py` compiles the supplied complete allocator core,
size-class table and modified functions with ASan/UBSan and assertions.
It selects the actual iOS geometry definitions, then uses Linux TLS and a
modeled 768 MiB mapping backend rather than Windows/iOS OS glue. The backend
enforces 64 KiB granularity and the requested 16 MiB span alignment. Windows
logging and the disabled allocation watcher are stubbed. This is not a
complete FEX execution or an iOS game/RSS measurement.

Ten concurrent worker heaps each retain 37 live size classes: 32 small,
four medium and one large. The old core reserves approximately 480 MiB;
the new core reserves 240 MiB, with the same 30 aligned span mappings.
All block bytes survive until cross-thread freeing. Tests also cover every
class boundary through 8 MiB, realloc preservation, alignments through
64 KiB, head transitions, rejected bad backlinks, oversized diagnostic
labels, guard behavior beyond the log cap, metadata failure on main/worker
threads, retry after capacity returns and huge/aligned/realloc failure.
The old head-transition and diagnostic tests fail; the new tests pass.

The production ARM64EC and WoW64 DLLs rebuild through the pinned recipes.
The guarded migration verifies all 1,615 checkpoint files and permits only
the two FEX images and their manifest records to change. The scratch pool,
complete WoW64 initialization failure-injection, 120 actual AArch64 guard
cases and CPUID regressions pass again. No phone connection/control or
Windows game launch was used.

| Image | SHA256 |
| --- | --- |
| aarch64 xtajit.dll | `5efa1af0a262d0a24bdeaa11a17df1868a127109b82b2f9aadbd4a6a354213ba` |
| ARM64EC xtajit64.dll | `6b7f33370de86b06ff078556f3fea945cd50947ef91d29246d9ee036b237de10` |

## Remaining risks and likely next stages

The arena is still bounded. Different class mixes, more live threads,
large pages, prediction stacks and JIT buffers can exhaust its aligned
slots even when total free bytes remain. Existing allocation scans, arena
totals, largest gap, refusal counts, native hashes and the r10 allocator
identity remain in reports. The old generic `spans` census counts 16 MiB
mappings; after this change it is not a count of all rpmalloc spans. Use
total used/free bytes and failed request size/alignment together.

Once execution reaches graphics, movie startup and D3D9 partial presentation
may be separate issues. A [DXVK upstream report](https://github.com/doitsujin/dxvk/issues/4754)
specifically describes Senren Banka flicker/black screens and discusses
partial presentation and layered splash videos. Other contributors could
not reproduce it on different GPUs, so it is a conditional lead, not proof
of this app's current failure or evidence that changing renderers fixes it.
The new owner log should first establish successful thread creation and
whether a D3D device, video or first frame is reached before changing that
path. No renderer switch or blanket API-success emulation is included.

The allocator's [upstream documentation](https://github.com/FEX-Emu/rpmalloc)
describes its per-thread heaps, three page types and alignment-based header
lookup; the port preserves that lookup contract.

The owner must side-load the new IPA in place and run the game to establish
whether this fixes the observed launch. Compatibility remains unverified;
neither a successful game launch nor a full repository test pass is claimed.

The `SteamGlass-20261017-r10` unsigned IPA passes all 87 package checks.
Its losslessly compressed archive is 182,718,736 bytes; packaged FEX hashes
match the table above, and the prior Wine/host images remain unchanged.
IPA SHA256:
`c9e0659f8c77c858a12b77d13e41edec959c76f121c8145d7dda3f1f32723a35`.
