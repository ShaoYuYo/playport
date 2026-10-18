# SteamGlass r27: restore edge settings and direct-touch mouse gestures

IPA SHA256: `c29442aec34d9bac4fa063c1a804bc50cda62c89406af8d13227398dee2935a0`

The owner reports that the in-game settings button cannot be summoned and
requests two-finger right-click and vertical wheel gestures. This package also
contains the [r26 compact prediction reservation fix](2026-10-18-steamglass-r26.md),
with those three native runtime outputs unchanged.

## Settings hierarchy

r25 constructed and configured EdgeMenuControl but omitted addSubview for it.
Its frame/visibility model could run successfully while the control never
entered UIKit's hit-test hierarchy. The constructor now adds it before mapped
controls can be inserted below it. Existing safe-edge geometry, glass styling,
fade, accessibility, auto-hide preference and reveal-only first touch remain.
This omission is a concrete source defect; the host visibility tests did not
exercise the actual UIKit hierarchy. No phone view/hit-test pass is claimed.

## Gesture arbitration

GameSurfaceView now accepts multiple direct touches and passes ordered batches
to a Foundation-only SurfaceMouseGesture model. Mouse/indirect-pointer delivery
remains with GameController, preventing duplicate physical-mouse clicks.

Single-finger taps emit left-down/up on lift without a post-lift wait. Moving
eight points starts a left drag from the original point; holding stationary
for 180 ms presses left via one cancellable deadline. This defers the initial
press sufficiently for a second finger to join without advancing the game
with an unwanted left click. A second finger joining an already-held drag
releases that hold and cannot generate a right tap.

A two-finger tap within 400 ms generates right-down/up at the centroid. Motion
of either finger cancels right-tap eligibility, including opposing movements
whose centroid stays still. Vertical motion crosses an eight-point slop before
scrolling, carries fractional movement between events and emits bounded
120-unit wheel packets, with approximately forty UIKit points per notch.
Finger-down motion pulls content down (natural touch scrolling). The Windows
packet size and sign follow [MOUSEINPUT](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-mouseinput).

Once either finger lifts, remaining touches are consumed until all lift;
they cannot become an extra left click/drag. Third or replacement fingers,
cancellation, invalid coordinates, focus loss, view detachment, menu/editing
activation and a surface-size change clear the gesture. Any existing left hold
is released through the normal input ownership/lifecycle path. Right-clicks
and wheel events are gated by foreground/menu state and use the existing
client-pointer ring. No gesture polling timer or per-frame UI work is added.
The control editor describes the gestures and edge-button reveal behavior.

## Validation and limits

73 HostIOKit tests pass, including thirteen new cases for single tap, drag,
stationary hold, simultaneous/staggered pairs, scroll directions/remainders,
finger-lift suppression, opposing movement, timeout, late second finger,
third/replacement finger, cancellation/focus reset, a delayed hold timer and bounded/invalid input.
Existing control visibility, geometry, ownership and lifecycle tests pass.
These exercise the production decision model, with UIKit mapping reviewed in
source and compiled in the release app; they do not emulate iOS touch delivery.

Release compilation and 88 IPA checks pass. The package is independently checked for the new revision and prediction marker, both FEX hashes, the ntdll archive record, unchanged other native components, source/runner equality and Files flags. The 1,615-file native checkpoint is verified after the three permitted runtime replacements.

The first package-planning attempt terminated inside the workstation's
swift-package/libdispatch before source compilation. Its private log is
retained. Retrying the unchanged source completes; this was not a phone crash
or a test of the game. No toolchain/pin upgrade is made.

No phone connection/control, visible Windows game, cloud/save mutation,
public IPA upload, reset redemption or shutdown occurs. The settings hit target,
actual two-finger feel, post-fix gameplay stability, FPS and power remain for
the owner's sideload test. No stable 60 FPS or measured energy saving is claimed.
