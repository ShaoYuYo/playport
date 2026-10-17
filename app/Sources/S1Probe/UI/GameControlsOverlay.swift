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
            UserDefaults.standard.set(try? JSONEncoder().encode(layout.normalized), forKey: "touch.layout." + titleID)
        }
    }
    private var titleID: String?

    func load(titleID: String?) {
        self.titleID = nil
        let data = titleID.flatMap { UserDefaults.standard.data(forKey: "touch.layout." + $0) }
        layout = (data.flatMap { try? JSONDecoder().decode(TouchLayout.self, from: $0) } ?? TouchLayout()).normalized
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
    private let menuButton = UIButton(type: .system)
    private let toggleButton = UIButton(type: .system)
    private let pageButton = UIButton(type: .system)
    private var buttons: [UUID: MappedTouchControl] = [:]
    private var layout = TouchLayout()
    private var visible = false
    private var page = 0
    private var lastGeometry = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isMultipleTouchEnabled = true
        addSubview(surface)
        for button in [menuButton, toggleButton, pageButton] {
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = UIColor(white: 0.14, alpha: 0.85)
            button.layer.cornerRadius = 14
            addSubview(button)
        }
        menuButton.setTitle("選單", for: .normal)
        menuButton.accessibilityLabel = "遊戲選單、按鍵映射與畫面設定"
        toggleButton.setTitle("按鍵", for: .normal)
        toggleButton.accessibilityLabel = "顯示或隱藏觸控按鍵"
        menuButton.addTarget(self, action: #selector(openMenu), for: .touchUpInside)
        toggleButton.addTarget(self, action: #selector(toggleControls), for: .touchUpInside)
        pageButton.addTarget(self, action: #selector(nextPage), for: .touchUpInside)
    }
    required init?(coder: NSCoder) { fatalError("created in code") }
    @objc private func openMenu() { InGameMenu.shared.open() }
    @objc private func toggleControls() { TouchControlsStore.shared.layout.enabled.toggle() }
    @objc private func nextPage() { page += 1; setNeedsLayout() }

    func update(layout: TouchLayout, visible: Bool) {
        self.layout = layout.normalized
        self.visible = visible
        for id in Array(buttons.keys) where !self.layout.buttons.contains(where: { $0.id == id }) {
            buttons.removeValue(forKey: id)?.removeFromSuperview()
        }
        for binding in self.layout.buttons {
            let button: MappedTouchControl
            if let existing = buttons[binding.id] { button = existing }
            else { button = MappedTouchControl(); buttons[binding.id] = button; insertSubview(button, belowSubview: menuButton) }
            button.configure(binding)
        }
        surface.isUserInteractionEnabled = visible
        if visible { surface.becomeFirstResponder() }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let insets = window?.safeAreaInsets ?? safeAreaInsets
        let pixels = TitleScreen.pixelSize
        let geometry = GameViewport(width: bounds.width, height: bounds.height,
            top: insets.top + 4, left: insets.left + 4, bottom: insets.bottom + 4, right: insets.right + 4,
            contentWidth: pixels.width, contentHeight: pixels.height, docked: layout.docked)
        surface.frame = geometry.game
        surface.configureRenderSize(pixels)
        let pages = max(1, (layout.buttons.count + geometry.pageSize - 1) / geometry.pageSize)
        page %= pages
        menuButton.frame = CGRect(x: geometry.safe.maxX - 50, y: geometry.safe.minY + 2, width: 48, height: 44)
        toggleButton.frame = CGRect(x: geometry.safe.minX + 2, y: geometry.safe.minY + 2, width: 48, height: 44)
        pageButton.frame = CGRect(x: geometry.safe.minX + 2, y: geometry.safe.maxY - 46, width: 48, height: 44)
        pageButton.setTitle("\(page + 1)/\(pages)", for: .normal)
        menuButton.isHidden = !visible
        toggleButton.isHidden = !visible
        toggleButton.isSelected = layout.enabled
        pageButton.isHidden = !visible || !layout.enabled || !layout.docked || pages == 1
        for (index, binding) in layout.buttons.enumerated() {
            guard let button = buttons[binding.id] else { continue }
            let shown = visible && layout.enabled && (!layout.docked || index / geometry.pageSize == page)
            button.setVisible(shown, opacity: layout.opacity)
            button.frame = layout.docked ? geometry.controlFrame(index: index % geometry.pageSize)
                : geometry.customFrame(x: binding.x, y: binding.y, width: buttonWidth(binding.label))
        }
        // Sparse layout evidence, without per-frame UI publishing or device IDs.
        let summary = "game=\(Int(surface.bounds.width))x\(Int(surface.bounds.height)) safe=\(Int(insets.left)),\(Int(insets.right)),\(Int(insets.bottom)) docked=\(layout.docked)"
        if summary != lastGeometry { lastGeometry = summary; HostIO.log("touch-ui: " + summary) }
    }

    override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); setNeedsLayout() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }
}

