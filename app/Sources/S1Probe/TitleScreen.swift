// SPDX-License-Identifier: GPL-3.0-or-later
// A title's screen (the UI's Play): landscape, a guest display mode at the
// panel's native pixels or the title's own screen (LaunchSettings, else its
// titles.json `screen`; HostIOKit Display.guestSize), the swap chain
// aspect-fitted rather than stretched, a Unity title asked to open full screen
// at that size (LaunchCoordinator), and presents free to run at the panel's
// refresh (120 Hz on ProMotion) instead of DXMT's 60 Hz lock. The player's
// frame rate limit (LaunchSettings) is the only cap: the game layer holds each
// frame to it (PacedMetalLayer, HostIO.swift). The size becomes
// MADEIRA_SCREEN_W/H, which the runtime's virtual monitor, metrics and mode
// list follow; the guest's monitor reports the panel's maximum rate
// (MADEIRA_SCREEN_HZ).

#if canImport(UIKit)
import Foundation
import HostIO
import HostIOKit
import QuartzCore
import UIKit

enum TitleScreen {
    /// What configure() chose, for the title's log.
    nonisolated(unsafe) private(set) static var summary = "not configured"

    /// Retain the refresh request so the in-game FPS picker can change it.
    @MainActor private static var link: CADisplayLink?
    @MainActor private(set) static var frameLimit = 0
    @MainActor private(set) static var configuredSize = "—"
    @MainActor private(set) static var pixelSize = CGSize(width: 1280, height: 720)

    /// On the main thread, before the runtime reads its environment; again
    /// for each title a process starts, since the environment it sets is only
    /// read when the runtime starts. `title` is the title's screen spec
    /// (LaunchPlan.screen, or the player's choice), nil for the panel's;
    /// `frameLimit` the player's limit, 0 for none.
    @MainActor
    static func configure(title: String? = nil, frameLimit: Int = 0) {
        let px = UIScreen.main.nativeBounds.size
        let screen: String
        if let (w, h) = Display.guestSize(panelLong: Int(px.width), panelShort: Int(px.height), spec: title) {
            setenv("MADEIRA_SCREEN_W", String(w), 1)
            setenv("MADEIRA_SCREEN_H", String(h), 1)
            screen = "\(w)x\(h)" + (title.map { " (the title's screen \($0))" } ?? "")
            configuredSize = "\(w)×\(h)"
            pixelSize = CGSize(width: w, height: h)
        } else {
            screen = "\(title ?? "") not understood; the runtime's 1024x768"
            configuredSize = "1024×768"
            pixelSize = CGSize(width: 1024, height: 768)
        }
        madeira_set_vsync_locked(0)
        setFrameLimit(frameLimit)
        // The refresh the guest's monitor reports (patches/madeira-unix/0011-win32u-report-the-host-panel-s-refresh-rate-for-the-.patch).
        let hz = UIScreen.main.maximumFramesPerSecond
        setenv("MADEIRA_SCREEN_HZ", String(hz), 1)
        summary = "screen \(screen) (panel \(Int(px.width))x\(Int(px.height)) px), landscape, swap chain aspect-fitted, "
            + "presents free-running, refresh request \(Self.frameLimit > 0 ? Self.frameLimit : hz) Hz"
            + (link == nil ? " (native cadence, no empty display-link callbacks)" : " (ProMotion display link)")
            + (Self.frameLimit > 0 ? ", frames limited to \(Self.frameLimit) FPS" : ", no frame rate limit")
            + ", guest monitor \(ProcessInfo.processInfo.environment["MADEIRA_SCREEN_HZ"] ?? "60") Hz; frame-pacing-v2 drawable wait counts toward limiter deadline"
    }

    /// ProMotion keeps a CAMetalLayer at 60 Hz unless the app asks for more:
    /// CADisableMinimumFrameDurationOnPhone (Info.plist) and a display link's
    /// preferred range. The link does no work; it only states the rate.
    @MainActor
    static func setFrameLimit(_ fps: Int) {
        let maximum = UIScreen.main.maximumFramesPerSecond
        frameLimit = fps > 0 ? min(fps, maximum) : 0
        PacedMetalLayer.limit(fps: frameLimit)
        let top = Float(frameLimit > 0 ? frameLimit : maximum)
        // A 60 Hz panel already presents at its native refresh. An empty
        // display-link callback there just wakes the main thread every frame,
        // including static scenes. Only retain the request needed for >60 Hz.
        guard top > 60 else {
            link?.invalidate()
            link = nil
            return
        }
        if link == nil {
            let newLink = CADisplayLink(target: Tick.shared, selector: #selector(Tick.tick))
            newLink.add(to: .main, forMode: .common)
            link = newLink
        }
        guard let link else { return }
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, top), maximum: top, preferred: top)
    }

    private final class Tick: NSObject, Sendable {
        static let shared = Tick()
        @objc func tick() {}
    }
}
#endif
