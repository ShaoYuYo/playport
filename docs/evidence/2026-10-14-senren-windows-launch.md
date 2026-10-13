# Senren Banka i386 launch on the user's iPhone

## Observed device failure

The user supplied an in-app report for Steam app 1144400 on 2026-10-14.
The latest two launches have the same failure. JIT activation and the native
session root succeed, then the i386 executable fails before its first
instruction: `[wow64-window] reservation FAILED ... status=0xc0000017`.
Wine reports Windows error 8; the app's launch result is `run_exe=-7`.

The FEX arena had already reserved 4 GiB, while the remaining high-address
hole was about 1.25 GiB. Its allocator used only about 91 MiB at failure.
The full WoW64 window independently requires 4 GiB, so this is address-space
reservation contention, not a failed JIT setup, missing game files, or proof
that the Steam encrypted-ticket warning caused the launch failure. The report
shows a 3,072 MiB physical memory limit; a virtual reservation is not itself
4 GiB of resident memory.

The uploaded logs contain private device/container data and remain outside
the repository. This record includes only the necessary diagnostic facts.

## Change

- Read the selected executable's actual PE/COFF machine before runtime startup.
  SessionRoot is x64 even when the game is i386, so its architecture cannot be
  used for this decision. The existing UI Play path remains the only entry.
- For an i386 title, reserve and retain the full 4 GiB registered Wine view
  before FEX chooses its arena. Hand it to the first i386 owner without an
  unmap/reallocation gap. Additional i386 children still require their own
  isolated windows. Keep the existing PEB/TEB/bootstrap and retirement rules.
- Try the established FEX arena sizes in remaining space, adding the existing
  consumer's accepted 1 GiB minimum as the final i386 fallback. The x64 ladder
  is unchanged. The guest window is never shrunk or shared with FEX.
- Reuse the known SHA-256-verified native checkpoint. Its only changed native
  source is `virtual_ios.c`: rebuild its `virtual.o` with the patched upstream
  compiler function, replace the one archive member, update the artifact hash,
  and save/reverify the migrated snapshot. Reject unrelated native changes.
  Wine PE, FEX, DXMT, Mesa, Steam and notices remain verified cached bytes.

## Validation and limits

- Production early-window functions compile and pass a constrained 5.25 GiB
  VM model, one-owner consumption, repeated preparation, x64, invalid mapping
  and allocation failure cases. The actual COFF reader passes i386/x64/ARM64,
  truncated/non-PE, missing file, invalid offset and null path cases.
- Migration tests reject unrelated native inputs and verify the refreshed
  archive record leaves other records unchanged. Existing checkpoint tamper
  checks, sanitizer, Chinese resources, font and SDK-header tests pass.
- Native patch series applies to the pinned Madeira tree; patch/name/secret
  gates and workflow YAML/shell syntax pass. Cloud native compilation, final
  app linking, `verify-ipa` and artifact upload are still required.
- No iPhone is attached here. The new reservation strategy needs another
  real launch on the user's device. Success compiling the IPA does not prove
  Senren Banka reaches its first frame or renders Chinese correctly.

## Previous build completion

Run [38460928733](https://github.com/ShaoYuYo/StikDebug-Modified/actions/runs/38460928733)
on source `750a37f124ab08ea2f2673d0553184fae6810aae` completed all jobs,
`verify-ipa` 85 passed / 0 failed, and uploaded a nonempty unsigned IPA.
IPA SHA-256: `3274b88fb2e32ab56b1f64afb2318428d30184d986af4350ab6694e808de76cb`.
The device report establishes why build/distribution verification alone was
not evidence that this 32-bit game could launch.
