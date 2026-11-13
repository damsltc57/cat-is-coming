import Carbon
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct HeatmapView: View {
    let session: KeyboardSession
    @State private var metric: Metric = .presses
    @State private var selection: Int64?
    @State private var shareImage: PawReportImage?
    @State private var shareFailed = false
    private let keyboard = HeatmapKeyboard()

    private enum Metric: Hashable {
        case presses, heldTime

        func value(_ activity: KeyActivity) -> Double {
            self == .presses ? Double(activity.presses) : activity.heldSeconds
        }
    }

    private var activity: [Int64: KeyActivity] { session.keys }
    private var totalPresses: Int { activity.values.reduce(0) { $0 + $1.presses } }
    private var reportLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? Locale.current.identifier)
    }

    private var napDuration: String {
        session.duration.formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated).locale(reportLocale)
        )
    }

    private var busiest: Int64? {
        activity.keys.min {
            let first = activity[$0]?.presses ?? 0
            let second = activity[$1]?.presses ?? 0
            return first == second ? $0 < $1 : first > second
        }
    }

    private var maxValue: Double { activity.values.map(metric.value).max() ?? 0 }

    var body: some View {
        report(interactive: true)
            .sheet(item: $shareImage) { PawSharePreview(report: $0) }
            .alert("Couldn’t create the image.", isPresented: $shareFailed) {
                Button("OK", role: .cancel) {}
            }
    }

    private func report(interactive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            header(interactive: interactive)
            keyboardPanel(interactive: interactive)
            footer
        }
        .padding(.horizontal, 32)
        .padding(.top, interactive ? 43 : 28)
        .padding(.bottom, 22)
        .frame(width: 928)
        .foregroundStyle(HeatmapPalette.ink)
        .background(HeatmapPalette.paper)
        .environment(\.colorScheme, .light)
    }

    private func header(interactive: Bool) -> some View {
        HStack(spacing: 12) {
            Image("CatArtwork")
                .resizable()
                .scaledToFit()
                .frame(width: 61, height: 61)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Paws on the Keyboard")
                    .font(.custom("Baskerville", size: 41))
                    .tracking(-0.7)
                    .accessibilityAddTraits(.isHeader)
                Text("Keyboard nap: \(napDuration)")
                    .font(.system(size: 13))
                    .foregroundStyle(HeatmapPalette.muted)
            }
            Spacer()
            if interactive {
                Button(action: prepareShare) {
                    Label("Share the Paw Prints…", systemImage: "square.and.arrow.up")
                }
                .controlSize(.large)
            }
        }
    }

    private func keyboardPanel(interactive: Bool) -> some View {
        let peak = maxValue
        let selected = selection ?? busiest
        let extras = activity.keys.filter { !keyboard.codes.contains($0) }.sorted()
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                if interactive {
                    HStack(spacing: 2) {
                        metricButton("Presses", .presses)
                        metricButton("Held Time", .heldTime)
                    }
                    .padding(2)
                    .background(HeatmapPalette.control, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Heatmap metric")
                } else {
                    Text(metric == .presses ? "Presses" : "Held Time")
                        .font(.system(size: 13, weight: .semibold))
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("Low")
                    ForEach(HeatmapPalette.heat.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(HeatmapPalette.heat[index])
                            .frame(width: 16, height: 12)
                            .accessibilityHidden(true)
                    }
                    Text("High")
                }
                .font(.system(size: 11))
                .foregroundStyle(HeatmapPalette.muted)
            }

            ZStack(alignment: .topLeading) {
                ForEach(keyboard.keys) { key in
                    keycap(key.id, peak: peak, selected: key.id == selected, interactive: interactive,
                           returnInset: key.returnInset)
                        .frame(width: key.width, height: key.height)
                        .offset(x: key.x, y: key.y)
                }
            }
            .frame(width: HeatmapKeyboard.width, height: HeatmapKeyboard.height, alignment: .topLeading)

            if !extras.isEmpty {
                let grid = LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 5)], spacing: 5) {
                    ForEach(extras, id: \.self) { code in
                        keycap(code, peak: peak, selected: code == selected, interactive: interactive)
                            .frame(height: 30)
                    }
                }
                if interactive {
                    ScrollView { grid.padding(2) }
                        .frame(height: extras.count > 10 ? 66 : 34)
                } else {
                    grid
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 25)
        .background(HeatmapPalette.sage, in: RoundedRectangle(cornerRadius: 14))
    }

    private var footer: some View {
        VStack(spacing: 13) {
            Rectangle().fill(HeatmapPalette.divider).frame(height: 1)
                .accessibilityHidden(true)

            if let selected = selection ?? busiest {
                HStack(spacing: 19) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Total Presses")
                            .font(.system(size: 11))
                            .foregroundStyle(HeatmapPalette.muted)
                        Text(totalPresses.formatted())
                            .font(.system(size: 19, weight: .semibold))
                    }
                    .frame(minWidth: 107, alignment: .leading)
                    .accessibilityElement(children: .combine)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Most Pressed Key")
                            .font(.system(size: 11))
                            .foregroundStyle(HeatmapPalette.muted)
                        Text(busiest.map(keyboard.label) ?? "—")
                            .font(.system(size: 19, weight: .semibold))
                    }
                    .accessibilityElement(children: .combine)

                    Spacer(minLength: 12)
                    let level = heatLevel(for: selected, peak: maxValue)
                    HStack(spacing: 9) {
                        Text(keyboard.label(selected))
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 7)
                            .frame(minWidth: 26, minHeight: 26)
                            .foregroundStyle(HeatmapPalette.legendInk(level))
                            .background(HeatmapPalette.keyFill(level), in: RoundedRectangle(cornerRadius: 5))
                        Text(details(for: selected))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(HeatmapPalette.muted)
                    }
                    .accessibilityElement(children: .combine)
                }
                .monospacedDigit()
            } else {
                Text("No key presses during this lock.")
                    .font(.system(size: 13))
                    .foregroundStyle(HeatmapPalette.muted)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            }
        }
    }

    private func metricButton(_ title: LocalizedStringKey, _ option: Metric) -> some View {
        Button {
            metric = option
        } label: {
            Text(title)
                .font(.system(size: 12, weight: metric == option ? .semibold : .medium))
                .padding(.horizontal, 14)
                .frame(height: 27)
                .foregroundStyle(metric == option ? HeatmapPalette.ink : HeatmapPalette.muted)
                .background(metric == option ? HeatmapPalette.paper : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(metric == option ? .isSelected : [])
    }

    @ViewBuilder
    private func keycap(
        _ code: Int64, peak: Double, selected: Bool, interactive: Bool, returnInset: CGFloat = 0
    ) -> some View {
        let label = keyboard.label(code)
        let level = heatLevel(for: code, peak: peak)
        let face = Text(label)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.67)
            .padding(.leading, returnInset)
            .padding(.top, returnInset > 0 ? 32 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(HeatmapPalette.legendInk(level))
            .contentShape(HeatmapKeyShape(inset: returnInset))
        let style = HeatmapKeyStyle(level: level, selected: selected, returnInset: returnInset)
        if interactive {
            Button {
                selection = code
            } label: {
                face
            }
            .buttonStyle(style)
            .help(details(for: code))
            .accessibilityLabel(label)
            .accessibilityValue(details(for: code))
            .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            style.keyFace(face, pressed: false)
        }
    }

    private func prepareShare() {
        guard let data = reportPNG() else {
            shareFailed = true
            return
        }
        shareImage = PawReportImage(data: data)
    }

    func reportPNG() -> Data? {
        let renderer = ImageRenderer(content: report(interactive: false).environment(\.locale, reportLocale))
        renderer.scale = 2
        renderer.isOpaque = true
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private func heatLevel(for key: Int64, peak: Double) -> Int? {
        guard let sample = activity[key], peak > 0 else { return nil }
        let value = metric.value(sample)
        guard value > 0 else { return nil }
        let steps = HeatmapPalette.heat.count
        return min(steps - 1, Int(ceil(value / peak * Double(steps))) - 1)
    }

    private func details(for key: Int64) -> String {
        let count = activity[key]?.presses ?? 0
        if key == kVK_CapsLock { return String(localized: "Presses: \(count) · Hold time unavailable") }
        let seconds = (activity[key]?.heldSeconds ?? 0)
            .formatted(.number.precision(.fractionLength(2)).locale(reportLocale))
        return String(localized: "Presses: \(count) · Held: \(seconds) s")
    }
}

private nonisolated struct PawReportImage: Identifiable, Transferable, FileDocument {
    let data: Data
    let id = UUID()

    static var readableContentTypes: [UTType] { [.png] }
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
            .suggestedFileName("cat-is-coming.png")
    }

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct PawSharePreview: View {
    let report: PawReportImage
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var saveFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Share the Paw Prints")
                .font(.title3.bold())
            if let image = NSImage(data: report.data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Preview of the keyboard activity image")
            }
            HStack {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save PNG…") { saving = true }
                ShareLink(item: report, preview: SharePreview("Paws on the Keyboard")) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 680)
        .fileExporter(isPresented: $saving, document: report, contentType: .png,
                      defaultFilename: "cat-is-coming") { result in
            if case .failure = result { saveFailed = true }
        }
        .alert("Couldn’t save the image.", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        }
    }
}

private enum HeatmapPalette {
    static let paper = Color(hex: 0xF8F4E9)
    static let ink = Color(hex: 0x232B22)
    static let muted = Color(hex: 0x4E5848)
    static let divider = Color(hex: 0xDAD8C9)
    static let sage = Color(hex: 0xDCE3D1)
    static let control = Color(hex: 0xCED8C4)
    static let neutralKey = Color(hex: 0xF5F2E7)
    static let heat = [Color(hex: 0xA6C194), Color(hex: 0xDBBF75), Color(hex: 0xCD8A60), Color(hex: 0xA74D3E)]

    static func keyFill(_ level: Int?) -> Color { level.map { heat[$0] } ?? neutralKey }
    static func legendInk(_ level: Int?) -> Color { level == heat.count - 1 ? paper : ink }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 255) / 255,
            green: Double((hex >> 8) & 255) / 255,
            blue: Double(hex & 255) / 255
        )
    }
}

