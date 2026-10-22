// SPDX-License-Identifier: GPL-3.0-or-later
import HostIOKit
import SwiftUI
import UIKit

@MainActor
final class TouchControlsStore: ObservableObject {
    static let shared = TouchControlsStore()
    @Published var layout = TouchLayout() {
        didSet {
            guard let titleID else { return }
            UserDefaults.standard.set(try? JSONEncoder().encode(layout.normalized), forKey: "touch.freeform." + titleID)
        }
    }
    private var titleID: String?
    @Published var selected: UUID?

    func load(titleID: String?) {
        self.titleID = nil
        let data = titleID.flatMap { UserDefaults.standard.data(forKey: "touch.freeform." + $0) }
        layout = (data.flatMap { try? JSONDecoder().decode(TouchLayout.self, from: $0) } ?? TouchLayout()).normalized
        selected = nil
        self.titleID = titleID
    }

    func move(_ id: UUID, x: Double, y: Double) {
        guard let i = layout.buttons.firstIndex(where: { $0.id == id }) else { return }
        layout.buttons[i].x = min(1, max(0, x))
        layout.buttons[i].y = min(1, max(0, y))
    }

    func actionBinding(_ button: TouchBinding) -> Binding<TouchAction> {
        Binding(get: { self.layout.buttons.first(where: { $0.id == button.id })?.action ?? button.action }, set: { action in
            guard let i = self.layout.buttons.firstIndex(where: { $0.id == button.id }) else { return }
            if self.layout.buttons[i].label == self.layout.buttons[i].action.title { self.layout.buttons[i].label = action.title }
            self.layout.buttons[i].action = action
        })
    }

    func labelBinding(_ button: TouchBinding) -> Binding<String> {
        Binding(get: { self.layout.buttons.first(where: { $0.id == button.id })?.label ?? button.label }, set: { text in
            guard let i = self.layout.buttons.firstIndex(where: { $0.id == button.id }) else { return }
            self.layout.buttons[i].label = String(text.prefix(12))
        })
    }
}

private func buttonWidth(_ text: String) -> CGFloat { min(108, max(48, CGFloat(text.count) * 10 + 24)) }

