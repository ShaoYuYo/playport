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

## Run 24: corrected native object and verified IPA

Run [38485465819](https://github.com/ShaoYuYo/StikDebug-Modified/actions/runs/38485465819)
on source `7bc174df31f1c15953377a526ceed55257e2ffb7` and workflow
`0307cf814c7031027ac0cbb26bd85a45ce135af4` completed all three jobs.
The restored 1,614-file snapshot passed SHA-256 verification. The cloud
compiled the actual patched `virtual_ios.c`, replaced only `virtual.o` in
`libntdll_unix.a`, and saved/reverified the migrated native checkpoint.
All other native outputs were retained; the heavy stages were skipped.

The app compiled and `verify-ipa` passed **85 checks, zero failures**, including
all resources, Chinese strings, Wine i386/WoW64, Steam, DXMT, signatures and
notices. IPA size: **673,342,641 bytes**. IPA SHA-256:
`d24e80f55f3f0ee36611319db1266425d5b6e92657584a3cecb773855e497105`.
The nonexpired downloadable artifact is
[PlayPort-unsigned-IPA](https://github.com/ShaoYuYo/StikDebug-Modified/actions/runs/38485465819/artifacts/11860741302).
Its outer ZIP is 673,342,925 bytes.

The companion build-evidence artifact was downloaded and independently checked
against SHA-256 `3dd95a88bde3869b4cd31ff0c221b4e4bca58865512739eaab7b3b9997ffe5dd`.
Its verification log and source/series provenance match this run. The exact
generated `app/artifacts.tsv` and Wine PE records are committed with this
evidence. This follow-up changes only generated records and documentation;
the downloadable IPA's compiled source remains the SHA above.

**Device validation remains open:** install the new IPA over the existing app,
preserving its container, then launch Senren Banka again. The expected new
diagnostics are a successful `title pre-reservation`, an owned 4 GiB WoW64
window and a FEX arena selected from the remaining space. Only the phone can
establish whether the game proceeds to its first frame and Chinese rendering.


## Afternoon device report: WoW64 FEX allocator handoff

The owner's `Playport-report-app-1144400-20261014-164846.zip` includes two
new launches. The morning reservation repair worked: the selected machine is
i386, the native host owns the complete 4 GiB guest window, and FEX reserves a
separate 1 GiB arena. The game maps at guest address `0x400000` and the session
launch returns success. Nevertheless WoW64 FEX's first allocator initialization
probes the old hardcoded arena bands, reports `NO BAND`, and faults writing
through a null allocation. This is a second defect after the repaired window
allocation, not evidence of a missing game or failed Steam download.

The native arena channel reaches ARM64EC FEX but the WoW64 DLL did not export
its corresponding DATA slots. `InitCRTProcess()` initializes rpmalloc before
normal FEX startup, so handing the values over later is too late. Patch 0023
exports those two existing globals. Native patch 0100 validates their mapped
PE DATA locations and writes the host's already-reserved arena into the backing
image before the parent or child JIT copy. The consumer's end is inclusive;
the native channel's exclusive end is converted with `end - 1`. Later backing
and IAT synchronization retains the same pair. No early Win32/CRT/environment
call is added. Malformed exports or a partial protection failure reject module
loading before either DATA value is written.

The checkpoint migration now accepts only this precise native patch append,
WoW64 export append and matching build/verifier changes. It verifies run 24's
snapshot, rebuilds only `virtual.o` and WoW64 FEX, updates only their artifact
records and saves/reverifies a new snapshot. ARM64EC FEX, Wine PE, DXMT, Mesa,
Steam and notices remain cached. The actual newly linked WoW64 DLL is mapped
on the build host and validated with the same bounded native DATA parser before
staging; IPA verification additionally requires both exports.

The host regression test compiles the production parser and handoff wrapper
with undefined-behavior checks, covers the reported 1 GiB range and inclusive
end, backing-to-JIT copy, invalid/forwarded/aliased/executable/out-of-bounds
exports, truncated headers and partial protection failure. Manifest tests
ensure only the two changed native outputs are recorded. This source repair
still requires cloud native compilation, IPA verification and another phone
launch; no first frame or Chinese game rendering is claimed here.


## Run 25: pre-CRT handoff build completed

Run [38540569334](https://github.com/ShaoYuYo/StikDebug-Modified/actions/runs/38540569334)
on source `1c206116709728c7dc4fa00a145e8c05b7772781` and workflow
`200a1c59a91ebd702cedd94844cc98e2e49151d4` completed all three jobs successfully
on 2026-10-14 at 17:52 Taiwan time. The native migration compiled the actual
patched Wine object and WoW64 FEX DLL. The production parser verified the new
DATA RVAs `0x3d14f0` and `0x3d14f8` before staging. Its 1,614-file checkpoint
was saved and reverified under the new native key ending
`ea40aa39a41a054f38899634b21b9ba6432a1059881cdb6a508c70b88a353f9f`.
The full Wine/DXMT/Mesa rebuild stages were skipped because their cached
outputs had passed SHA-256 verification.

Cloud Swift tests ran 18 SteamStub/depot tests with zero failures and the
existing real-sample test skipped because no `STEAMSTUB_SAMPLE` fixture was
provided; both GameLanguage tests and all 17 focused Python tests passed.
The real production SwiftUI/Liquid Glass IPA preflight passed as well.
FEX's upstream host-only SVE probe printed a nonfatal Python error on the x86
runner's missing ARM CPU feature field. CMake treats its nonzero result as the
conservative SVE-disabled `cortex-a78` fallback; actual compilation, DLL
validation and final verification all completed. No validation gate was removed.

Final `verify-ipa`: **86 checks passed, zero failed**. The new check confirms
both WoW64 FEX arena DATA channels are present in the bundled `xtajit.dll`.
The verified unsigned IPA is **673,342,689 bytes**; its SHA-256 is
`c0c3db30a494896dbb5c42fe77d6d85e3da1908999ef660e75cf571aedbcd8fa`.
[PlayPort-unsigned-IPA](https://github.com/ShaoYuYo/StikDebug-Modified/actions/runs/38540569334/artifacts/11883499647)
is nonexpired; its outer ZIP is **673,342,973 bytes**, digest
`936fc23b78d414e64dffd55fe7a625a926d8007ce69278be12755c30b2f0e40e`.

The 226,838-byte companion build-evidence ZIP was downloaded and independently
verified against SHA-256
`120500d18c3022f73f9ba3fed5969a115fbdbe6b3ed90fad29ffa6f4c81212be`.
Its `provenance.txt` names the exact source SHA above and the updated series;
its `SHA256SUMS` agrees with the completed job log. The generated manifest
changes only the Wine archive and WoW64 FEX hashes; all other artifact rows
and Wine PE records remain byte-identical. These exact records accompany this
evidence-only follow-up; the downloadable IPA still comes from source `1c206116`.

**Phone validation is still open.** Upgrade over the existing app to preserve
the Wine prefix, Steam session and installed game. The next fresh Senren Banka
launch should show `[wow64-fex-arena] pre-CRT handoff` before FEX's allocator
initializes. Check the latest launch block rather than historical errors in an
appended report. A first frame and correct Chinese rendering must still be
established on the owner's iPhone; neither is claimed from build success.


## 18:08 device report: handoff confirmed, encrypted-wrapper execution fault

The owner supplied `Playport-report-app-1144400-20261014-180806.zip` after
installing run 25. Its latest launch (18:07 Taiwan time) shows the successful
pre-CRT arena handoff with the expected exclusive-to-inclusive conversion.
FEX initializes, decodes the i386 Wine loader, loads the game's dependencies,
registers desktop/message classes and begins executing the game wrapper.
This establishes that the two preceding memory-reservation and allocator-channel
repairs took effect on the actual phone.

The new failure is a read access violation, `c0000005`, after 851 ms. FEX
reconstructs guest EIP `0x8db75f`; that is within the main executable's mapped
`.bind` code interval (`0x8da000` through `0x903900`). Its native emitted
instruction reads guest address `0x8b3504a9` at host `0x70c33504a9`, precisely
window base `0x7038000000` plus the zero-extended guest address. That address
has no committed readable Wine page. The guest stack remains a plausible
`0x110f694`; the native handler's zero Frame.RIP/RSP dump refers to its ARM64EC
state probe, while the WoW64 handler subsequently reconstructs the real guest
context. Those diagnostic zeros alone are not evidence of missing stack setup.
The arena used 197 MiB with 827 MiB free, without refused allocations; the JIT
pool had 454 MiB room. This is not evidence of arena exhaustion.

The Play UI's executable check reports `SteamStub 3.1 x86 with encrypted code
is not supported yet`. The current implementation deliberately leaves such
images intact and supports only unencrypted 3.1 wrappers. There are also earlier
rpmalloc available-list guard reports (`bad=0x20`, head with non-null previous
link); their relationship to this guest instruction is not established. Neither
the unsupported-wrapper label nor the allocator guard is sufficient by itself
to prove the ultimate cause. Do not disable protection, map the invalid address,
reset heap lists blindly, or treat a failed encrypted-wrapper launch as a
successful game launch.

Next implementation requires validating the real x86 wrapper layout/decryption
contract and matching the faulting guest instruction before changing executable
bytes. The public third-party reference-code clone was rejected by automatic
approval review as outside the two-repository operation scope. It was stopped
and not retried through another route. No speculative runtime or wrapper change
was made from this report, and no unchanged IPA rebuild was submitted. Source
and private workflow still preserve the successful run 25 native checkpoint.
Only necessary nonprivate diagnostic facts are recorded; the uploaded report
remains outside version control.


## Encrypted x86 wrapper preparation

The owner subsequently authorized downloading other reference code, with edits
still restricted to PlayPort and its build workflow and any new fork private.
The format reference was read at public upstream commit
`cd770bf9749d3e4f438d23ac643917ad1a804257`; its x86 3.1 header declarations
confirm the same 0xF0 header and offsets already used by PlayPort. Relevant
format facts are the 32-byte key at 0x58, encrypted 16-byte IV at 0x78,
stolen first cipher block at 0x88 and declared code RVA/length at 0x48/0x50.
The reference was not vendored or modified, and no new fork was needed.
Reference: [x86 header and code-section handling](https://github.com/atom0s/Steamless/tree/cd770bf9749d3e4f438d23ac643917ad1a804257/Steamless.Unpacker.Variant31.x86).

PlayPort's existing portable AES implementation gains unpadded CBC; depot
chunks and filenames retain their original PKCS#7 behavior. For validated x86
3.1 images, prepare the first ciphertext block plus the declared raw code,
decrypt the IV with AES-ECB, decrypt all code blocks with CBC without padding
removal, and write exactly the declared plaintext length. Restore the original
entry point after decryption. This uses PlayPort's own AES and PE handling;
no third-party implementation is incorporated. Encrypted x64 and older
wrapper variants stay outside this change.

Validate executable section identity, raw/file bounds, aligned positive length,
a 128 MiB preparation limit, original entry point, nonoverlapping raw ranges
and TLS callbacks before producing a modified copy. A callback into the wrapper
is rejected because it would execute before the restored entry; existing
original TLS data is preserved. Keep the owned executable as `.orig`, retain
Steam verify/repair's original hash, and make removal idempotent and reversible.
Malformed inputs must not alter either the original or an existing destination.
Launch logs record only architecture, flags, app ID and original entry point,
without keys or executable bytes.

Regression fixtures are wholly synthetic, independently encrypted with OpenSSL
AES-256-CBC/ECB without padding. They exercise stolen-block restoration, a
padding-shaped last code block, original/depot verification, repeated preparation,
restore, kept wrappers/overlays, malformed bounds/sections, source/destination
aliasing, truncated PE headers and wrapper/original TLS callbacks. NIST
SP 800-38A F.2.5 separately checks unpadded CBC. Swift tests and a new verified
IPA still need to complete; real encrypted-game launch remains a phone check.
The run 25 native cache identity is unchanged by these app-only source changes.


Run 26's Swift 6.4 CI compiled the implementation and ran 43 selected tests.
All 18 SteamStub tests (one existing real-sample skip), all 14 codec tests and
all six depot tests passed. The only failure was a transcription error in the
new NIST expected plaintext, not an AES mismatch: OpenSSL independently agrees
with the computed four blocks. The literal is corrected as four explicit
16-byte strings. An additional UINT64_MAX header case requires checking raw
length before computing end addresses; this is fixed before accepting the
source. The IPA job was skipped by the failed-test gate. No verifier was disabled
and the source has not yet been promoted to main.
