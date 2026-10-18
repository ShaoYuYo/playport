# SteamGlass r28: fixed top-right settings and shared pacing deadline

IPA SHA256: `ec2cef3214edf7678f4bd28cdec65b08b8d9aef365ea013c4a3598de6c6dc5ee`

The owner reports that the settings target still cannot be opened, requests
the top-right corner, reports an apparent fling when lifting a drag, and asks
for steadier 60 FPS. This candidate addresses concrete input/pacing behavior;
device delivery and game performance have not been measured for this package.

## Settings activation

The target is fixed at the safe canvas's top-right, 48 points square,
independent of the current game's resolution, texture and letterbox aspect.
UIKit's camera/corner insets remain respected. A standard glass UIButton
handles visible taps; a transparent UIButton owns the same hidden target.
Either opens with one touch-up-inside. The original pressed button stays
attached and enabled through the reveal animation, preventing cancellation
caused by replacing the control underneath the finger. Cancellation/outside
release cannot open it. Controls have no full-screen interception area.

The existing 2.5-second one-shot hide deadline, fade, VoiceOver activation,
hover and editing visibility remain event-driven. A stale hover after closing
cannot suppress the next hide deadline. Help text now describes one tap at
the top right. Sparse viewport-v4 and menu-input-v2 logs distinguish attachment,
geometry and an activation accepted/rejected by the launch/menu state.

## Drag release

A held drag releases at its last delivered move, without a lift-coordinate
motion sample. An ended-only displacement cannot start a new drag. HostIO
posts button-up without a move flag, using the same ordered Winios ring as
client-position events. The pointer-only entry's implementation is in the
[pinned Winios source](https://github.com/willfaust/Madeira/blob/8c050d0/app/Madeira/Winios/Winios.m#L1274).
The presented-content aspect is captured at gesture start and retained until
all fingers lift/cancel, avoiding coordinate changes during texture resizing.
Existing input ownership, two-finger right tap/wheel and lifecycle releases
remain in place. A game's own scrolling behavior still needs device testing.

## Presentation timing

The limiter previously slept its full delay before acquiring a Metal drawable.
It now reserves one deadline, acquires the drawable, and sleeps only the
remaining budget; drawable backpressure consumes that same interval. A failed
acquisition receives no additional limiter wait. FrameHealth records the true
post-limiter return time, keeping limiter time out of the producer interval.
The frame-pacing-v2 marker identifies the new behavior in reports.

This applies the general backpressure principle discussed in Microsoft's
[waitable swapchain guidance](https://learn.microsoft.com/en-us/windows/uwp/gaming/reduce-latency-with-dxgi-1-3-swap-chains)
to the existing Metal path. It does not implement a DXGI waitable object API.
Frame production that is itself slow can still miss 60 FPS. No phone FPS,
long-session stability or energy improvement is claimed from host tests.

## Validation

78 HostIOKit tests pass, including five added cases for disabled stale events,
lift-only displacement, held release, shared drawable/limiter deadline and
post-acquisition timing. Existing hidden/visible tap and safe-corner geometry
tests are updated to the new behavior. These exercise production models.

Release compilation and 88 IPA checks pass. Independent package validation
checks the r28 revision/menu/pacer markers, seven native component hashes,
native archive records, ZIP CRC and both Files App sharing flags. All
215 tracked production app source files were compared with the runner:
all executable source matches. One JitPool.swift difference consists only of
line comments describing the general pool budget; its non-comment lines are
identical. All fifteen changed source files match byte for byte.
The 1,615-file native checkpoint passes. The r26 FEX/Wine native binaries,
audio path and cloud protections are retained; no live saves were changed.

The normal WSL build host still reports a Hypervisor boot-loader failure after
its authorized restart. This build instead used an isolated headless Linux
guest with a separate copy-on-write layer; the original WSL disk was opened
read-only. All fifteen changed source hashes were checked before testing and
compilation. No toolchain or component pin upgrade was made.

No phone connection/control or game execution is performed. UIKit hit delivery,
actual touch feel and steady 60 FPS remain for the owner's sideload test.