/// UIKit owns the surface and the actual hit targets together. No full-screen
/// SwiftUI control overlay can intercept the uncovered game area.
final class GameSurfaceContainer: UIView {
    let surface = GameSurfaceView()
    private let menuButton = EdgeMenuControl()
    private let addButton = UIButton(type: .system)
    private var buttons: [UUID: MappedTouchControl] = [:]
    private var layout = TouchLayout()
    private var visible = false
    private var editing = false
    private var edgeToEdge = true
    private var geometry: GameViewport?
    private var lastGeometry = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isMultipleTouchEnabled = true
        addSubview(surface)
        for button in [addButton] {
            var appearance = UIButton.Configuration.glass()
            appearance.baseBackgroundColor = UIColor(PP.glassTint)
        appearance.baseForegroundColor = UIColor(PP.text)
            appearance.cornerStyle = .capsule
            appearance.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 5, bottom: 4, trailing: 5)
            button.configuration = appearance
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            button.setTitleColor(UIColor(PP.text), for: .normal)
            addSubview(button)
        }
        menuButton.accessibilityLabel = "遊戲設定"
        addSubview(menuButton)
        addButton.setTitle("新增", for: .normal)
        menuButton.onOpen = { [weak self] in self?.openMenu() }
        addButton.addTarget(self, action: #selector(addControl), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("created in code") }
    @objc private func openMenu() {
        if editing {
            HostIO.log("menu-input-v2: finish-editing")
            InGameMenu.shared.resume()
        } else {
            let opened = InGameMenu.shared.open()
            HostIO.log("menu-input-v2: top-right activated accepted=\(opened)")
        }
    }
    @objc private func addControl() {
        let b = TouchBinding(action: .enter, x: 0.5, y: 0.5)
        TouchControlsStore.shared.layout.buttons.append(b)
        TouchControlsStore.shared.selected = b.id
        InGameMenu.shared.editingControls = false
        InGameMenu.shared.panel = .controls
    }

    func update(layout: TouchLayout, visible: Bool, editing: Bool, edgeToEdge: Bool, menuAutoHide: Bool) {
        self.layout = layout.normalized
        self.visible = visible
        self.editing = editing
        self.edgeToEdge = edgeToEdge
        menuButton.configure(active: visible, editing: editing, autoHide: menuAutoHide)
        for id in Array(buttons.keys) where !self.layout.buttons.contains(where: { $0.id == id }) {
            buttons.removeValue(forKey: id)?.removeFromSuperview()
        }
        for binding in self.layout.buttons {
            let button: MappedTouchControl
            if let existing = buttons[binding.id] { button = existing }
            else { button = MappedTouchControl(); buttons[binding.id] = button; insertSubview(button, belowSubview: menuButton) }
            button.configure(binding)
            button.editing = editing
            button.onSelect = {
                TouchControlsStore.shared.selected = binding.id
                InGameMenu.shared.editingControls = false
                InGameMenu.shared.panel = .controls
            }
            button.onMove = { [weak self] origin in
                guard let self, let geometry = self.geometry else { return }
                let p = geometry.customPosition(origin: origin, width: buttonWidth(binding.label))
                TouchControlsStore.shared.move(binding.id, x: p.x, y: p.y)
            }
        }
        surface.setDirectInputEnabled(visible && !editing)
        if visible && !editing { surface.becomeFirstResponder() }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let insets = window?.safeAreaInsets ?? safeAreaInsets
        let pixels = TitleScreen.pixelSize
        let geometry = GameViewport(width: bounds.width, height: bounds.height,
            top: insets.top + 4, left: insets.left + 4, bottom: insets.bottom + 4, right: insets.right + 4,
            contentWidth: pixels.width, contentHeight: pixels.height, docked: false, edgeToEdge: edgeToEdge)
        self.geometry = geometry
        surface.frame = geometry.game
        surface.configureRenderSize(pixels)
        menuButton.frame = geometry.menuFrame()
        addButton.frame = CGRect(x: geometry.safe.minX + 2, y: geometry.safe.minY + 2, width: 58, height: 44)
        addButton.isHidden = !visible || !editing
        addButton.isEnabled = layout.buttons.count < 20
        for binding in layout.buttons {
            guard let button = buttons[binding.id] else { continue }
            let shown = visible && (layout.enabled || editing)
            button.setVisible(shown, opacity: layout.opacity)
            button.frame = geometry.customFrame(x: binding.x, y: binding.y, width: buttonWidth(binding.label))
        }
        bringSubviewToFront(menuButton)
        bringSubviewToFront(addButton)
        // Sparse layout evidence, without per-frame UI publishing or device IDs.
        let summary = "viewport-v4 game=\(Int(surface.bounds.width))x\(Int(surface.bounds.height)) safe=\(Int(insets.left)),\(Int(insets.right)),\(Int(insets.bottom)) edge_to_edge=\(edgeToEdge) menu=\(Int(menuButton.frame.minX)),\(Int(menuButton.frame.minY)),\(Int(menuButton.frame.width)) menu_attached=\(menuButton.superview === self) docked=\(layout.docked)"
        if summary != lastGeometry { lastGeometry = summary; HostIO.log("touch-ui: " + summary) }
    }

    override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); setNeedsLayout() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

