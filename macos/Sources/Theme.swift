import SwiftUI
import Combine

// MARK: - Design tokens

enum DS {
    static let bg = Color(red: 0.055, green: 0.055, blue: 0.062)
    static let bgRaised = Color(red: 0.085, green: 0.085, blue: 0.095)
    static let surface = Color.white.opacity(0.045)
    static let surfaceHover = Color.white.opacity(0.075)
    static let pill = Color(red: 0.16, green: 0.16, blue: 0.18)
    static let stroke = Color.white.opacity(0.08)
    static let accent = Color(red: 0.98, green: 0.55, blue: 0.08)

    static let ok = Color(red: 0.27, green: 0.82, blue: 0.47)
    static let warn = Color(red: 1.0, green: 0.66, blue: 0.20)
    static let bad = Color(red: 1.0, green: 0.38, blue: 0.38)
    static let info = Color(red: 0.36, green: 0.62, blue: 1.0)
    static let muted = Color.white.opacity(0.35)

    static let text1 = Color.white.opacity(0.93)
    static let text2 = Color.white.opacity(0.62)
    static let text3 = Color.white.opacity(0.38)

    static func stateColor(_ state: String?) -> Color {
        switch state {
        case "ok": return ok
        case "warn": return warn
        case nil: return muted
        default: return bad
        }
    }
}

// MARK: - Task status vocabulary

enum TaskState {
    static let order = ["running", "pending", "awaiting_approval", "approved", "failed", "done", "rejected"]

    static func label(_ s: String) -> String {
        switch s {
        case "pending": return "Sırada"
        case "running": return "Çalışıyor"
        case "awaiting_approval": return "Onay bekliyor"
        case "approved": return "Onaylandı"
        case "done": return "Tamamlandı"
        case "failed": return "Hata"
        case "rejected": return "Reddedildi"
        default: return s
        }
    }

    static func color(_ s: String) -> Color {
        switch s {
        case "pending": return DS.muted
        case "running": return DS.info
        case "awaiting_approval": return DS.warn
        case "approved": return Color(red: 0.30, green: 0.80, blue: 0.85)
        case "done": return DS.ok
        case "failed": return DS.bad
        default: return DS.muted
        }
    }

    static func icon(_ s: String) -> String {
        switch s {
        case "pending": return "clock"
        case "running": return "bolt.fill"
        case "awaiting_approval": return "hand.raised.fill"
        case "approved": return "checkmark.seal"
        case "done": return "checkmark.circle.fill"
        case "failed": return "exclamationmark.triangle.fill"
        case "rejected": return "xmark.circle"
        default: return "circle"
        }
    }

    static func canRetry(_ s: String) -> Bool { ["done", "failed", "rejected"].contains(s) }
}

// MARK: - Small components

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 7
    var pulse = false
    @State private var on = false

    var body: some View {
        ZStack {
            if pulse {
                Circle().fill(color.opacity(0.35))
                    .frame(width: size * 2.2, height: size * 2.2)
                    .scaleEffect(on ? 1 : 0.4)
                    .opacity(on ? 0 : 1)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: on)
            }
            Circle().fill(color).frame(width: size, height: size)
        }
        .frame(width: size * 2.2, height: size * 2.2)
        .onAppear { on = true }
    }
}

struct StatusBadge: View {
    let status: String
    var compact = false

    var body: some View {
        let c = TaskState.color(status)
        HStack(spacing: 4) {
            Image(systemName: TaskState.icon(status)).font(.system(size: compact ? 8.5 : 9.5, weight: .bold))
            if !compact { Text(TaskState.label(status)) }
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(c)
        .padding(.horizontal, compact ? 5 : 8)
        .padding(.vertical, 3)
        .background(c.opacity(0.14), in: Capsule())
        .help(TaskState.label(status))
    }
}

struct Chip: View {
    let text: String
    var color: Color = DS.text2
    var filled = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(filled ? Color.black.opacity(0.85) : color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(filled ? color : DS.pill, in: Capsule())
    }
}

struct CircleIconButton: View {
    let systemName: String
    var badge = 0
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(hover ? DS.surfaceHover.opacity(2.4) : DS.pill)
                    .overlay { Circle().stroke(DS.stroke, lineWidth: 1) }
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: systemName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DS.text1)
                    }
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 17, minHeight: 17)
                        .background(DS.warn, in: Capsule())
                        .offset(x: 4, y: -3)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DS.text3)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.text1)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

// Ajan cevaplarındaki başlık, madde, ayraç, **kalın**, `kod` ve bağlantılar düz metin gibi görünmesin.
// Text tam Markdown'da satır sonlarını yuttuğu için bloklar satır satır çizilir.
struct MarkdownText: View {
    let text: String
    var size: CGFloat = 13
    var color: Color = DS.text1

    private enum Block {
        case heading(String), bullet(String, Int), rule, paragraph(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let s):
                    Text(Self.inline(s))
                        .font(.system(size: size + 0.5, weight: .bold))
                        .padding(.top, 3)
                case .bullet(let s, let indent):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(indent > 0 ? "◦" : "•").foregroundStyle(DS.text3)
                        Text(Self.inline(s))
                    }
                    .padding(.leading, CGFloat(indent) * 12)
                case .rule:
                    Rectangle().fill(DS.stroke).frame(height: 1).padding(.vertical, 3)
                case .paragraph(let s):
                    Text(Self.inline(s))
                }
            }
        }
        .font(.system(size: size))
        .foregroundStyle(color)
        .lineSpacing(2)
        .tint(DS.accent)
    }

    private static func blocks(_ s: String) -> [Block] {
        var out: [Block] = []
        var para: [String] = []
        func flush() {
            if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para = [] }
        }
        for raw in s.components(separatedBy: "\n") {
            let indent = raw.prefix { $0 == " " }.count / 2
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }) && line.count >= 3 { flush(); out.append(.rule); continue }
            if line.hasPrefix("#") {
                flush()
                out.append(.heading(String(line.drop { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if line.hasPrefix("* ") || line.hasPrefix("- ") || line.hasPrefix("• ") {
                flush()
                out.append(.bullet(String(line.dropFirst(2)), indent))
                continue
            }
            para.append(line)
        }
        flush()
        return out
    }

    static func inline(_ s: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }

    // Tek satırlık önizlemeler için işaretleri temizle
    static func plain(_ s: String) -> String {
        String(inline(s).characters)
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 14
    var accent: Color? = nil

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DS.stroke, lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                if let accent {
                    RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 3).padding(.vertical, 10)
                }
            }
    }
}

extension View {
    func card(padding: CGFloat = 14, accent: Color? = nil) -> some View {
        modifier(CardStyle(padding: padding, accent: accent))
    }
}

struct TypingDots: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(DS.text2)
                    .frame(width: 6, height: 6)
                    .opacity(phase == i ? 1 : 0.3)
            }
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}
