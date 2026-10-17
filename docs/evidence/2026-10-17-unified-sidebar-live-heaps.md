# Unified glass sidebar and bounded live translator heaps

The owner confirms r17 audio is now satisfactory. The game's title page is
nearly stable, but its settings page averages about 30 FPS with an uneven
graph; some early launches fail and Steam progress still appears fresh.
No r17 report was supplied for this change. The retained r16 report establishes
one arena exhaustion; it cannot establish the cause of every new failure.
No phone was connected or controlled. No game window was opened on Windows.

## Arena capacity

The earlier failure fills a 768 MiB translator host arena to about 758 MiB,
with no contiguous space for the next roughly 8 MiB call/return window.
A later launch obtains a 1024 MiB arena and reaches approximately 911 MiB.
The physical-memory admission monitor reports no denial in that failure.
Reducing wasted mapped space is justified; merely changing the physical RAM
reserve does not repair this separate address-space limit.

rpmalloc patch 0010 changes owner mask, alignment and all cached span sizes
from 4 to 2 MiB together. Medium pages become 512 KiB; cached large classes
stop at 1 MiB and larger requests retain the exact-size huge mapping path.
The public alignment limit, non-iOS geometry, call/return window, scratch
ownership, JIT cache policy and live-heap ownership are unchanged.

The actual allocator core, with iOS geometry and a 768 MiB bounded Linux map
backend, passes ASan/UBSan. This is host capacity evidence, not phone RAM or
gameplay performance:

| Workload | r17 | r18 |
| --- | --- | --- |
| 10 simultaneous heaps, 37 size classes | 120 MiB mapped | 60 MiB mapped |
| 40 simultaneous heaps, 400 MiB other state | 766 MiB mapped, 220 refused requests | 642 MiB mapped, zero refusals |

The pressure workload is synthetic, not a replay of the game's allocation
trace. Both versions retain successful allocations through the pressure
barrier and free them cleanly. Additional cases cover every size-class
boundary, realloc preservation, remote frees, metadata/huge OOM and recovery,
supported alignments, 1/2 MiB threshold boundaries and 8/16 MiB blocks. The
existing fragmented-arena fixture retains its canaries and supports actual
small, medium, large and aligned huge allocations.

A rejected prototype mapped only 1 MiB of small/medium spans while retaining
4 MiB ownership units. Its ordinary workload shrank, but the same pressure
workload still refused 753 requests at 538 MiB mapped because the holes were
unusable for additional rpmalloc owners. It is not shipped. This is why the
final change adjusts owner geometry and cached classes as one unit.

Only two FEX runtime images change in the native checkpoint. The migration
validates the exact append to the r17 patch series, protected native inputs,
PE machine types and the output delta, then saves/verifies all 1615 outputs.
The iOS scratch ownership, WoW64 initialization failure, actual AArch64
call/return/callback boundary and CPUID sanitizer regressions also pass.

## Shared sidebar

Launcher and game use the same `GlassSidebar`, row presentation, glass shape,
spacing, camera/home-indicator clearance and spring slide/fade transitions.
Reduce Motion uses a short fade. The launcher has one menu button; its old
three-entry top navigation is replaced by the drawer. Root page views remain
mounted to retain their state. Controller menu/up/down/A/B work with the
drawer, and Settings section rows use the same presentation without nested
buttons or losing their existing focus behavior. The game retains its pause,
resume and input gate. The screenshot row no longer claims a photo was saved
before a capture occurred. Appearance is compiled, not inspected on a phone.

## Steam evidence and frame timing

The exact bundled i386 emulator was tested in a hidden Windows process with
an isolated synthetic save root and networking disabled. Its modern flat API
and the game's Client017/RemoteStorage013 vtable read the exact synthetic
bytes. The legacy interface enumerates all three synthetic files, accepts a
NULL size pointer, returns correct sizes, retains returned name strings and
reads each listed file. These native Windows results do not establish that
the real phone save set is loaded correctly through FEX.

Steam's [RemoteStorage documentation](https://partner.steamgames.com/doc/api/ISteamRemoteStorage)
defines enumeration and file reading separately. The pinned emulator's
[enumeration implementation](https://raw.githubusercontent.com/Detanup01/gbe_fork/7103add7ca6ef3ef8353279219880068f2494fc8/dll/steam_remote_storage.cpp)
and [storage iterator](https://raw.githubusercontent.com/Detanup01/gbe_fork/7103add7ca6ef3ef8353279219880068f2494fc8/dll/local_storage.cpp)
were inspected. No speculative interface or save-path change is applied.

The service now retains the actual pre-transfer remote list separately from
the agreement baseline. Exported `steam-save-transfer.txt` compares recognised
save names and SHA1 values against both local backends; it labels the snapshot
as historical, not a live network query. It omits account identifiers, arbitrary
cloud names, payloads and linked files. Reads are bounded to 64 names, 2 MiB per
file and 8 MiB total. Old records decode with an unavailable snapshot until the
next sync. The existing forced download, hashes and backups remain intact.
Tests cover matched/different copies, blocked links, privacy and old records.
Successful transfer is still not proof of a successful semantic game load.

Frame health adds actual presentation interval mean/standard deviation and
maximum drawable-request arrival gap, alongside existing limiter/drawable
waits. It uses constant-space arithmetic without texture readback or synthetic
frames. A test distinguishes steady 30 FPS from uneven frames with the same
average and checks late callback handling. The public KiriKiriZ reference
[draw device](https://github.com/krkrz/krkrz/blob/fd5c4baa6a2ef5978db1bd043634351f48667daf/visual/win32/BasicDrawDevice.cpp)
polls raster status for vblank; its
[initialization](https://github.com/krkrz/krkrz/blob/fd5c4baa6a2ef5978db1bd043634351f48667daf/base/win32/SysInitImpl.cpp)
already requests high timer precision by default. That makes timing a useful
investigation path, not proof this game's settings page shares a specific
upstream bottleneck. No unverified renderer flags or timer override is added.

## Candidate and limits

IPA SHA256: `86a4149906827adebe3e6cbac3a6e5bb469dadc2e8556370c3249980fcdd889c`

- 50 HostIOKit, 36 Cloud/Steam API and 14 selected PlayportKit tests pass.
- Release compilation and 87 IPA checks pass; the new allocator marker is
  present in both packaged FEX images and every changed production source
  matches the build checkout.
- Preserved audio/ntdll archive:
  `c32057edf9035f00fd9a54cfbd40ee0896efb6d661ec9577e8e92f3741d6991f`.
- Preserved win32u archive:
  `c0e279a03d755fbf9725a66e7e3e95ab24a53b88b6d105935e8be969ea2484b9`.
- New WoW64 translator:
  `ffceff77b919dea7b7f5b0f7a5ce18b0afb89213d6ed2546b56378f88708b938`.
- New ARM64EC translator:
  `650093419b2561e3ec9c2f142269a5b53d0d5e18d14ce6b5a14d69aedee917ec`.

Phone startup reliability, settings-page frame pacing and real Steam progress
remain unverified. The next report must contain this revision, a failed launch
if one occurs, settings-page activity and a cloud retry. Its hashes/open results
can distinguish failed transfer, wrong backend and a game-side load failure.