/// A fixed 48-point target: a real glass UIButton when shown and a transparent
/// UIButton when hidden. Both open on one tap without forwarding it to the
/// game. The pressed button stays attached throughout its touch sequence.
private final class EdgeMenuControl: UIView {
    private let visual = UIButton(type: .system)
    private let reveal = UIButton(type: .custom)
    private weak var heldBy: UIButton?
    private var visibility = EdgeMenuVisibility()
    private var hideTask: Task<Void, Never>?
    private var scheduledDeadline: Double?
    private var requestedAutoHide = true
    private var editing = false
    var onOpen: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        var appearance = UIButton.Configuration.glass()
        appearance.baseBackgroundColor = UIColor(PP.glassTint)
        appearance.baseForegroundColor = UIColor(PP.text); appearance.cornerStyle = .capsule
        appearance.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        visual.configuration = appearance
        visual.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        addSubview(visual)
        addSubview(reveal)
        for button in [visual, reveal] {
            button.isAccessibilityElement = false
            button.isExclusiveTouch = true
            button.addTarget(self, action: #selector(pressed(_:)), for: .touchDown)
            button.addTarget(self, action: #selector(releasedInside(_:)), for: .touchUpInside)
            button.addTarget(self, action: #selector(cancelled(_:)), for: [.touchUpOutside, .touchCancel])
        }
        isAccessibilityElement = true; accessibilityTraits = .button; isHidden = true
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(hovered))
        hover.cancelsTouchesInView = false
        addGestureRecognizer(hover)
        NotificationCenter.default.addObserver(self, selector: #selector(accessibilityChanged),
            name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("created in code") }
    deinit { hideTask?.cancel() }
    override func layoutSubviews() { super.layoutSubviews(); visual.frame = bounds; reveal.frame = bounds }
    func configure(active: Bool, editing: Bool, autoHide: Bool) {
        requestedAutoHide = autoHide
        if self.editing != editing {
            self.editing = editing
            visual.setTitle(editing ? "完成" : nil, for: .normal)
            visual.setImage(editing ? nil : UIImage(systemName: "gearshape.fill"), for: .normal)
        } else if visual.currentImage == nil && !editing {
            visual.setImage(UIImage(systemName: "gearshape.fill"), for: .normal)
        }
        accessibilityLabel = editing ? "完成配置並返回遊戲" : "遊戲設定"
        if !active { heldBy = nil }
        visibility.configure(active: active, autoHide: autoHide && !UIAccessibility.isVoiceOverRunning,
                             editing: editing, now: ProcessInfo.processInfo.systemUptime)
        refresh()
    }
    @objc private func accessibilityChanged() {
        configure(active: visibility.active, editing: editing, autoHide: requestedAutoHide)
    }
    @objc private func hovered(_ gesture: UIHoverGestureRecognizer) {
        visibility.hover(gesture.state == .began || gesture.state == .changed, now: ProcessInfo.processInfo.systemUptime)
        refresh()
    }
    @objc private func pressed(_ sender: UIButton) {
        guard visibility.active, heldBy == nil else { return }
        heldBy = sender
        visibility.begin(now: ProcessInfo.processInfo.systemUptime)
        refresh()
    }
    @objc private func releasedInside(_ sender: UIButton) {
        guard heldBy === sender else { return }
        let open = visibility.end(inside: true, now: ProcessInfo.processInfo.systemUptime)
        heldBy = nil
        refresh()
        if open { onOpen?() }
    }
    @objc private func cancelled(_ sender: UIButton) {
        guard heldBy === sender else { return }
        heldBy = nil
        _ = visibility.end(inside: false, now: ProcessInfo.processInfo.systemUptime)
        refresh()
    }
    override func accessibilityActivate() -> Bool {
        guard visibility.active else { return false }
        onOpen?(); return true
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            heldBy = nil
            _ = visibility.end(inside: false, now: ProcessInfo.processInfo.systemUptime)
            hideTask?.cancel(); hideTask = nil; scheduledDeadline = nil
        }
        else { refresh() }
    }
    private func refresh() {
        isHidden = !visibility.active
        // Revealing the glass must not hide/disable the UIButton that owns
        // the ongoing touch, or UIKit can cancel its touchUpInside event.
        let revealOwnsTouch = heldBy === reveal
        reveal.isHidden = !visibility.active || (visibility.shown && !revealOwnsTouch)
        visual.isUserInteractionEnabled = visibility.active && visibility.shown && !revealOwnsTouch
        if !reveal.isHidden { bringSubviewToFront(reveal) }
        let alpha: CGFloat = visibility.shown ? 1 : 0
        if visibility.shown { visual.isHidden = false }
        if visual.alpha != alpha {
            UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.1 : 0.18,
                           delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) { self.visual.alpha = alpha }
                completion: { _ in if !self.visibility.shown { self.visual.isHidden = true } }
        } else if !visibility.shown { visual.isHidden = true }
        guard scheduledDeadline != visibility.deadline else { return }
        hideTask?.cancel(); hideTask = nil; scheduledDeadline = visibility.deadline
        guard let deadline = visibility.deadline else { return }
        let delay = max(0, deadline - ProcessInfo.processInfo.systemUptime)
        hideTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(150)) } catch { return }
            guard let self else { return }
            self.scheduledDeadline = nil
            self.visibility.expire(now: ProcessInfo.processInfo.systemUptime)
            self.refresh()
        }
    }
}