private struct HeatmapKeyStyle: ButtonStyle {
    let level: Int?
    let selected: Bool
    let returnInset: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        keyFace(configuration.label, pressed: configuration.isPressed)
    }

    func keyFace(_ label: some View, pressed: Bool) -> some View {
        let shape = HeatmapKeyShape(inset: returnInset)
        return label
            .background {
                shape.fill(HeatmapPalette.ink.opacity(0.17)).offset(y: 1.5)
                shape.fill(HeatmapPalette.keyFill(level))
                    .offset(y: pressed ? 1 : 0)
            }
            .overlay {
                if selected {
                    shape.stroke(HeatmapPalette.ink, lineWidth: 1.4)
                }
            }
    }
}

private struct HeatmapKeyShape: Shape {
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        guard inset > 0 else { return RoundedRectangle(cornerRadius: 5).path(in: rect) }

        let corner: CGFloat = 5
        let notchX = rect.minX + inset
        let notchY = rect.midY - 2
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + corner, y: rect.minY))
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                        tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: corner)
            path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                        tangent2End: CGPoint(x: notchX, y: rect.maxY), radius: corner)
            path.addArc(tangent1End: CGPoint(x: notchX, y: rect.maxY),
                        tangent2End: CGPoint(x: notchX, y: notchY), radius: corner)
            path.addArc(tangent1End: CGPoint(x: notchX, y: notchY),
                        tangent2End: CGPoint(x: rect.minX, y: notchY), radius: 3)
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: notchY),
                        tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: 3)
            path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                        tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: corner)
            path.closeSubpath()
        }
    }
}

