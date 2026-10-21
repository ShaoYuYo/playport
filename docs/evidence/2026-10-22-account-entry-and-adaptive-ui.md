# Apple verification entry and adaptive launcher layout

The owner reports that Apple sign-in reaches verification but the app has no
usable code entry. The old form placed installation details before conditional
entry, never focused or scrolled to it, and mounted entry only after the code
notification HTTP request returned. There is no device capture proving which
of these conditions occurred on the owner's phone.

Show the challenge before delivery begins. Each sign-in owns a separate
single-use verification gate that accepts an early code, waits without blocking
the main actor, rejects malformed or duplicate submissions and releases its
continuation on cancellation. No code, password or response body is logged or
persisted. A closed generation cannot display an old request in a later login.
No automatic resend or credential retry is added. Apple protocol, endpoint
identity and capability semantics otherwise remain the r35 behavior.

The account page is now a full-screen, keyboard-aware scroll surface, allowing
portrait entry/AutoFill and restoring landscape on dismissal. Its
active step is first; six-digit entry focuses automatically, supports paste,
full-width decimal digits and one-time-code AutoFill. Both the card and keyboard
toolbar offer submission. Installation details move into a disclosure section.
Waiting for a person is distinct from a busy network progress indicator.

Launcher navigation keeps the single top-left drawer. Settings switch between
side navigation and a horizontal section strip with safe content width, show a
section heading and reveal controller-focused sections. Shared rows wrap their
labels/descriptions/values and use larger touch targets with separate surfaces.
Home covers use available height, Library columns use safe width, and game
pages scroll instead of relying on a fixed 76-point top gap. Game actions scroll
horizontally and reveal controller focus; facts stack on narrower screens.
Options panels are bounded by their viewport. Steam sign-in cards reflow and
scroll; setup steps and download-side information stay reachable by scrolling.
Flat content cards limit glass to navigation and controls; existing reduced
motion/transparency behavior and retained root-page state remain in place.

Checks use production verification and layout logic, plus the existing host
regression suites and unsigned release compilation. No phone, private Apple
account, Steam/cloud writes, game/save modifications, Windows reboot/shutdown,
public IPA hosting or D-drive synchronization is used. Actual keyboard/AutoFill,
visual layout and real authentication still require owner-side testing.

## Built artifact

IPA SHA256: `c1410f6846bb2fae37a4ed02b14e44219106042633a4fbf5245cbf1a8462bf77`.

54 Swift cases pass: 27 storage/memory/JIT/layout, 4 display and 23 account
(including 9 verification lifecycle cases). All 13 retained native VA cases
and 88 IPA checks pass. All 228 production sources and 19
transferred inputs match the build. Optimized host flags remain present.
Native checkpoint and artifact records equal r35. No device visual/keyboard
or real account verification was performed. No D-drive synchronization.
