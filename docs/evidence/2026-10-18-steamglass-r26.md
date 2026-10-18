# SteamGlass r26: bound per-thread return prediction storage

IPA SHA256: `73c460e33c4cbaf4f631d5324b1dc382034c2e417a562e15c384336158450840`

The owner's new report identifies r25 and two guest exits with
STATUS_NO_MEMORY (0xc0000017), after 34 and 16 seconds respectively. Both
reach a first frame. The process is restarted by the existing recovery path.
The report also contains a separate, earlier built-in JIT tunnel timeout;
changing prediction storage does not fix network/VPN readiness.

## Evidence and change

Both completed launches reserve the 768 MiB WoW64 fallback arena after larger
reservations fail. The first refusal occurs with 44 or 43 call-return stacks
and approximately 753 or 759 MiB occupied. Subsequent thread initialization
fails. Ordinary physical-memory safety checks record no denied commitments;
the last samples retain approximately 1.2 GiB available with a 500 MiB reserve.
This is a bounded emulator address-space failure, independent of that reserve.
The existing shape-based census cannot distinguish every rpmalloc view from
an identically sized L1 view; its L1 count is not a live-thread count.

FEX now reserves 4 MiB plus guards per iOS prediction stack, instead of 8 MiB.
The default is base+2 MiB and the guarded window is [base+1 MiB,base+3 MiB).
The downward half holds 65,536 sixteen-byte predictions. This is a return
target predictor, separate from the guest's architectural stack. Its existing
overflow behavior resets prediction state and falls through to ordinary target
lookup on a miss. All three emitted CALL/RET guards now take the named constants,
as the callback guard already does. No host-register layout or guest-stack
size changes. Other hosts retain their previous constants.

Full-allocation decommit/reset, zero initialization, guard pages, top-down
packing, allocation failure containment and the prohibition on placement outside
the owned host arena are retained. No rpmalloc span/mask changes, unconstrained
allocation fallback, larger memory limit or unsafe disk cache are introduced.
The native census and failure-report default offset match the new geometry.

At the observed 43..44 stacks the reservation reduction is approximately
172..176 MiB. This is virtual-address capacity, not a promise of equivalent
physical-memory or battery savings. Initial scrub and whole-cache reset ranges
are halved, but their phone timing is unmeasured. A finite arena can still
exhaust with more threads or other allocation growth.

## Other report findings

Seven five-second render samples range from 36.3 to 55.0 FPS, at a 2338x1061
or 2338x1080 drawable. Maximum gaps reach about 617 ms. CPU readings reach
157% (100% is one core); thermal state is nominal or fair in these samples.
Both producer work and drawable waits contribute. This change addresses the
reproducible allocator failure; it does not establish stable 60 FPS, a lower
temperature or longer battery life. Existing explicit resolution/FPS settings,
audio, the r25 edge control and save protections are retained.

Cloud logs include successful reconciliation of 25 remote files with no
outstanding transfers/conflicts, and successful uploads of two changed system
files before play. The transfer audit matches all 25 native files to the last
observed Steam hashes; the separate later backend audit differs for two system
files after gameplay writes. This is evidence that transfers and placement
occurred, not proof of the player's intended restored chapter, nor a live
query at report export. No live saves or cloud account are accessed here.

## Validation

Actual Windows callret initialization, teardown and reserve/commit failure
paths run under ASan/UBSan against a bounded mapping fixture. Holding 460 MiB
of other users in a 768 MiB arena, the previous real geometry starts 38 of 64
threads; the new geometry starts all 64 and releases every mapping. This is a
host capacity experiment, not an iPhone game run.

The real AArch64 emitter runs under Unicorn: 375 boundary/register/flags cases
cover all three guards, both iOS targets and unchanged non-iOS behavior; 54
callback cases execute the guard and sentinel push inside a 4 MiB mapping.
The actual native census fixture passes. Scratch ownership/reuse and concurrent
init-failure tests, CPUID tests and rpmalloc tests are also rerun on the built
source. The two FEX images are rebuilt through the patch series. Only virtual.o
and signal_arm64.o are replaced in ntdll's archive; every other archive member
and all other runtime components are byte-checked unchanged.

60 HostIOKit and 22 selected PlayportKit tests pass. Release compilation and 88 IPA checks pass. The package is independently checked for the new revision and prediction marker, both FEX hashes, the ntdll archive record, unchanged other native components, source/runner equality and Files flags. The 1,615-file native checkpoint is verified after the three permitted runtime replacements.

The owner has requested report-based testing without phone access. No phone
connection, public download upload, save mutation, usage reset or shutdown is
performed. Actual post-fix startup, stability, FPS, power and edge-control
appearance remain unverified until the owner's sideload test.