private struct HeatmapKeyboard {
    struct Key: Identifiable {
        let id: Int64
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        var returnInset: CGFloat = 0
    }

    static let width: CGFloat = 824
    static let height: CGFloat = 227
    let keys: [Key]
    let codes: Set<Int64>
    private let layout = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
    private let keyboardType = UInt32(LMGetKbdType())

    init() {
        let iso = KBGetLayoutType(Int16(LMGetKbdType())) == kKeyboardISO
        let unit: CGFloat = 55
        let gap: CGFloat = 5

        func regular(_ codes: [Int]) -> [(Int, CGFloat)] { codes.map { ($0, 1) } }

        func row(_ keys: [(Int, CGFloat)], at y: CGFloat, height: CGFloat = 33) -> [Key] {
            var x: CGFloat = 0
            return keys.map { code, units in
                let key = Key(id: Int64(code), x: x, y: y, width: units * unit - gap, height: height)
                x += units * unit
                return key
            }
        }

        var layoutKeys = row([(53, 1.5)] + regular([122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]), at: 0, height: 27)
        layoutKeys += row(regular([50, 18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24]) + [(51, 2)], at: 34)
        layoutKeys += row([(48, 1.5)] + regular([12, 13, 14, 15, 17, 16, 32, 34, 31, 35, 33, 30])
                          + (iso ? [] : [(42, 1.5)]), at: 74)
        layoutKeys += row([(57, 1.75)] + regular([0, 1, 2, 3, 5, 4, 38, 40, 37, 41, 39])
                          + (iso ? [(42, 1)] : [(36, 2.25)]), at: 114)
        if iso {
            layoutKeys.append(Key(id: 36, x: 13.5 * unit, y: 74, width: 1.5 * unit - gap, height: 73, returnInset: unit / 4))
        }
        layoutKeys += row([(56, iso ? 1.25 : 2.25)] + regular(iso ? [10, 6, 7, 8, 9, 11, 45, 46, 43, 47, 44] : [6, 7, 8, 9, 11, 45, 46, 43, 47, 44])
                          + [(60, 2.75)], at: 154)
        layoutKeys += row([(63, 1), (59, 1), (58, 1), (55, 1.25), (49, 4.5), (54, 1.25), (61, 1), (62, 1), (123, 1)], at: 194)
        layoutKeys += [
            Key(id: 126, x: 13 * unit, y: 194, width: unit - gap, height: 15),
            Key(id: 125, x: 13 * unit, y: 212, width: unit - gap, height: 15),
            Key(id: 124, x: 14 * unit, y: 194, width: unit - gap, height: 33),
        ]

        keys = layoutKeys
        codes = Set(layoutKeys.map(\.id))
    }

