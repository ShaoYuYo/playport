# Memory economy and the ARM64EC arena handoff

The owner supplied the 18:31:10 report for Steam app 1144400 from r5 and
requested lower RAM consumption and a hidden Windows comparison. No phone
connection or control was used. Private reports, game data, binaries, captures,
save directories and full diagnostic outputs stay outside public source.

## What the supplied report establishes

The existing menu bridge succeeds repeatedly. The first attempt later fills
its **virtual address arena**, not the iOS RAM limit:

- App limit 3072 MiB; last recorded footprint 1124 MiB, including 67 MiB of
  compressed pages. No memory-safety refusal was recorded; configured margin
  was 1024 MiB. That preference is preserved.
- A 512 MiB fixed JIT pool; recorded head 26 MiB, tail 33 MiB, no exhaustion.
  Every blessed pool page is charged, so reducing this allocation avoids
  charging 256 MiB from activation. This is not a measurement of the new
  candidate's total footprint.
- FEX arena reserved 1024 MiB; first refused mapping reports 998 MiB of views,
  largest gap 15 MiB, 39 allocator spans, 14 call-return stacks and 14 L1
  caches. A further 16 MiB-aligned allocator span cannot fit. ThreadState
  creation fails and a subsequent null access terminates the process.
  View sizes describe address occupancy and must not be added to physical RAM.

The second attempt reserves and publishes 768 MiB, but the ARM64EC root
rejects it against an old 1 GiB minimum, zeros the channel, then FEX has no
arena. The previous sub-gigabyte change covered the i386 child handoff but
missed this root validation path. Wine PE patch 0035 accepts the same 512 MiB
floor there, retains the end-exclusive to inclusive conversion, rejects
unmapped/invalid intervals by clearing both slots, and adds a below-4-GiB
base check. Native selection and the full isolated 4 GiB guest window remain.

## Changes and their limits

Decision 0069 records the opt-out title-specific pool, existing processor-count
setting and engine cache defaults. KiriKiri's own
[command-line documentation](https://krkrz.github.io/docs/kirikiriz/j/contents/CommandLine.html)
describes `-memusage=low` as limiting caches and TJS hash tables at a possible
performance cost, and `-drawthread` as the drawing worker count. The supplied
game executable also contains both option names. Explicit player arguments
and runtime keys win; game archives, configuration and saves are not changed
by this app policy.

The processor-count setting already updates Wine's shared `cpu_count`, used
by processor queries and the owner PEB; the existing WoW64 owner projection
copies it to PEB32. Limiting a worker fleet is an expected reduction in FEX
per-thread demand, not a hard thread cap or proof of a particular final count.

[Apple's memory diagnostics guidance](https://developer.apple.com/videos/play/wwdc2021/10180/)
describes OS-managed compression and evaluating footprint rather than resident
memory alone. This report already records compression (up to 181 MiB on the
second attempt). We do not compress live executable pages or evict game-owned
allocations. Host diagnostics now expose TASK_VM_INFO compressed pages in
original bytes, already included in footprint, and log every two seconds
when the UI scheduler can run. Native footprint diagnostics also remain.

## Windows measurement

The matching unwrapped executable and existing emulator DLL were started in
a private Win32 desktop, with no desktop switch or visible window. Samples
were collected every two seconds for about 60 seconds, without trimming the
working set. Original installed game files and saves were not edited. Later
attempts used isolated scratch save directories and a kill-on-close Job to
clean up only the processes created by the test.

| Test | Working set after startup | Private commitment | Recorded peak working set |
| --- | ---: | ---: | ---: |
| Existing configuration | about 247 MiB | about 233 MiB | 248.3 MiB |
| Fresh isolated save, low engine options | about 232 MiB | about 218 MiB | 241.4 MiB |

These are **startup observations**, not gameplay benchmarks or a controlled
cache A/B comparison (save settings differ). The private desktop cannot
initialize this game's Direct3D9 device caps; all attempts remain at that
prompt, including attempted software fallback. The expected native Windows
startup budget is therefore roughly 250 MiB, with about 300 MiB as a rounded
startup allowance, but there is no measured story/video/full-game peak.
Wine/FEX/Metal and JIT costs make that number unsuitable as an iOS cap.
All processes created by the tests have ended; the scratch configuration was
restored to the original hash.

## Verification

The production ARM64EC handoff validation and assignment block passes twelve
UBSan host cases: 512/768/1024 MiB and 8 GiB successful handoffs, plus invalid
size, missing endpoints, reversed intervals, misalignment and guest-space
overlap. Reinstating the old floor reproduces rejection of the small valid
arena. Thirty-one selected Swift tests pass, including title scoping,
explicit argument/configuration precedence, opt-out, JIT exhaustion reporting,
routes, launch diagnostics and safety-margin behavior.

The pinned production recipe rebuilds only ARM64EC ntdll and the checkpoint
migration retains every other artifact. New DLL SHA256:
`70b7422a07d3b45c987c29ce432507057b7c953752b52a0d155b1ce228884a39`.
The migration verifies the exact appended patch and selective build recipe;
no pins move. Existing broad tooling failures remain unresolved;
no full-suite pass or successful iOS game launch is claimed.

The unsigned r6 candidate passes all 87 IPA verifier checks, SHA256
`86d9b3497ab79d7ec0aa17ee9e9bb5fa2f2ee10ac71160e8b7be59e73273f674`.
Its packaged ARM64EC ntdll, both unchanged CPUID modules and unchanged menu
bridge hashes were checked against the staged records, along with the r6
identity and new memory diagnostic strings in the executable. The production
CPUID ASan regression and menu thunk UBSan regression pass. The menu test now
finds the conversion patch's parent explicitly, instead of assuming HEAD's
parent is the pre-fix source; the later ntdll patch exposed that test-fixture
assumption. These checks do not establish a successful iOS first frame.
