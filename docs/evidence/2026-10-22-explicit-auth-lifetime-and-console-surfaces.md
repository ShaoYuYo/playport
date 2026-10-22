# Explicit Apple authentication lifetime and console surfaces

The owner reports continued game stutter and Apple sign-in ending when the
system's trusted-device notification appears. No r35/r36 device report is
available: the newest local report is r33 and cannot measure these revisions.

The account view unconditionally called model.close() on disappearance,
cancelling its task and continuation. System notifications, temporary inactivity
and presentation rebuilding must not be interpreted as an explicit user cancel.
Session lifetime, orientation and typed verification entry now belong to the
model/presentation owner. The view only clears its password on disappearance.
The busy presentation rejects implicit dismissal, and the explicit Close button
still cancels immediately. Returning active refocuses entry without resetting it.
No credential or verification value is logged or persisted.

Compare current SideStore authentication behavior with its SideSign source at:
https://github.com/SideStore/SideSign/blob/752d1ef602aa792a432ffa1e71646dc1ecf7363c/Sources/DeveloperPortal/Authentication.swift
It distinguishes an already pushed verification challenge, including hsc=409,
from a new delivery request, and only a caller cancel response is user cancellation.
The local client now accepts equivalent trusted-device/root/status envelopes and
does not send another notification for an already-pushed code. Verified SRP server
proof remains mandatory; challenge metadata never grants a developer session.
Nested validation rejection codes survive, and an unexpected cancelled network
request is a transport failure rather than evidence of a person cancelling.
Unknown account repair/unsupported channels still stop safely. This is a scoped
comparison, not complete integration of that project's authentication stack.

The release previously set MTL_HUD_ENABLED=1 even when the visible HUD was off.
It now avoids enabling developer Metal HUD instrumentation in ordinary releases.
The product performance overlay uses actual presented-frame health reports and
the memory reading already collected every five seconds: no new display link,
GPU readback, per-frame UI publication or polling timer. It labels averaged FPS
and does not claim to preserve the developer HUD's GPU timing counters. Explicit
inherited profiling environment and development-build diagnostics are preserved.
Reduced measurement overhead is expected; no measured FPS or thermal gain is
claimed and guest animation/submission cost is not proven solved.

UI uses graphite surfaces, Steam-like blue emphasis, pale focus borders and
semantic warning/error colors. Shared tinted glass dialogs/drawers, navigation,
keyboard, save choice, launch/failure panels, memory banner, settings sheets,
game controls, opening accent and product performance overlay use the same
palette. Home gives the active title a larger heading over the cover shelf.
Save choices/actions and picker footers stay in bounded scrollable layouts.
The RAM banner reserves safe-area space for the HUD and gear and leaves the
paused menu clear.
The ambient background no longer adds a full-screen 30-point blur pass. Game
art, the game's pixels, system web authentication and screen-dimming mode keep
their intended semantics. Glass backgrounds are used while game menus pause the
guest; the compact gameplay HUD updates only from existing health samples.

No phone, live Apple account, portal write, Steam/cloud/save modification,
D-drive synchronization, public IPA hosting or Windows reboot/shutdown is used.
Actual alert/keyboard behavior, visual sign-off, Apple account success and current
game performance remain owner-side verification. Source and host regression checks
cannot substitute for those observations.

## Built artifact

IPA SHA256: `7da12cedc3c6f266462e401414856021e99269224259ff82da7a3564a78a5006`.

60 Swift cases pass: 27 storage/memory/JIT/layout, 4 display and 29 account.
The account suite adds 6 challenge-envelope/validation cases. All 13 retained
native VA cases and 88 IPA checks pass. All 230 production source
hashes and every transferred input match. Optimized host flags remain present;
native checkpoint/artifact records equal r36. Alert/keyboard/visual behavior,
real Apple sign-in and device game performance are not verified.
