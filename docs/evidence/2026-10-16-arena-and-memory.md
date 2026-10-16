# r3 startup arena failure and configurable RAM headroom

The owner-supplied 173955 report identifies `SteamGlass-20261016-r3`, the
rebuilt native archive and both CPUID-fixed FEX modules. The fresh launch
starts after the r3 build marker. Earlier Unicode and relocation faults
in the same log belong to preceding launches and are not this run's result.

The fresh run reserves the full 4 GiB i386 guest window at `7038000000`,
but all ten host-arena candidates fail. Native mappings begin at
`7170800000`; the remaining gap after the guest window is about 904 MiB.
The smallest existing arena is 1 GiB. FEX cannot obtain its initial heap,
and the session root returns `-5` before starting the game. This report
neither confirms nor refutes r3's later guest-subpage repair.

## Arena change

Madeira patch 0102 adds 768 and 512 MiB candidates after the existing
ladder, only for i386 titles, and lowers the WoW64 pre-CRT handoff validator
to that 512 MiB floor. The complete guest window stays reserved; native
reservation, registration and publication still use the actual bounded
interval. No unconstrained fallback, component pin or FEX binary changes.

`build/test-fex-arena-capacity.py` compiles the actual complete production
selector, with a mocked Mach address map. The original ladder fails with
904 MiB free; the new selector reserves 768 MiB. A 600 MiB gap selects
512 MiB, a 500 MiB gap publishes nothing. x64 skips the small candidates;
an 8 GiB placement still succeeds. Registration failure releases the held
range and publishes nothing. The production PE data-export/CRT handoff
test also checks 512, 768 and 1,024 MiB intervals under UBSan.

These smaller arenas can still exhaust during later gameplay; their
successful reservation is not evidence of a successful first frame.

## Requested RAM policy

The owner requested a configurable safety margin, default 100 MB. Settings
now offers 50, 100, 150, 200, 300, 500, 750 and 1,024 MiB, applied at the
next title start. The UI samples process footprint and OS availability
every second. The reported target follows current use plus the selected
margin, capped by the OS-reported limit; it is not a physical allocation.
An early warning appears when remaining RAM is below twice the margin.
Denials and a ten-second usage/target record are retained in the log.

Patch 0103 checks new local Wine `NtAllocateVirtualMemory` and `...Ex`
commitments against live OS availability, preserving the selected margin
under a conservative assumption that all newly committed bytes become
resident. Existing logical commitments are not charged twice; reserve-only
requests retain their sparse behavior. Rejection returns `STATUS_NO_MEMORY`
before the operation, increments an atomic counter, and emits at most 24
records. A refusal is shown by the live warning and included in the
launch-failure detail when applicable. The JIT preflight separately checks
its fixed pool plus the margin before runtime startup.

This is admission control for new Wine commitments, **not** a hard RAM cap
at use-plus-margin. It cannot preempt writes to already committed pages,
control UIKit/Metal or every file-backed mapping, predict future game
needs, override iOS jetsam limits, or reclaim live game data. Concurrent
allocations and the OS reporting interval also limit physical guarantees.
Conservative admission may reject a large sparse commitment even if the
game would not immediately touch all its bytes. The JIT pool remains fixed
after activation; changing its size in place is unsupported.

The native regression compiles the production admission header and actual
logical-page growth helper against mocked OS availability and Wine views.
It covers the exact margin boundary, oversized requests, zero availability,
clamping and recommitting existing pages. Swift policy tests cover rising
and falling use, changing limits, warning thresholds and integer overflow.

Only `virtual.o` was rebuilt with the production Darwin recipe. All 34 other
native archive members were byte-identical. Native archive SHA256:
`028d570e4b5246eced39f535aa9250ff828c117bb9db12f8e0672dc378e91a81`.

## Verification and handoff

The 25 selected AppRoutes, LaunchDiagnostics and MemorySafety Swift tests
pass, as do the capacity, native admission and pre-CRT handoff regressions.
The focused WoW64 suite is also run for this candidate; Wine-cache-dependent
resolver/CREATESTRUCT tests remain unavailable. The previously recorded
broader tooling test failures are not reported as resolved by this change.

The final unsigned release IPA passes all 87 verifier checks. SHA256:
`1effae75173dcf6d9598d67db1ccd66814ec6bfa1301680ea4d5fab8854787d4`. A binary audit confirms r4/v4 identity, both smaller
arena candidates, the admission log marker, settings preference key and
retained subpage repair; the packaged manifest matches the rebuilt archive.
No phone connection or control was used. The owner will sideload and
return the next report. First frame and actual UI display remain unverified.