private final class MappedTouchControl: UIControl {
    private let label = UILabel()
    private var binding: TouchBinding?
    private var held = false
    private var wantsVisible = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 18
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.isUserInteractionEnabled = false
        addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
        isHidden = true
        restyle()
    }
    required init?(coder: NSCoder) { fatalError("created in code") }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { releaseInput() } }
    override func layoutSubviews() { super.layoutSubviews(); label.frame = bounds.insetBy(dx: 8, dy: 2) }
    func configure(_ value: TouchBinding) {
        if binding?.id != value.id || binding?.action != value.action { releaseInput() }
        binding = value
        label.text = value.label
        accessibilityLabel = value.label + " · " + value.action.title
    }
    func setVisible(_ visible: Bool, opacity: Double) {
        guard visible != wantsVisible else { if visible { alpha = opacity }; return }
        wantsVisible = visible
        isUserInteractionEnabled = visible
        if visible { isHidden = false; alpha = 0 } else { releaseInput() }
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.1 : 0.18,
                       delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.alpha = visible ? opacity : 0
        } completion: { _ in
            if !self.wantsVisible { self.isHidden = true }
        }
    }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard !held, let binding else { return false }
        held = true
        HostIO.shared.mappedInput(binding.action, source: binding.id.uuidString, down: true)
        restyle()
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) { releaseInput() }
    override func cancelTracking(with event: UIEvent?) { releaseInput() }
    func releaseInput() {
        guard held, let binding else { return }
        held = false
        HostIO.shared.mappedInput(binding.action, source: binding.id.uuidString, down: false)
        restyle()
    }
    private func restyle() {
        UIView.animate(withDuration: 0.12) {
            self.backgroundColor = self.held ? UIColor.systemBlue.withAlphaComponent(0.75) : UIColor(white: 0.12, alpha: 0.6)
            self.transform = self.held ? CGAffineTransform(scaleX: 0.95, y: 0.95) : .identity
        }
    }
}

struct TouchMappingEditor: View {
    @ObservedObject private var controls = TouchControlsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("顯示觸控按鍵", isOn: $controls.layout.enabled)
                    Toggle("使用黑色邊欄（避開鏡頭）", isOn: $controls.layout.docked)
                    Text("邊欄模式會把按鍵排列到遊戲畫面外側；按鍵過多可切換分頁。關閉邊欄模式後使用下方拖曳位置。點選預覽按鈕可修改按鍵或名稱。按住即長按，放開即停止。每款遊戲分別保存。")
                        .font(.footnote).foregroundStyle(.secondary)
                    GeometryReader { g in
                        ZStack {
                            RoundedRectangle(cornerRadius: 18).fill(.black.opacity(0.35))
                            ForEach(controls.layout.normalized.buttons) { b in
                                MappingPreviewButton(binding: b, size: g.size, selected: selected == b.id) { selected = b.id }
                            }
                        }
                    }.frame(height: 210)
                    HStack {
                        Menu {
                            ForEach(TouchAction.allCases, id: \.self) { action in
                                Button(action.title) {
                                    let b = TouchBinding(action: action, x: 0.5, y: 0.5)
                                    controls.layout.buttons.append(b)
                                    controls.layout.enabled = true
                                    selected = b.id
                                }
                            }
                        } label: { Label("新增按鍵", systemImage: "plus") }
                        .disabled(controls.layout.buttons.count >= 20)
                        Spacer()
                        Text("\(controls.layout.buttons.count)/20").foregroundStyle(.secondary)
                    }
                    if let button = controls.layout.buttons.first(where: { $0.id == selected }) {
                        Picker("映射按鍵", selection: controls.actionBinding(button)) {
                            ForEach(TouchAction.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        TextField("按鈕名稱", text: controls.labelBinding(button))
                            .textFieldStyle(.roundedBorder)
                        Button("刪除此按鍵", role: .destructive) {
                            controls.layout.buttons.removeAll { $0.id == button.id }; selected = nil
                        }
                    }
                    HStack {
                        Text("透明度")
                        Slider(value: $controls.layout.opacity, in: 0.2...1)
                    }
                    Button("恢復預設配置") {
                        controls.layout = TouchLayout(); controls.layout.enabled = true; selected = nil
                    }
                }.padding(20)
            }
            .navigationTitle("按鍵映射")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

private struct MappingPreviewButton: View {
    let binding: TouchBinding
    let size: CGSize
    let selected: Bool
    let select: () -> Void
    @State private var origin: CGPoint?
    var body: some View {
        let w = max(1, size.width - 108), h = max(1, size.height - 56)
        Text(binding.label).font(.system(size: 14, weight: .semibold))
            .frame(width: buttonWidth(binding.label), height: 46)
            .background(selected ? Color.blue.opacity(0.7) : Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
            .position(x: 54 + CGFloat(binding.x) * w, y: 28 + CGFloat(binding.y) * h)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if origin == nil { origin = CGPoint(x: binding.x, y: binding.y); select() }
                    guard let origin else { return }
                    TouchControlsStore.shared.move(binding.id, x: origin.x + v.translation.width / w,
                                                   y: origin.y + v.translation.height / h)
                }
                .onEnded { _ in origin = nil })
    }
}
