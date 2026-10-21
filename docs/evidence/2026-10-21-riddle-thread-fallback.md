# Riddle Joker: thread allocation fallback and engine profile

The owner confirms Riddle Joker is a GALGAME. The supplied r33 report also
identifies its actual KiriKiri resources: XP3 archives and KAGParserEx,
SteamDrawDevice and k2compat plugins. Its launch nevertheless logs
`engine_profile=general` because the measured profile listed only two app IDs.
Add app 1277930 to the i386 KiriKiri profile, preserving opt-out and explicit
settings. The report's head 26 + tail 161 MiB fits the same measured startup
budget as the existing titles; successful full play is still an owner test.

The fatal sequence occurs before a real first frame: a new thread's 8 MiB
mapping fails, then libc++abi reports an uncaught system_error, "Failed to
create thread: Resource temporarily unavailable", and the title exits 3 after
about 6.2 seconds. JIT is acquired, its pool is not exhausted, and the usable
Metal surface is registered. The r33 kernel ceiling fix is active: the selected
bound is 0x7180000000, below the fixed furniture ceiling 0x73ffff0000.

map_view initialized ceiling_relaxable to false and computed it only inside
the furniture-clamp branch. With the lower real task ceiling, that branch is
not entered. A failed fixed-address scan with the ordinary 4 GiB floor then
returns STATUS_NO_MEMORY instead of reaching the existing anonymous kernel
placement fallback. This is a real control-flow defect; the report does not
establish exhausted physical RAM.

Patch 0112 establishes soft-floor eligibility independently of the clamp.
Caller-supplied upper bounds and higher explicit floors remain strict. Existing
user-limit validation and the 8 MiB guard-stack floor are retained. Failed
scans accurately describe a pending kernel retry; successful recovery is logged
with a bounded va-kernel-pick-v1 marker. It does not enlarge the kernel ceiling
or claim an allocation must succeed under genuine memory pressure.

Eight cases compile the actual production policy/clamp block, including the
reported lower task ceiling, an active clamp, no furniture ceiling and strict
caller bounds. The same harness can compile the previous policy and reproduce
its refusal. A title-profile regression covers Riddle Joker defaults, explicit
arguments and opt-out. Native pins remain frozen.

Apple's VM flags distinguish a fixed address from kernel-selected placement:
https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/osfmk/mach/vm_statistics.h

No phone access, live account/cloud/save writes or visible game launch is
performed by these host checks. Device startup is not proven by compilation.

## Build workflow inspection

The owner asked why the build was taking so long. GitHub's latest PlayPort
workflow run is the completed 2026-10-15 success, run 38716736545 in the separate
build repository; no r34 Actions build is running or queued. The source
repository's Actions runs collection is empty at inspection time.

This artifact is built locally in the preserved headless Linux environment,
using QEMU TCG because the Windows hypervisor is unavailable. The VM starts at
22:37 local time; the retained 1619-file runtime checkpoint is verified, the
changed native archive's 35 units rebuild, and the app-only pipeline starts at
22:46. App compilation and linking progress through Playport-App-product to
Packaging and the IPA write. The remaining steps losslessly compress and
validate the IPA. Logs and increasing VM CPU time establish continued progress.
No repeated full toolchain download or second concurrent build was observed.

The current recovery driver preserves its pre-build checkpoint on retries.
The existing verified runtime is reused rather than rebuilding PE, FEX and
Direct3D. No Windows restart or new Actions dispatch is needed to finish this
artifact. A future hardware-accelerated build environment requires separate
repair of the already diagnosed Windows virtualization configuration.

## Built artifact

IPA SHA256: `59b7b6c64467dce2014be1cb457079d0ef7e2581e18b1fea928b12c836d4f7e6`.

37 Swift cases are verified: 22 memory/storage/JIT cases run for this source,
plus the unchanged r33 display (3) and account (12) suites whose recorded
production/test-source hashes are checked. Eight compiled production fallback
policy cases reproduce the old refusal and pass the fix; five production
ceiling-function cases also pass. All 35 native units and 88
IPA checks pass, and every production Swift source matches the guest build.

Only libntdll_unix.a changes among native artifact records; retained PE, FEX and
Direct3D DLLs match r33. The correct kernel ceiling remains in force.
No phone was contacted, no game was visibly launched, and no live account, cloud
or save writes were performed. Actual Riddle Joker startup and play remain
owner-side checks; the passing build is not proof of successful device play.
