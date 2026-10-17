# Game input waits, native glass controls and fresh Steam Cloud checks

The owner reports immediate highlighting of the side controls but a long delay
before game clicks/options respond. This puts the reported delay after UIKit
touch delivery. No new device report accompanies this result, so the remaining
game/render load and the actual end-to-end latency are not measured here.

## Input wait defect

The iOS host input ring has no wineserver file descriptor to wake a blocking
message wait. The existing 16 ms polling path in win32u's `wait_message` was
restricted to desktop mode. A game could therefore leave host input queued
until another handle or timer woke its thread. Patch 0106 extends that existing
deadline-bounded poll to games, preserving the caller's absolute deadline and
alertability. Queue readiness alone does not satisfy WaitAll's other handles.
This removes a concrete input delivery defect, but does not promise that every
game frame or input will complete within 16 ms.

`build/test-ios-input-wait.py` extracts the actual timeout conversion and wait
function from the patched native tree and builds it against simulated native
wait/clock/queue functions with AddressSanitizer and UndefinedBehaviorSanitizer.
The parent revision reproduces the delayed/missed input assertion. The patched
function passes 43 arrival/deadline/mode cases, including finite and infinite
waits, zero timeout, external handles, WaitAll and alertable APC returns. These
are deterministic host simulations, not phone timing measurements.

The checkpoint migration verifies its r14 inputs, applies the series normally,
compiles only `message_ios.c`, and replaces only `message.o` in the verified
win32u archive. Member ordering and all 87 other members remain byte-identical.
The checkpoint verifies 1,615 outputs. New `libwin32u_unix.a` SHA256:
`c0e279a03d755fbf9725a66e7e3e95ab24a53b88b6d105935e8be969ea2484b9`.
The stable game-launch fixes, component pins and remaining native modules are
unchanged. The migration helper intentionally rejects a second migration of
the already changed archive.

## Controls

The UIKit rail controls and mapped input buttons now use
[`UIButton.Configuration.glass()`](https://developer.apple.com/documentation/uikit/uibutton/configuration-swift.struct).
Mapped buttons retain immediate down/up delivery, cancellation and held-input
release. Native highlighting and a small scale animation replace flat custom
fills. Visibility still animates; the brightness slider dims foreground tint
instead of permanently lowering the entire glass effect view's alpha. Existing
camera-safe rails and input mapping remain in place. Appearance requires owner
verification on the phone.

## Steam Cloud

Prelaunch now requests a fresh synchronization even when this process already
has cached cloud status. Session/network and per-file failures are visible and
prevent silently starting with an unsynchronized save. The player can retry
with the new game-page sync action, or explicitly disable that game's cloud
option for offline play. Existing backup and conflict-choice behavior remains.

Starting a Steam title persists its app ID as pending cloud work. On the next
app process/session restoration, cloud saves run before achievement uploads.
Pending work is cleared only after a sync without file failures or unresolved
conflicts. Steam remains suspended while the native game process is active;
upload after play therefore requires closing and reopening PlayPort. There is
no claim of in-game background synchronization.

The 14 existing Cloud/CloudService tests pass, including fresh-device download,
subsequent upload, first-upload confirmation, conflicting changes and backup
retention. Their backend is simulated. They do not exercise a live account,
the new UIKit rows, or prove that every game writes into its Steam remote root.
An older report contains a successful 25-file comparison with no transfers;
that does not establish the cause of the owner's current sync complaint. No
unproven save-directory copying or conflict auto-resolution was added.

## Build and limits

The unsigned release compiles and passes all 87 IPA checks. Packaging verifies
the changed app sources against the build checkout, the new win32u manifest
hash and the stable launch DLL hashes. Name, secret, patch-series and whitespace
gates pass. This is not a full-suite claim.

No phone was connected or controlled and no live Steam saves were transferred
by this workstation. Actual game response, native glass appearance and the
owner's cloud round trip require the owner's side-load test. Existing passive
input/frame logs remain available to distinguish remaining stalls. Audio code,
game assets and audio encoding are unchanged.

IPA SHA256: `33b881b8d22813d064308950737688b593f5836e0e7dd7e8ba25ab8f7ad30df2`
