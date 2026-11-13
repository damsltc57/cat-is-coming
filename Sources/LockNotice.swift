import AppKit
import SwiftUI

final class LockNoticeController {
    private static let size = NSSize(width: 394, height: 138)
    private let model = LockNoticeModel()
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?

    func update(keyboard: Bool, pointer: Bool, show: Bool) {
        if model.showHeatmap && !show { return }
        guard keyboard || pointer else {
            dismiss()
            return
        }
        model.status = if keyboard && pointer {
            String(localized: "Keyboard and mouse locked")
        } else if keyboard {
            String(localized: "Keyboard locked")
        } else {
            String(localized: "Mouse locked")
        }
        guard show else { return }
        model.showHeatmap = false
        present(for: .seconds(4), interactive: false)
    }

    func showKeyboardReport(open: @escaping () -> Void) {
        model.showHeatmap = true
        model.openHeatmap = { [weak self] in
            self?.dismiss()
            open()
        }
        present(for: .seconds(8), interactive: true)
    }

    private func present(for duration: Duration, interactive: Bool) {
        dismissal?.cancel()
        let panel = panel ?? makePanel()
        panel.ignoresMouseEvents = !interactive
        if !panel.isVisible || !model.visible {
            position(panel)
            panel.orderFrontRegardless()
            model.setVisible(true)
        }
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func dismiss() {
        guard model.visible else { return }
        dismissal?.cancel()
        model.setVisible(false)
        panel?.ignoresMouseEvents = true
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: LockNoticeView(model: model))
        panel.setContentSize(Self.size)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        guard let bounds = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(
            x: max(bounds.minX, bounds.maxX - Self.size.width - 12),
            y: max(bounds.minY, bounds.maxY - Self.size.height - 8)
        ))
    }
}

private final class LockNoticeModel: ObservableObject {
    @Published var status = ""
    @Published var showHeatmap = false
    var openHeatmap: (() -> Void)?
    @Published private(set) var visible = false

    func setVisible(_ visible: Bool) {
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)) {
            self.visible = visible
        }
    }
}

private struct LockNoticeView: View {
    @ObservedObject var model: LockNoticeModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cream = Color(red: 0.98, green: 0.95, blue: 0.89)
    private let mint = Color(red: 0.76, green: 0.88, blue: 0.70)
    private let surface = Color(red: 0.13, green: 0.17, blue: 0.14)

    var body: some View {
        HStack(spacing: 15) {
            Image("CatArtwork")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(model.visible || reduceMotion ? 0 : -9))
                .scaleEffect(model.visible || reduceMotion ? 1 : 0.95)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                if model.showHeatmap {
                    title("Keyboard unlocked")
                    Button {
                        model.openHeatmap?()
                    } label: {
                        Label("View Paw Activity", systemImage: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(mint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(mint)
                    .padding(.top, 3)
                } else {
                    title("Your cat is coming")
                    Text(model.status)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(cream.opacity(0.8))
                    HStack(spacing: 7) {
                        Text("Unlock Everything")
                            .font(.system(size: 12))
                            .foregroundStyle(cream.opacity(0.8))
                        Text(Shortcut.unlock.label)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(mint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                            .accessibilityLabel("Control, Shift, and Escape")
                    }
                    .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(surface, in: RoundedRectangle(cornerRadius: 23))
        .overlay {
            RoundedRectangle(cornerRadius: 23)
                .strokeBorder(cream.opacity(0.14))
        }
        .shadow(color: .black.opacity(0.26), radius: 8, x: 0, y: 4)
        .padding(11)
        .frame(maxHeight: .infinity, alignment: .top)
        .opacity(model.visible ? 1 : 0)
        .offset(y: model.visible || reduceMotion ? 0 : -7)
        .accessibilityElement(children: model.showHeatmap ? .contain : .combine)
    }

    private func title(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundStyle(cream)
    }
}
