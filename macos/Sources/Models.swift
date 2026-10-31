import Foundation

// Duffy sunucusunun iki sürümü farklı alan adları kullanıyor (result / result_summary,
// approval_summary / approval_Action); ikisini de kabul et.
private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private extension KeyedDecodingContainer where K == AnyKey {
    func first<T: Decodable>(_ type: T.Type, _ keys: String...) -> T? {
        for k in keys {
            if let v = try? decodeIfPresent(T.self, forKey: AnyKey(k)) { return v }
        }
        return nil
    }
}

struct DuffyTask: Decodable, Identifiable, Equatable {
    let id: Int
    let title: String
    let category: String
    let status: String
    let modelUsed: String?
    let resultSummary: String?
    let approvalAction: String?
    let approvalCmd: String?
    let createdAt: String?
    let updatedAt: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = try c.decode(Int.self, forKey: AnyKey("id"))
        title = c.first(String.self, "title") ?? ""
        category = c.first(String.self, "category") ?? "general"
        status = c.first(String.self, "status") ?? "pending"
        modelUsed = c.first(String.self, "model_used")
        resultSummary = c.first(String.self, "result_summary", "result")
        approvalAction = c.first(String.self, "approval_Action", "approval_action", "approval_summary")
        approvalCmd = c.first(String.self, "approval_cmd")
        createdAt = c.first(String.self, "created_at")
        updatedAt = c.first(String.self, "updated_at")
    }

    var created: Date? { Fmt.parse(createdAt) }
    var lastActivity: Date? { Fmt.parse(updatedAt) ?? created }
}

struct DuffyChatMsg: Decodable, Identifiable, Equatable {
    let id: Int
    let agentId: String
    let sender: String
    let message: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, sender, message
        case agentId = "agent_id"
        case createdAt = "created_at"
    }

    var date: Date? { Fmt.parse(createdAt) }
    var isUser: Bool { sender == "user" }
}

struct DuffyAPIResponse: Decodable {
    let status: String
    let tasks: [DuffyTask]
    let chats: [DuffyChatMsg]?
    let agents: [String: String]?
    let version: String?
}

// Ofis paneli değerleri string, sayı ya da bool olabilir
struct FlexText: Decodable {
    let text: String

    init(text: String) { self.text = text }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { text = "—" }
        else if let s = try? c.decode(String.self) { text = s }
        else if let i = try? c.decode(Int.self) { text = String(i) }
        else if let d = try? c.decode(Double.self) { text = String(d) }
        else if let b = try? c.decode(Bool.self) { text = b ? L("evet", "yes") : L("hayır", "no") }
        else { text = "—" }
    }
}

struct OfficeAgent: Decodable, Identifiable {
    let id: String
    let name: String
    let role: String
    let state: String
    let facts: [String: FlexText]

    init(id: String, name: String, role: String, state: String, facts: [String: String]) {
        self.id = id
        self.name = name
        self.role = role
        self.state = state
        self.facts = facts.mapValues { FlexText(text: $0) }
    }

    var isOK: Bool { state == "ok" }
    var severity: Int { state == "ok" ? 2 : (state == "warn" ? 1 : 0) }
}

struct OfficeService: Decodable, Identifiable {
    let label: String
    let pid: Int?
    let lastExit: String

    var id: String { label }
    var running: Bool { pid != nil }

    enum CodingKeys: String, CodingKey {
        case label, pid
        case lastExit = "last_exit"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        pid = try? c.decodeIfPresent(Int.self, forKey: .pid)
        lastExit = (try? c.decode(FlexText.self, forKey: .lastExit).text) ?? "—"
    }
}

// İki ofis sürümü var: kart listesi döndüren ("agents": [...]) ve repodaki office.py
// ("agents": {id: ad}, "health": [{name, ok, ms}], "duffy_online"). İkisinden de kart üret.
struct OfficeSnapshot: Decodable {
    let agents: [OfficeAgent]
    let services: [OfficeService]

