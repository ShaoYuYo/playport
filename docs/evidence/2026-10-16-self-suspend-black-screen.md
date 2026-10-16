# Senren Banka: self-suspend can return before a deferred Mach hold

## Owner report

The owner supplied reports ending in `20261016-233550` and
`20261016-233659`. The current logs identify r7 and all five PE module
hashes match that IPA. The older previous-log section also contains older
runs; those are not evidence of r7 behavior. No phone connection or control
was used. Private logs, game code, device identifiers and filesystem paths
are not included here.

One current r7 launch stays alive with no first frame through footprint
cycle 45. Pointer events are dropped because there is no foreground client
area. A subsequent r7 launch terminates with `c0000005` about 5.4 seconds
after game start, also without a first frame. JIT room remains 198 MiB and
both the arena refusal counter and live RAM admission denial counter are
zero. The black-screen run reaches approximately 1,085 MiB footprint.
These reports do not show an admission or JIT exhaustion failure.

The failing guest instruction is a 128-bit aligned pixel fill store at
`0061de97`, called from the game's bitmap worker. Width is 1,920 pixels,
stride is -7,680 bytes and the fill color is opaque black. The faulting
guest address `0b9d2e40` belongs to a former `0b350000` allocation; at the
fault the Wine view is a larger coalesced `VPROT_WOW64_HOLE`, with no page
access, rather than the prior 0xa90000-byte allocation. The black-screen
run records repeated host protection faults with the matching PC suffix
`0x1f4`, into the same former allocation; it does not reconstruct a guest EIP.
Changing its protection to make the stale access succeed would hide an
allocation-lifetime failure.

Both runs have a draw worker issuing self-suspends with server counts
`0->1`, `0->1`, `1->2`, `2->3`, all initially `held=2` (deferred). The black
run later gets a physical hold while the worker is in translated code.
The failure run reaches the pixel fault instead. This is direct evidence
that a self-suspending guest can return to its loop before it is stopped.
It is consistent with a repeated bitmap task racing completion and release;
it does not prove that every remaining startup error has this cause.

The open-source engine's [ThreadImpl.cpp](https://github.com/krkrz/krkrz/blob/master/utils/win32/ThreadImpl.cpp)
has the corresponding task pattern: perform the callback, decrement the
running count, self-suspend; dispatch replaces the task and resumes it, and
the caller waits for the running count to reach zero. A worker must not
perform another callback just because its physical hold is deferred.
The owner's binary was also checked locally for this sequence. No game
bytes are published and no Windows game was launched for this investigation.

## Change

`madeira-unix/0104` changes only `NtSuspendThread` in `thread_ios.c`.
After a successful suspend request it enters the existing non-alertable
`server_select(NULL, 0, SELECT_INTERRUPTIBLE, 0, NULL, NULL)` gate before
returning. This is the same select form used by `wait_suspend` without
publishing a new CPU context. The server checks `is_thread_suspended`
before its zero timeout, so it cannot complete while the caller is
logically suspended. The existing Mach holds, suspend counters and
`NtResumeThread` implementation are unchanged.

The gate applies to every successful suspend: pseudo and real handles to
self work without an extra query-access requirement. An ordinary
other-thread suspend returns through the zero timeout immediately unless
the caller is also suspended. A resume between the original request and
the select is observed from the server's count, not a new client event,
so it cannot become a lost wakeup. Failed requests skip the gate and keep
their original status/count contract. The gate is iOS-only. Self-handle
wait/resume messages are bounded to 32 pairs per process.

The app build marker is r8 with `suspend=gate-v1`. Existing memory settings,
the SteamGlass interface, the RAM economy profile and all pins are retained.

## Validation and limits

`build/test-self-suspend.py` extracts the actual native suspend and resume
functions. Its before case removes the appended iOS gate and reproduces
the defect: suspend returns with count one without any resume. The after
case passes ASan/UBSan with pseudo/real self handles, nested count two
requiring two resumes, a NULL count pointer, invalid and overflow failures,
an ordinary other-thread target, and a resume racing select entry. A
pthread worker then completes 10,000 bitmap tasks with each completed
buffer freed before the next task, preserving exactly-once execution.
Server request/response and select waiting are modeled with pthreads;
this is not a full wineserver, Mach, FEX or iOS game run.

The guarded migration checks the exact appended patch and the r7 native
archive, compiles `thread_ios.c` with the unchanged production SDK recipe,
and replaces only `thread.o`. It verifies the bytes and order of the other
34 archive members and all unrelated checkpoint outputs. All 1,615 native
checkpoint files verify. The resulting native archive SHA256 is
`a606eb427546f0771946b1db8ea544c2fd30f730a33d87a4dcdc75af9a31caff`.

The fix closes a demonstrated return-barrier defect. Successful game
startup still requires the owner's side-load run; no successful iOS play
or full repository test-suite pass is claimed.

The unsigned r8 IPA passes all 87 verifier checks, SHA256
`65337f94bbdd7b174adbda9b5255935d64e23fefc6dc5c493a4e03ef76b1c8aa`.
The packaged PE hashes, native gate string, executable build marker and
native archive record are inspected again before delivery.
