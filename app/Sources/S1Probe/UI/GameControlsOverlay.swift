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

/// Only the controls receive touches; the rest of the canvas remains the game's.
struct GameControlsOverlay: View {
    @ObservedObject private var controls = TouchControlsStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if controls.layout.enabled {
                GeometryReader { g in
                    ForEach(controls.layout.normalized.buttons) { binding in
                        HeldTouchButton(binding: binding)
                            .frame(width: buttonWidth(binding.label), height: 46)
                            .opacity(controls.layout.opacity)
                            .position(x: 54 + CGFloat(binding.x) * max(0, g.size.width - 108),
                                      y: 28 + CGFloat(binding.y) * max(0, g.size.height - 56))
                    }
                }
                .padding(.top, 50)
                .transition(.opacity)
            }
            HStack(spacing: 10) {
                Button { controls.layout.enabled.toggle() } label: {
                    Image(systemName: controls.layout.enabled ? "keyboard.fill" : "keyboard")
                        .frame(width: 44, height: 40)
                }
                .accessibilityLabel("顯示或隱藏按鍵")
                Button { InGameMenu.shared.open() } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 44, height: 40)
                }
                .accessibilityLabel("遊戲選單與按鍵映射")
            }
            .foregroundStyle(.white).ppGlass(cornerRadius: 22, interactive: true)
            .buttonStyle(.plain).padding(12)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: controls.layout.enabled)
    }
}

private func buttonWidth(_ text: String) -> CGFloat { min(108, max(48, CGFloat(text.count) * 10 + 24)) }

/// UIControl cancellation (including a system gesture) always sends the up edge.
private struct HeldTouchButton: UIViewRepresentable {
    let binding: TouchBinding
    func makeUIView(context: Context) -> MappedTouchControl { MappedTouchControl() }
    func updateUIView(_ view: MappedTouchControl, context: Context) { view.configure(binding) }
    static func dismantleUIView(_ view: MappedTouchControl, coordinator: ()) { view.releaseInput() }
}

private final class MappedTouchControl: UIControl {
    private let label = UILabel()
    private var binding: TouchBinding?
    private var held = false
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
                    Text("拖曳按鈕調整位置，點選後修改按鍵或名稱。按住即長按，放開即停止。每款遊戲分別保存；畫面其他位置仍可直接點擊。")
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
