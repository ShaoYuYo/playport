# SteamGlass r25: launch waits, edge menu and idle overlay work

IPA SHA256: `8e4c77f223c5bc2d8235683c64bff48f431fad99d63730a698c2e8400269a163`

The owner requests faster startup, lower power use, and a settings button in the
side black area which can hide until touched. There is no newer phone report or
owner permission to connect/control the phone. This candidate changes app-side
work and preserves the native runtime and save protections.

## Startup

Encrypted-app-ticket and ownership/broker preparation previously ran serially.
They now use structured concurrent requests with their original individual
deadlines and fallback behavior. CM service calls already route replies by job
ID. Both preparations are awaited before runtime launch/suspension; stale-ticket
cleanup and final emulator configuration remain ordered. Setup and cloud save
verification still precede the launch. A sparse `launch-prep-v1` log separates
setup/cloud time from ticket preparation for subsequent owner reports.

The host concurrency test blocks both backend requests at a barrier and verifies
that both enter before either can finish. Separate tests cover independent
failure fallbacks and the encrypted request's deadline while the broker is ready.
This proves overlap, not a measured phone startup-time reduction; network and JIT
activation can still dominate startup.

## Edge menu

The settings target is 44 points at the outer safe edge, vertically centred away
from rounded corners. Geometry chooses the wider camera-safe side letterbox.
Senren uses its known 1280x720 scene aspect inside the monitor-sized surface;
there is no GPU pixel readback. Other games use the configured display aspect.
When no side black area exists, the target remains at the less obstructed safe
edge. No game resize, stretching or new black strip is introduced.

Auto-hide defaults on and is configurable in launcher Graphics settings and
the in-game display menu. After approximately 2.5 seconds the glass button fades
out and its visual subtree becomes hidden. The transparent edge hit target
remains: first finger contact reveals the button without forwarding a click to
the game or opening the menu; a subsequent tap opens it. Mouse/pointer hover can
also reveal it. This does not claim iPhone finger proximity sensing before
contact. Editing controls and VoiceOver keep the button visible.

A pure event-driven visibility model drives one cancellable delayed task, with
no display link, per-frame observer or repeating timer. Repeated view updates do
not reschedule a deadline or reveal the hidden button. Held/hovered targets do
not disappear, cancellation cannot open the menu, and returning from an inactive
state begins a new visible interval. Tests exercise those cases and both camera
orientations with 720p and monitor-aspect game surfaces.

## Power-related work

Ordinary memory diagnostics now write every ten seconds instead of every two,
reducing those periodic writes from 30 to 6 per minute (80%, not an energy
percentage). Safety monitoring remains at one second, allocation refusal logs
remain immediate, and the five-second frame/CPU/thermal report remains intact.
Mapped controls skip repeated title and glass-tint updates when their values
did not change. Hidden menu glass is removed from the visible view subtree.
The event-driven approach follows Apple's [timer energy guidance](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/MinimizeTimerUse.html).

## Validation and limits

60 HostIOKit and 73 selected SteamClient host
tests pass. The latter include all r24 cloud/save regression cases, Steam API
placement, ticket preparation and library service behavior. Release compilation
and 88 IPA checks pass. The package is independently checked
for its new revision, edge/launch/preference markers, production-source copy
equality, Files flags and unchanged native/audio/Metal/DX12 hashes. The 1615-file
native checkpoint is unchanged.

No phone connection, public IPA upload, live cloud mutation, usage reset or
shutdown occurs. Actual phone startup time, thermal/battery improvement, touch
behavior and visible button placement remain unverified until the owner tests
the sideload. No FPS, temperature or battery-life improvement is claimed from
host tests alone.
