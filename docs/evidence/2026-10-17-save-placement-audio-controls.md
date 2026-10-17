# Save placement, bounded caches, audio continuity and free control placement

The owner reports fresh progress after cloud sync, a pause before game-page
transitions followed by choppy animation, and intermittent audio. They ask for
one settings control and freely positioned, individually mapped buttons, and
for research into UTM's approach. No new phone report was received during this
change. The defects below are established from code and host tests; this is not
an end-to-end diagnosis or a measured phone performance result.

## Saves

The existing cloud client uses the Steam API emulator's remote directory. The
installed game's configuration also names a native directory under AppData:
`YuzuSoft/SenrenBanka`. The engine's Steam plugin supports a separate storage
backend. A successful comparison of remote files alone therefore does not
establish what progress the game reads. The pinned emulator's
[save path selection](https://raw.githubusercontent.com/Detanup01/gbe_fork/7103add7ca6ef3ef8353279219880068f2494fc8/dll/settings_parser.cpp)
supports a per-game `local_save_path`; this title now gets the same explicit
guest save root the app's cloud mapping uses. No credential or account ID is
part of that path.

For app 1144400 only, cloud synchronization reconciles recognised native save
files with the remote directory: `data*.ksd`, `data*.bmp`, and `savecheck`.
`data_anchor.ksd`, configuration, logs and nested paths are excluded. The last
agreed content hash identifies which local backend changed. The new mirror has
its own established-version flag: an older remote-only baseline cannot silently
authorize uploading a previously unseen native save. Its first disagreement
requires a choice. Divergent changes
in both local backends become a conflict, with an explanation that the phone
choice uses the native-directory version. A settled result is placed in both
locations. Every replaced local copy is backed up with a distinct backend
suffix. The existing choice/backup behavior for Steam's losing copy remains.
Read/write/placement failure is reported and does not establish a new agreed
baseline. No timestamp heuristic or unconditional choice of progress is used.

Remote files missing locally are now restored even when a previous baseline
exists. Previously the baseline could prevent re-downloading a lost local
file. Deletion is never uploaded by this change. New logs include the number
of local save placements in addition to transfers, failures and conflicts.

These changes cover both storage backends. They do not prove which backend
the owner's current game session selected, or that their live account's latest
progress has now completed a round trip. No live Steam save was transferred
by this workstation.

## Transition load

The previous automatic `-memusage=low` tells the engine it has zero physical
memory, disables its archive segment cache and requests unused layer-cache
release. That trades RAM for repeated work during scene changes. The automatic
title profile now selects normal cache behavior with `-gclim=64` (64 MiB image
cache). The 256 MiB JIT budget, two reported guest CPUs and two drawing workers
remain. Explicit player arguments still win. The game archives, executable,
native configuration and saves are not patched for this optimization.

The engine source inspected is
[SysInitImpl.cpp](https://github.com/krkrz/krkr2/blob/master/kirikiri2/trunk/kirikiri2/src/core/base/win32/SysInitImpl.cpp).
It establishes the option semantics, not a benchmark of this game's private
engine build. The extra bounded cache may use more RAM than low mode; actual
transition/FPS improvement requires the owner run. Existing passive frame and
memory measurements remain in the report.
Read-only inspection of the installed executable also finds each of the
`-memusage`, `-gclim` and `-drawthread` UTF-16 option names once.

## Audio and the UTM comparison

UTM's [architecture](https://github.com/utmapp/UTM/blob/main/Documentation/Architecture.md)
separates its QEMU backend from host display/audio handling. Its
[audio backend](https://github.com/utmapp/spice-gtk/blob/master/src/spice-gstaudio.c)
also isolates potentially blocking audio state transitions from the main
context. This research informed the host-output review. No UTM code or full
Windows VM was added; Playport remains built on willfaust/Madeira, with its
existing native output ring, audio queue and Wine/FEX execution.

Patch 0107 fixes a concrete callback-boundary error: a different-rate stream
previously rounded consumed source frames up independently on every callback.
Source samples could be skipped, and playback depended on the device's buffer
partition. The mixer now carries the fractional source position between
callbacks. Equal-rate PCM keeps the same samples and conversion.

After an underrun, a short refill avoids immediately alternating each tiny
producer burst with silence. It targets 40 ms of source audio, with a maximum
wait of 40 ms plus at most one hardware callback quantum, so a short final clip
cannot wait indefinitely. This recovery can add a small delay after starvation;
it cannot compensate for an indefinitely stalled game/mixer. The callback still
does no allocation, locking, logging, sleeping or Wine calls. Existing ring
capacity is unchanged. Five-second timer diagnostics report cumulative missing
frames, underrun callbacks and refill callbacks. Old per-buffer sample scans
and raw sample-word dumps are removed. Game audio assets, codec and sample
rate requests are unchanged; no lossy audio encoding was added. The existing
different-rate interpolation/filter quality is not redesigned by this patch.

The migration compiles only `audio_null_ios.o`; all 34 other ntdll archive
members and their order remain identical. New `libntdll_unix.a` SHA256:
`02afde4867ebbac70cab30883a0b3a129718b137f198c19707bf0b87481260cd`.
The r15 win32u input-wait fix and stable launch DLLs remain unchanged. Component
pins are frozen. The checkpoint verifies 1,615 outputs.

## Controls

Normal play initially shows only a native Liquid Glass settings gear. There
are no default mapped buttons, visibility toggle, paging button or forced
rails. Custom controls use a new per-title preference namespace; the old layout
data is retained without being applied. Settings lets the player add/remove a
button, choose its keyboard/mouse action and label, then place it on the actual
paused game screen. Dragging uses the same safe canvas and per-label width as
gameplay. Camera/home-indicator insets remain protected. Tapping a button in
placement mode opens its settings; the Done control resumes the game. Add is
shown only during editing. The settings/Done control is brought above mapped
buttons so a custom position cannot hide the way out.

The editor retains the existing guest input/audio pause rather than resuming
the game underneath drag gestures. Native UIKit targets handle the controls;
the empty SwiftUI editor overlay explicitly ignores hit testing. Outside
editing, buttons send down immediately and up on release/cancel and retain the
existing multi-owner key handling.

## Validation and remaining evidence

- All 48 HostIOKit tests pass, including safe placement, inverse coordinate
  round trips, persistence and input ownership/lifecycle.
- All 32 targeted Cloud/CloudService/SteamAPISwap tests pass. New cases cover
  initial placement in both backends, upload after either backend writes,
  conflicting local copies with backups, case preservation, missing-file
  restoration, safe upgrade from a remote-only baseline and save-root preservation through ticket cleanup. Their backend
  is simulated; they do not test the owner's Steam account.
- Four targeted title-memory and quick-menu tests pass. Explicit cache/worker
  arguments and opt-out remain supported.
- The actual native mixer compiled with ASan/UBSan passes steady PCM equality,
  four rate pairs with callback partition invariance, ring wrap, mono/integer
  formats, bounded refill, stopped streams and short-tail draining. The parent
  revision reproduces callback-partition-dependent consumption.
- The unsigned release compiles and passes all 87 IPA checks. Packaging compares
  all changed production sources with the build checkout, native manifests and
  stable launch DLL hashes. Name, secret, patch-series and whitespace gates pass.
  This is not a full-suite claim.

No phone was connected or controlled and no Windows game was launched this
turn. Native glass appearance, direct drag behavior, actual scene responsiveness,
audible continuity and live cloud loading still require the owner's side-load
test. A new report is needed if the symptom persists; audio health and existing
render/input measurements can separate remaining starvation from presentation
stalls. None of the host results guarantees a particular FPS.

IPA SHA256: `81b6d7eca8cf350ad7658ff1d30963527f04b4f41e1ce5708146c03ed8abcca2`