    private struct HealthCheck: Decodable {
        let name: String
        let ok: Bool
        let ms: Int?
    }

    private enum CodingKeys: String, CodingKey {
        case agents, office, services, health
        case duffyOnline = "duffy_online"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        services = (try? c.decode([OfficeService].self, forKey: .services)) ?? []
        if let cards = try? c.decode([OfficeAgent].self, forKey: .agents) {
            agents = cards
            return
        }
        if let cards = try? c.decode([OfficeAgent].self, forKey: .office) {
            agents = cards
            return
        }
        var cards: [OfficeAgent] = []
        if let online = try? c.decode(Bool.self, forKey: .duffyOnline) {
            cards.append(OfficeAgent(id: "duffy", name: "Duffy", role: L("Görev kuyruğu", "Task queue"),
                                     state: online ? "ok" : "down", facts: [L("durum", "status"): online ? L("çevrimiçi", "online") : L("ulaşılamıyor", "unreachable")]))
        }
        for h in (try? c.decode([HealthCheck].self, forKey: .health)) ?? [] {
            cards.append(OfficeAgent(id: "health:\(h.name)", name: h.name, role: L("HTTP sağlık kontrolü", "HTTP health check"),
                                     state: h.ok ? "ok" : "down",
                                     facts: [L("durum", "status"): h.ok ? L("yanıt veriyor", "responding") : L("yanıt yok", "not responding"), L("süre", "response"): h.ms.map { "\($0) ms" } ?? "—"]))
        }
        agents = cards
    }
}

enum Fmt {
    private static let api: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: L("tr_TR", "en_US"))
        f.dateFormat = format
        return f
    }

    static func parse(_ s: String?) -> Date? {
        guard let s, s.count >= 19 else { return nil }
        return api.date(from: String(s.prefix(19)).replacingOccurrences(of: "T", with: " "))
    }

    static func time(_ d: Date) -> String { formatter("HH:mm").string(from: d) }
    static func clock(_ d: Date) -> String { formatter("HH:mm:ss").string(from: d) }

    // Bugünse saat, dünse "dün", daha eskiyse "25 Eki": eski mesaj bugünkü gibi görünmesin
    static func relative(_ d: Date?) -> String {
        guard let d else { return "—" }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return time(d) }
        if cal.isDateInYesterday(d) { return L("dün", "yesterday") }
        return formatter("d MMM").string(from: d)
    }

    static func day(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return L("Bugün", "Today") }
        if cal.isDateInYesterday(d) { return L("Dün", "Yesterday") }
        return formatter(L("d MMMM EEEE", "EEEE, d MMMM")).string(from: d)
    }

    // "2026-10-31T10:48:27.04+01:00" gibi ham zaman damgalarını "bugün 10:48" yap
    static func humanize(_ s: String) -> String {
        guard s.count >= 19, s.dropFirst(10).first == "T" || s.dropFirst(10).first == " " else { return s }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = iso.date(from: s) ?? ISO8601DateFormatter().date(from: s) ?? parse(s)
        guard let d else { return s }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return L("bugün \(time(d))", "today \(time(d))") }
        if cal.isDateInYesterday(d) { return L("dün \(time(d))", "yesterday \(time(d))") }
        if cal.isDateInTomorrow(d) { return L("yarın \(time(d))", "tomorrow \(time(d))") }
        return formatter("d MMM HH:mm").string(from: d)
    }

    static func ago(_ d: Date?) -> String {
        guard let d else { return L("hiç", "never") }
        let s = Int(Date().timeIntervalSince(d))
        if s < 60 { return L("az önce", "just now") }
        if s < 3600 { return L("\(s / 60) dk önce", "\(s / 60) min ago") }
        if s < 86_400 { return L("\(s / 3600) sa önce", "\(s / 3600) h ago") }
        return relative(d)
    }
}