private final class MappedTouchControl: UIButton {
    var editing = false { didSet { if oldValue != editing { pan.isEnabled = editing; if editing { releaseInput() } } } }
    var onSelect: (() -> Void)?
    var onMove: ((CGPoint) -> Void)?
    private var dragOrigin: CGPoint?
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(dragged))
    private var binding: TouchBinding?
    private var inputHeld = false
    private var wantsVisible = false
    private var lastOpacity: Double?
    override init(frame: CGRect) {
        super.init(frame: frame)
        var appearance = UIButton.Configuration.glass()
        appearance.baseBackgroundColor = UIColor(PP.glassTint)
        appearance.baseForegroundColor = UIColor(PP.text)
        appearance.cornerStyle = .capsule
        appearance.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 5, bottom: 4, trailing: 5)
        configuration = appearance
        titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel?.adjustsFontSizeToFitWidth = true
        titleLabel?.minimumScaleFactor = 0.5
        isAccessibilityElement = true
        accessibilityTraits = .button
        isHidden = true
        pan.isEnabled = false
        addGestureRecognizer(pan)
        addTarget(self, action: #selector(selectedForEdit), for: .touchUpInside)
        restyle()
    }
    required init?(coder: NSCoder) { fatalError("created in code") }
    @objc private func selectedForEdit() { if editing { onSelect?() } }
    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        guard editing, let parent = superview else { return }
        if gesture.state == .began { dragOrigin = frame.origin }
        if let dragOrigin, gesture.state == .began || gesture.state == .changed {
            let offset = gesture.translation(in: parent)
            onMove?(CGPoint(x: dragOrigin.x + offset.x, y: dragOrigin.y + offset.y))
        }
        if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed { dragOrigin = nil }
    }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { releaseInput() } }
    func configure(_ value: TouchBinding) {
        guard binding != value else { return }
        if binding?.id != value.id || binding?.action != value.action { releaseInput() }
        binding = value
        setTitle(value.label, for: .normal)
        accessibilityLabel = value.label + " · " + value.action.title
    }
    func setVisible(_ visible: Bool, opacity: Double) {
        // Keep native glass at full view alpha; dim its text/tint instead of
        // flattening a partially transparent effect view every frame.
        if lastOpacity != opacity {
            configuration?.baseForegroundColor = UIColor(PP.text).withAlphaComponent(max(0.45, opacity))
            lastOpacity = opacity
        }
        guard visible != wantsVisible else { return }
        wantsVisible = visible
        isUserInteractionEnabled = visible
        if visible { isHidden = false; alpha = 0 } else { releaseInput() }
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.1 : 0.18,
                       delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.alpha = visible ? 1 : 0
        } completion: { _ in
            if !self.wantsVisible { self.isHidden = true }
        }
    }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if editing { return super.beginTracking(touch, with: event) }
        guard !inputHeld, let binding else { return false }
        _ = super.beginTracking(touch, with: event)
        inputHeld = true
        HostIO.shared.mappedInput(binding.action, source: binding.id.uuidString, down: true)
        restyle()
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) { releaseInput(); super.endTracking(touch, with: event) }
    override func cancelTracking(with event: UIEvent?) { releaseInput(); super.cancelTracking(with: event) }
    func releaseInput() {
        guard inputHeld, let binding else { return }
        inputHeld = false
        HostIO.shared.mappedInput(binding.action, source: binding.id.uuidString, down: false)
        restyle()
    }
    private func restyle() {
        isHighlighted = inputHeld
        UIView.animate(withDuration: 0.12) {
            self.transform = self.inputHeld ? CGAffineTransform(scaleX: 0.95, y: 0.95) : .identity
        }
    }
}

struct TouchMappingEditor: View {
    @ObservedObject private var controls = TouchControlsStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("顯示觸控按鍵", isOn: $controls.layout.enabled)
                    Text("單指點選或拖曳；雙指輕點是滑鼠右鍵，雙指上下滑動可捲動。設定鍵固定在避開鏡頭的右上角，隱藏時點原位置一下即可開啟。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("新增按鈕、選擇對應按鍵，再到遊戲畫面拖曳位置。位置會避開鏡頭與手勢區，可覆蓋遊戲畫面或放到黑邊。配置時遊戲暫停，按完成後繼續。每款遊戲分別保存。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("在遊戲畫面拖曳位置", systemImage: "hand.draw") {
                        InGameMenu.shared.placeControls()
                    }.buttonStyle(.glass)
                    ForEach(controls.layout.normalized.buttons) { b in
                        Button { controls.selected = b.id } label: {
                            HStack { Text(b.label); Spacer(); Text(b.action.title); if controls.selected == b.id { Image(systemName: "checkmark") } }
                        }.buttonStyle(.glass)
                    }
                    HStack {
                        Menu {
                            ForEach(TouchAction.allCases, id: \.self) { action in
                                Button(action.title) {
                                    let b = TouchBinding(action: action, x: 0.5, y: 0.5)
                                    controls.layout.buttons.append(b)
                                    controls.layout.enabled = true
                                    controls.selected = b.id
                                }
                            }
                        } label: { Label("新增按鍵", systemImage: "plus") }
                        .disabled(controls.layout.buttons.count >= 20)
                        Spacer()
                        Text("\(controls.layout.buttons.count)/20").foregroundStyle(.secondary)
                    }
                    if let button = controls.layout.buttons.first(where: { $0.id == controls.selected }) {
                        Picker("映射按鍵", selection: controls.actionBinding(button)) {
                            ForEach(TouchAction.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        TextField("按鈕名稱", text: controls.labelBinding(button))
                            .textFieldStyle(.roundedBorder)
                        Button("刪除此按鍵", role: .destructive) {
                            controls.layout.buttons.removeAll { $0.id == button.id }; controls.selected = nil
                        }
                    }
                    HStack {
                        Text("按鍵亮度")
                        Slider(value: $controls.layout.opacity, in: 0.2...1)
                    }
                    Button("移除全部按鈕", role: .destructive) {
                        controls.layout = TouchLayout(); controls.selected = nil
                    }
                }.padding(20)
            }
            .ppSettingsSurface()
            .navigationTitle("自訂螢幕按鈕").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
