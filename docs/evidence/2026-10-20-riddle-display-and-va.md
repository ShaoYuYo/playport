# Riddle Joker: drawable acquisition and virtual address ceiling

Report: app 1277930, 2026-10-20 19:53:02, r32. Private raw report is not committed.

The current log contains multiple launch segments. JIT pool acquisition succeeds
and self-check passes. One segment calls the old first-frame callback at about
38.94 seconds, but later render-health samples still have frames=0, fps=0,
failed=5996 then 10647, pixels=none. This is acquisition failure, not evidence
that an image reached the display. The earlier attempt records a user Quit;
that is not a newly established access violation.

Repeated high-VA searches each attempt 786306 mappings. The hint walk selects
0x8000000000 although TASK_VM_INFO.max_address is 0x7180000000. Patch 0111
honors a valid kernel bound in either direction, retaining the hint fallback
when the query fails or returns less than 4 GiB. This avoids walking an
impossible band for ordinary stacks and mappings. It does not raise a system
limit or change any native component pin.

Peak reported footprint is about 1780 MiB with a 3072 MiB process limit. Arena
and pool counters do not show allocation refusals. This report does not prove
an out-of-memory termination. More memory rights therefore are not presented
as the proven Riddle Joker fix.

The Swift surface now supplies a Metal device and waits for finite, positive
view/drawable dimensions in a window before registering it. Nil acquisitions
use bounded backoff and sparse diagnostic lines. The first drawable request uncovers the launch overlay (without claiming
a frame), preventing a cover/acquisition dependency. A non-nil drawable is
recorded separately; only Metal's presented handler records the actual first
frame. No extra rendering loop fabricates FPS or visible frames.

## Verification contract

- Compile the production VA-limit function with deterministic OS stubs: lower
  kernel bound, higher bound, zero/tiny invalid values, failed query.
- Test production surface readiness, bounded backoff and failed-frame counters.
- Compile the release app and verify its IPA and bundled licence selection.
- Device/game launch remains owner verification; no phone was contacted.

## Limits and next evidence

The fix addresses measured invalid mapping work and invalid surface readiness.
It does not establish that all historical script/loader failures are solved.
A new report should show va-limit-v2, drawable-recovery-v1, first usable drawable,
and a genuine first frame with positive render-health frame counts. If drawable
acquisition still fails, the diagnostics include device, pixel format, size,
visibility and opacity to distinguish surface failures from guest failures.

The retained native checkpoint contains finished archives but omits installed
GnuTLS build headers. The recovery build restores only public headers from the
unchanged checksum-verified 3.8.9 source tarball. Its generated header follows
that release's configure substitutions, with an actual iOS SDK iovec compile
probe. Rebuilding uses the ordinary unix-gaps gnutls-config stage; the existing
GnuTLS static archives are retained and checked by the runtime checkpoint.
All ntdll compilation units must succeed, and secur32/crypt32 function-table
symbols must be present before a new IPA is accepted.

## Built artifact

IPA SHA256: `a25eab1f4a894811949e5db0808c4b479c972beaf5188309c548b91fcd3bec4c`.

36 Swift tests (21 existing memory/storage/JIT regressions, 3 display recovery,
12 account/SRP/capability cases), 5 compiled production VA-function cases and
88 IPA checks pass. The notice selection contains the exact
pinned dependency licences. Only libntdll_unix.a changes among native artifact
records; retained FEX, Wine PE and Direct3D runtime DLLs match r32.

The build uses the preserved headless Linux overlay. No phone was contacted,
no game was visibly launched, and no live account/cloud/save writes were made.
Apple account login and Riddle Joker's actual device presentation still require
owner testing; successful compilation is not a claim of successful device play.