    func label(_ code: Int64) -> String {
        switch Int(code) {
        case 53: return String(localized: "Esc")
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 51: return "⌫"
        case 48: return "⇥"
        case 57: return "⇪"
        case 36: return "↩"
        case 56, 60: return "⇧"
        case 63: return "fn"
        case 59, 62: return "⌃"
        case 58, 61: return "⌥"
        case 55, 54: return "⌘"
        case 49: return String(localized: "Space")
        case 123: return "←"
        case 125: return "↓"
        case 126: return "↑"
        case 124: return "→"
        default: return character(for: code) ?? String(localized: "Key \(code)")
        }
    }

    private func character(for code: Int64) -> String? {
        guard let key = UInt16(exactly: code),
              let property = layout.flatMap({ TISGetInputSourceProperty($0, kTISPropertyUnicodeKeyLayoutData) }) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var state: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = UCKeyTranslate(
            layout, key, UInt16(kUCKeyActionDisplay), 0, keyboardType,
            OptionBits(kUCKeyTranslateNoDeadKeysMask), &state, characters.count, &length, &characters
        )
        guard status == noErr, length > 0,
              characters[0] >= 32, !(0xE000...0xF8FF).contains(characters[0]) else { return nil }
        return String(decoding: characters.prefix(length), as: UTF16.self).uppercased()
    }
}
