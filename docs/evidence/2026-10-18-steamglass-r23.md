# SteamGlass r23: bounded continuous updates and full-window rendering

IPA SHA256: `f4c0a21316c28feeca678113855e9840ff2d40f172eb4af81f86b479694dcd98`

The owner reports 40--50 FPS and asks for less heat/power use, an optional RAM
banner and a game image that uses the window height. No current-run phone report
was supplied. The latest available r19 report contains a serious thermal-state
transition at a 2338x1080 output size, with both short and long drawable waits.
That does not establish the cause of the current r22 performance complaint.

## Continuous work

Previously, selecting unlimited presentation also supplied `-contfreq=0` to
this title's engine. The [engine documentation](https://krkrz.github.io/docs/kirikiriz/j/contents/CommandLine.html)
and [continuous-event implementation](https://github.com/krkrz/krkrz/blob/fd5c4baa6a2ef5978db1bd043634351f48667daf/base/win32/EventImpl.cpp)
show that zero drives continuous callbacks without sleeping. Default continuous
updates now follow the panel even when presentation is unlimited (60 Hz fallback,
240 Hz bound). Presentation selection, explicit continuous-rate arguments, script
overrides, title opt-out, normal caches and the existing worker/JIT budgets remain.
Already capped sessions using the panel rate have no continuous-rate change.

The actual game's unmodified executable was tested on a private Windows desktop,
using an isolated synthetic continuous handler and save/log directory. No game
window was shown and no owner save was loaded or written. Each handler ran for
approximately four seconds:

| Continuous rate | Callbacks | Elapsed ms | Whole-process CPU seconds |
| --- | ---: | ---: | ---: |
| 0 | 18,535,726 | 4,000 | 4.15625 |
| 60 | 241 | 4,005 | 0.265625 |
| 120 | 480 | 4,000 | 0.1875 |

These are engine callback/cumulative CPU measurements, including startup costs;
they are not gameplay FPS, translated iPhone CPU measurements, temperature or
battery savings. The ordering of the two small timed CPU totals is not evidence
that 120 Hz uses less energy than 60 Hz. The app also stops retaining an empty
CADisplayLink when the requested refresh is at most 60 Hz. The >60 Hz ProMotion
request remains available. Neither change fabricates or repeats game frames.

The existing five-second health report now includes cumulative process CPU deltas,
thermal and Low Power Mode state, and time between drawable return and the next
request. That last interval includes game work, submission and other waits; it is
not labelled pure CPU time. CPU percentages sum all process threads, so 100% is
one occupied core. The first sample/reset reports unknown rather than a false
zero. There is no new timer, per-frame CPU query, GPU readback or battery monitor.

## Display and reminders

Rendering now defaults to aspect-fitting inside the full window, independently
of the safe rectangle used for control hit targets. It removes the extra top and
home-indicator margins around the render view, preserves aspect and camera-safe
controls, and does not increase the selected render budget. Intrinsic game
letterboxing can remain. The owner can switch the full-window setting immediately
in the game display menu or launcher graphics settings.

The RAM-banner preference is available in both locations, defaults on and updates
without restarting. Hiding the banner does not disable monitoring, change the
configured headroom, remove allocation refusals or suppress diagnostic failures.
The existing 720p/60 and 720p/30 presets now clearly describe balance/power use and
when their resolution/FPS changes apply; no stored resolution is silently changed.

## Validation and limits

Host tests cover panel/fallback/explicit/unlimited options, producer versus
drawable/limiter timing, CPU reset/multicore accounting and full-window geometry
with camera-safe controls and pointer centres on both landscape rotations.
54 HostIOKit and 25 selected PlayportKit tests pass.
Release compilation and 88 IPA checks pass. The packaged app is
independently checked for production-source equality, both Files flags, the new
preference/diagnostic markers and unchanged native runtime/audio/DX12 hashes.
The 1615-file native checkpoint remains unchanged.

No phone connection, public IPA upload, usage reset or shutdown was performed.
Actual iPhone sustained FPS, energy/temperature improvement, menu appearance and
live preference changes remain unverified. In particular, this candidate does
not establish that all 40--50 FPS gameplay now holds 60 FPS.
