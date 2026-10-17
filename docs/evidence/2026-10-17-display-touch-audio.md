# Device display settings, touch mappings and audio preservation

The owner reports that SteamGlass r12 successfully starts Senren Banka
(Steam app 1144400). That is an owner report, not a workstation-controlled
phone run. Its native runtime remains unchanged in r13.

## Display

The app resolves unset global display settings to native panel pixels and
the panel's maximum refresh rate. Explicit global and game overrides remain
in place. Clearing an override follows the panel again, including during
the current app session. The portable launch resolver retains its legacy
720p/60 fallback for callers without panel information.

The FPS picker now includes the panel's own rate (60 or 120, for example),
which the previous strict-less-than filter omitted. An in-game picker
updates both the frame pacer and the retained display link immediately;
positive limits are bounded by the panel rate. The game's page also offers
a native-resolution/panel-rate preset. Resolution changes apply on the next
launch; arbitrary games cannot be forced to recreate their swap chain safely.
The game menu shows the configured guest screen and actual last-presented
texture size separately. Aspect fitting remains enabled.

These are output modes and limits, not measured FPS improvements or new
artwork detail. A game's own frame cap, render resolution, static assets,
CPU/GPU cost and system refresh decisions still apply. Native resolution can
increase RAM and GPU cost; lower resolution remains available.

## Touch input

A small in-game toolbar opens the existing paused-game menu without a
controller. The mapping editor adds keyboard or mouse-button controls,
supports held buttons, labels, dragging and opacity, and persists layouts
by catalogue title ID in UserDefaults. Controls are opt-in and hideable;
ordinary touches outside them continue to reach the game. Mouse mappings
click at the current guest pointer position. Existing physical controllers
continue through XInput; controller-button remapping is not added here.

Multiple screen buttons and hardware keys share input ownership. First-down
and last-up edges reach the guest; cancelling/removing a touch control sends
its up edge. Focus loss and opening the menu clear ownership and release
tracked keys and mouse buttons. The editor uses stable IDs when deleting
or updating controls. Menu rows scroll to the controller's selected item.

## Audio

The owner requests original quality without compression and has not yet
checked whether the current build produces sound. The audio driver, game
audio assets, mix format and decoder settings remain unchanged. The existing
driver exposes 48 kHz stereo 32-bit float PCM mixing and feeds linear PCM
to RemoteIO, with the driver's existing conversion for client formats.
No lossy encoder or sample-rate reduction was introduced. Hardware format
conversion and a Bluetooth route's codec remain system/device decisions;
bit-perfect output is not asserted.

New bounded event logs report output port types (not personal device names),
sample rate, channel count, volume, I/O duration and session resume. The menu
shows output format and volume and explains its intentional audio pause.

References: Apple's [frame-rate range documentation](https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange)
and [audio preference guidance](https://developer.apple.com/library/archive/qa/qa1631/_index.html).
Neither a refresh request nor an audio session setting proves actual
presentation cadence or audible output.

## Validation and limits

- HostIOKit: all 43 tests pass, including input ownership, focus/menu release,
  persistent layout normalization, HID coverage, display geometry and pacing.
- PlayportKit: 16 targeted launch-settings, panel-default and quick-menu tests
  pass, including explicit overrides and rates on 60/90/120 Hz panels.
- Existing WoW64 audio stream and VM tests pass under ASan/UBSan, reconstructing
  the patched native audio source from the build checkout's upstream objects.
  They cover PE32 pointer translation, render/ring transfer, silence flags,
  growth/OOM, ownership, retirement and release. RemoteIO is mocked: this does
  not test hardware sound or the actual game's audio content.
- Release IPA compiles and passes all 87 package checks. Native checkpoint
  verification covers 1,615 runtime outputs. Native DLLs retain r12 hashes.
- Name and secret gates and whitespace checks pass. No full-suite claim.

The owner will side-load the IPA. No phone connection, screenshots, audible
output test, visual UI test or comparative game FPS measurement was performed.

IPA SHA256: `0001a0e98fbbbc6ab52544803766bbf7b07f6cdcc2abf76d3b663e97576ce55d`
