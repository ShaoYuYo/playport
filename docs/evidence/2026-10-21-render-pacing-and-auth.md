# Dynamic-scene performance and Apple client rejection

Owner observations: Riddle Joker remains slow even on a still screen; other
titles approach 60 on static scenes but drop into the twenties with animation.
No post-r34 device report is available. The older Senren report contains
35–58 FPS samples, drawable waits averaging 7–15 ms, zero limiter waits, and
producer/request stalls up to several hundred milliseconds. These do not prove
that the GPU itself is overloaded: drawable waits include display backpressure,
and producer gaps include guest logic, translation, submission and other waits.

The pinned DXVK D3D9 swapchain derives a refresh-rate limiter from sync interval,
then waits for frame latency. The host also paces CAMetalLayer acquisition, and
the measured KiriKiri profile bounds continuous callbacks. r35 supplies D3D9
presentInterval=0 and maxFrameRate=-1 for that profile on Vulkan, leaving host
pacing and physical iOS scanout. This is a targeted double-pacing mitigation,
not proof that all animation cost has been found. Explicit graphics options
follow the defaults and now apply in release too; previously that merge was
compiled out of release. Economy opt-out and unmeasured engines keep their
existing policy. Tiler mode remains disabled and no image/audio quality is cut.

xtool builds the app in debug configuration. The release app's Swift host code,
HostIOKit's iOS frame/input bookkeeping and WinIOS C/Objective-C code now opt into
-O/-O2; debug instrumentation builds keep their existing main-app settings.
The passive five-second report counts producer and drawable waits over the
16.67 ms budget separately, without synthetic frames, readbacks or a new timer.
Physical presentations remain the FPS source. No shader/JIT compiler has been
replaced, no synchronization contract inside the driver has been removed, and
no claim of stable 60 FPS follows from compilation.

The owner also reports Apple error -80045. The old GSA policy replaced only the
Xcode token while retaining the rejected Mac hardware/OS descriptor. Use the
complete compatible Windows AuthKit descriptor and matching request metadata
only for GrandSlam SRP/app-token requests and validation. Provisioning lookups,
2FA pages, anisette service and developer portal retain their own descriptors.
Structured rejection codes in HTTP error plists are preserved; HTML responses
are not interpreted as account errors. -80045 has a specific explanation rather
than suggesting that it establishes a bad password. No automatic credential
retry loop, account login or live portal writes are performed by the checks.

This is a compatibility workaround for an undocumented endpoint, not an Apple
guarantee. Current upstream reports say it may change again:
https://github.com/Dadoum/anisette-v3-server/issues/61
https://github.com/SideStore/SideStore/pull/1683

Pinned presenter source:
https://github.com/doitsujin/dxvk/blob/e5ffd0fe5e5d62e68b2831d1285b51e61bb454d8/src/d3d9/d3d9_swapchain.cpp

The UTM comparison was checked against its current architecture description:
https://blog.getutm.app/2026/introducing-triton-directx-11-driver-for-qemu/
Its driver/host forwarding reduces conversion overhead; display refresh or a
Windows desktop at 60 Hz alone does not establish this game's new-frame rate.
Current iOS preferences document a DXMT DirectX 11 host driver and distinguish
the FPS limit from frame stalls: https://docs.getutm.app/preferences/ios/
The local i386 D3D9 DLL still executes through x86 translation, which can cost
CPU time in draw-heavy scenes. Replacing it with native thunks is not part of
this change. Device frame-time/thermal measurements remain necessary to quantify
the improvement and separate remaining CPU, upload, shader and GPU costs.

## Workstation build correction after reinstall

The initial r35 build reused the former software-emulation fallback. A fresh
inspection after the owner's reinstall confirmation finds the Windows
hypervisor present. A diskless WHPX execution probe succeeds without Windows
changes. After the r35 artifact is exported, the same Linux overlay boots under
WHPX, runs Swift 6.4 and verifies the complete 1619-file native checkpoint.
The local launcher now probes WHPX for future builds, retains an explicit TCG
fallback, and refuses a second VM. The original disk remains read-only.
This improves the workstation build path; it does not measure iPhone game FPS.
No WSL installation, system restart or D-drive synchronization is performed.

## Built artifact

IPA SHA256: `48cb23f59268e66e45070575a34183e7bf0b32faf551224bb935b9ba09d493cf`.

41 Swift cases run and pass (23 storage/memory/JIT/presentation defaults,
4 display recovery/health, 14 account/SRP/policy/capability). The retained native
VA ceiling and fallback production tests pass all 13 cases. 88
IPA checks pass. All production source bytes and transferred package/test inputs
match. The resolved SwiftBuild PIF contains -O for Playport and HostIOKit and
-O2 for WinIOS. Native artifact records and checkpoint files equal r34.

No phone, visible game, private account, cloud or save writes were used.
Animation FPS, power and successful real Apple login still require owner-side
testing. No automatic D-drive synchronization is performed.
