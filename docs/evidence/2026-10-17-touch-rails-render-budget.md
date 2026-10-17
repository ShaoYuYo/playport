# Controller-free input and bounded rendering

The owner reports that the game launches but touch input does nothing and
gameplay is very slow after r13. No new device report accompanies this result.
The cause of the observed game slowdown and the exact dropped-input stage
are therefore not established by device evidence.

## Input and layout changes

The Metal game view and its actual UIControl targets now share a UIKit parent.
The full-screen SwiftUI controls overlay is removed. Empty launch overlays
explicitly stop participating in hit testing after the launch sheet closes.
This removes an ambiguous interception path rather than asserting that every
game's input delivery has already been observed working.

The default layout reserves two 56-point black side rails inside the window's
current safe-area insets. The game viewport is aspect-fitted between them.
The controls therefore clear the camera and home indicator and remain outside
the game's view. Rotation/safe-area changes relayout the parent. Menu and
controls visibility buttons are always available during play, without Home
on a controller. Mapping buttons page when they exceed the rail capacity.
The menu remains accessible while mappings are hidden. Custom-position mode
is still available in the mapping editor; it can overlap the picture by choice.

New layouts enable touch controls and include Ctrl, Esc, Space, Enter and
both mouse buttons. Old saved layouts gain the rail default without losing
their keys or explicit visibility choice. Controls retain their identity across
updates, animate visibility, and release held input on cancellation, hiding,
removal, menu opening and focus loss. Controller-connection notes now describe
touch operation instead of asking everyone to connect hardware.

Direct touches map against the last presented texture's aspect ratio instead
of assuming the drawable extent is the image. A touch must begin within the
image; subsequent movement and release clamp to its boundary, so dragging out
does not lose the up event. The native input ABI and Wine input code remain
unchanged. First touch edges are logged with client fractions and lifecycle
state; existing Winios queue/drain/dispatch evidence covers the native path.

## Rendering changes

Unset global display settings return to a 720-row, at-most-60-FPS budget.
A one-time Senren Banka adjustment replaces unset/native per-game resolution
with 1280x720, and unset/unlimited/above-60 frame caps with 60. Deliberately
lower sizes or frame limits survive. The player can change these values again.

The game's view scale and initial drawable size now reflect the selected
render budget, capped by physical panel scale. Lower guest resolution no
longer automatically receives a native-size host drawable. Geometry changes
update it; ordinary UI updates do not overwrite a game's later drawable-size
choice. Native resolution remains available. The in-game menu has 720p/60
and 720p/30 presets, with FPS immediate and resolution on the next launch.
No clock acceleration, interpolation, CPU-count change, cache change or
native-runtime rebuild is included.

Passive frame health logs count actual presentation callbacks, gaps over
50 ms, maximum gap, average/maximum nextDrawable wait and failed drawable
requests. The deliberate FPS-limiter sleep is excluded from drawable wait.
Logs are sampled every five seconds through the existing memory watcher;
there is no GPU readback or per-frame SwiftUI update. Focus/menu transitions
reset the measurement window. These figures distinguish requested FPS from
observed presentation, but do not themselves identify a CPU/GPU bottleneck.

Apple documents that [hit testing includes transparent portions of a view](https://developer.apple.com/documentation/uikit/uiview/hittest(_:with:))
and that [drawableSize controls rendering texture pixels](https://developer.apple.com/documentation/quartzcore/cametallayer/drawablesize).
The implementation explicitly accounts for both.

## Validation and limits

- All 48 HostIOKit tests pass. New coverage checks both camera-side rotations,
  safe control rectangles outside the game, aspect preservation, custom bounds,
  letterbox rejection, drag-out release coordinates, old-layout decoding and
  presentation/wait measurements. Existing ownership/lifecycle tests still pass.
- All 22 targeted PlayportKit display, launch-settings, menu and setup tests pass.
- The unsigned release compiles and passes all 87 IPA checks. Its native
  checkpoint verifies 1,615 outputs; native module hashes are unchanged.
- Name, secret and whitespace gates pass. This is not a full-suite claim.

No phone was connected or controlled. The new UIKit hit routing, game
interaction and improvement to actual gameplay FPS still require the owner's
side-load test. The next report includes evidence to investigate remaining
input delivery, renderer stalls or game/emulator CPU cost. Audio assets,
format conversion and runtime audio code are unchanged.

IPA SHA256: `3b9dd4477a3c61def2f61aab756cabcd08f06ec04ff23872f03d04f4d79854e2`
