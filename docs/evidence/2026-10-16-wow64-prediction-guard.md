# i386 prediction guard and distinct exception evidence

The owner supplied the 21:27:33 report from r6, without phone access. The
report contains several launches with different memory preferences. Raw
reports, private paths, game bytes and stack contents remain in the ignored
local build area; none are published with this record.

## What r6 actually changed on the device

- Economy launches use a 256 MiB pool and Wine reports two processors. One
  starts at about 317 MiB footprint; an economy-disabled 512 MiB launch starts
  at about 574 MiB. These are startup observations, not a controlled full-game
  peak comparison. Later economy samples reach roughly 1039–1098 MiB.
- A 768 MiB native arena reaches the ARM64EC root through `handoff-v2` and the
  root starts successfully. This confirms the r6 handoff fix on this device.
- Economy runs retain room in both JIT and FEX arenas. End samples show about
  198 MiB of executable pool room, no pool exhaustion, no arena refusal and no
  RAM-admission refusal. The disabled run reproduces the older 998 MiB arena
  occupancy / failed 16 MiB span / failed ThreadState sequence.
- Two economy runs show the game's Access Violation dialog, then return exit
  code zero around 29 seconds without a detected first frame. Another ends
  with c0000005. Neither a zero code nor available RAM establishes a working
  game. The remaining startup failure is not explained by the safety margin.
  The player's latest margin choice is preserved.

## A concrete emulator defect exposed by this run

The WoW64 translator reaches a call-return prediction-stack guard page while
executing the i386 NtQueryPerformanceCounter stub. The logged host address is
outside the predictor allocation. This is host emulator metadata, not a
valid guest pointer; turning it into a truncated guest access violation is a
secondary failure, and cannot repair the guest.

All three existing inline predictor bounds checks (direct call, indirect call,
return) were guarded by `ARCHITECTURE_arm64ec`. The iOS WoW64 module is pure
aarch64 and missed them. FEX patch 0025 enables those same checks for
`FEX_IOS_HOST`, retaining the [base+2 MiB, base+6 MiB) window and midpoint reset.
It leaves the ARM64EC register reload and state writeback architecture-specific:
WoW64 keeps its live x25 between translated blocks, whereas ARM64EC uses x17.
The prediction cache is not the guest's call stack. The out-of-range recovery
diagnostic also stops dereferencing the invalid pointer just to print entries.

This fixes a proven guard omission. It does **not** establish that the main
game's fatal startup exception, graphics initialization or first frame is fixed.
For example, an IsBadReadPtr probe at a deliberately invalid address appears
in the report and is recoverable; it must not be called the root cause merely
because it is an early access violation.

## Evidence that survives the next failure

Wine PE patch 0036 replaces the first-sixteen-fault cap with at most 32 distinct
records keyed by thread, exception code, instruction, caller and fault page.
Each includes registers, eight stack words and up to four SEH links. Only
current-stack ranges are inspected, through NtReadVirtualMemory with a full
read check. Failure to read is diagnostic data, not another dereference.
The fixed table allocates no memory, skips rather than waits on contention,
and preserves LastErrorValue and LastStatusValue. These remain local user
reports, not telemetry or uploaded dumps.

The app disables only Wine's file **warnings**, whose expected missing control
file poll overwhelmed this report; file errors remain enabled. The supported
`warn-file` syntax is documented in the pinned ntdll debug parser. Build and
compatibility records now include the changed WoW64 bridge identity.

The startup outcome also checks the current launch's Windows message: an exit
without a detected frame within 60 seconds and with a dialog is shown as
startup ending, even with code zero. Message-less exits retain the existing
ten-second rule, drawing clears this condition, and later session messages
do not extend it. Only current-launch log bytes are parsed.

## Verification and candidate

`build/test-wow64-callret.py` extracts all three production guards, compiles
them with FEX's real header-only AArch64 emitter and CPUStateFrame offsets,
and executes the resulting instructions under Unicorn 2.1.4. All 120 cases
pass across old WoW64, fixed iOS WoW64, ARM64EC and unchanged native WoW64,
covering both bounds, invalid pointers, flag preservation and unrelated
registers. The old iOS WoW64 emits no guards and leaves the observed underflow
pointer unchanged. This is an instruction-level host test, not a whole-game
or full translated-block test. A local Python can be prepared with
`python3 -m venv .work/guard-test-python` and that environment's pip installing
`unicorn==2.1.4`.

`build/test-exception-evidence.py` compiles the actual policy header and logger
with ASan/UBSan. It verifies a duplicate flood, the 32-key cap, busy-lock behavior,
eleven stack-range cases, 80,000 concurrent duplicate claims, fault-contained
failed reads, preservation of both error fields, and logging only safe current
stack spans. Native memory reads and logging are modeled; this does not prove
device exception delivery. The existing CPUID ASan regression passes; all 31
selected Swift route, JIT, safety, title-memory and launch-diagnostic tests pass,
including the newly observed 29-second zero exit with an error dialog.

The pinned production recipes rebuild both FEX modules and only the WoW64
exception bridge. Guarded migrations retain every other checkpoint artifact
and validate exact appended patches. No pins move. Packaged module SHA256:

| Module | SHA256 |
| --- | --- |
| aarch64 xtajit.dll | `61e35fc346eb22a4941a59153a1dd3eba1b57e4424bdc463aa59c238292556ef` |
| ARM64EC xtajit64.dll | `5b87653285df4296c77f373094a251f2ce09121ab6087889c09733800c06fa31` |
| aarch64 wow64.dll | `611cba6bea3df3bf29c482513394e1ce2d30598ca7757374df1e6c8331be1390` |

The unsigned r7 IPA passes all 87 verifier checks, SHA256
`8c1b62ed776430e95ffb6ad0e40aa71b51dfc9ea0d0203e237cefe635dc8e1c5`.
The packaged hashes, diagnostic marker and executable revision are checked
directly before delivery. Existing broad tooling failures remain unresolved;
no full-suite pass or successful iOS game launch is claimed. The owner will
side-load and return another report; no phone connection or control was used.
