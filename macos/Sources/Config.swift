import SwiftUI

// Kişisel karakterler, sunucu adresleri ve komutlar koda değil ~/.duffy/app.json dosyasına yazılır.
// Dosya yoksa uygulama yerel Duffy sunucusuna (127.0.0.1) bağlanır ve karakterleri sunucudan alır.

struct PersonaConfig: Codable {
    let id: String
    let name: String
    var role: String?
    var color: String?
    var shape: Int?
    var greeting: String?
    var suggestions: [String]?
    // Ofis panelindeki eşleşen kayıtlar: "health" gibi kimlik ya da "name:email" gibi ad parçası
    var office: [String]?
}

struct CommandConfig: Codable, Identifiable {
    let title: String
    let command: String
    var desc: String?
    var id: String { title }
}

// Arayüz dili: ayar dosyasındaki "language" ("tr" / "en"), yoksa sistem dili; Türkçe değilse İngilizce
enum Lang {
    static let english: Bool = {
        let code = AppConfig.load().language ?? Locale.preferredLanguages.first ?? "en"
        return !code.lowercased().hasPrefix("tr")
    }()
}

func L(_ tr: String, _ en: String) -> String { Lang.english ? en : tr }

// Türkçede sayıdan sonra tekil kalır; İngilizcede 1 dışında çoğul eki gerekir
func plural(_ n: Int, _ word: String) -> String { n == 1 ? "1 \(word)" : "\(n) \(word)s" }

struct AppConfig: Codable {
    var language: String?
    var hosts: [String]?
    var duffyPort: Int?
    var officePort: Int?
    var hostLabel: String?
    var linkLabels: [String: String]?
    var chief: PersonaConfig?
    var agents: [PersonaConfig]?
    var commands: [CommandConfig]?

    static var path: String {
        ProcessInfo.processInfo.environment["DUFFY_APP_CONFIG"]
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".duffy/app.json")
    }

    static func load() -> AppConfig {
        guard let data = FileManager.default.contents(atPath: path) else { return AppConfig() }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            FileHandle.standardError.write("app.json okunamadı: \(error)\n".data(using: .utf8)!)
            return AppConfig()
        }
    }

    static let defaultCommands: [CommandConfig] = [
        CommandConfig(title: L("Yeni arka plan görevi ekle", "Queue a background task"),
                      command: L("duffy add \"Gelen kutusunu özetle\" -c general", "duffy add \"Summarise my inbox\" -c general"),
                      desc: L("Görev sıraya girer, Duffy sen yokken çalışır ve sonucu bildirir.", "The task is queued; Duffy works on it while you're away and reports back.")),
        CommandConfig(title: L("Görevleri listele", "List tasks"), command: "duffy list",
                      desc: L("Bekleyen, çalışan ve biten görevleri terminalde gösterir.", "Shows queued, running and finished tasks in the terminal.")),
        CommandConfig(title: L("Görev raporunu gör", "Show a task's report"), command: "duffy show 1",
                      desc: L("1 numaralı görevin ürettiği raporu ve onay komutunu basar.", "Prints task 1's report and any command waiting for approval.")),
        CommandConfig(title: L("Onayla ya da reddet", "Approve or reject"), command: "duffy approve 1   |   duffy reject 1",
                      desc: L("Onay bekleyen riskli adımı çalıştırır ya da iptal eder.", "Runs or cancels the risky step that is waiting for you.")),
        CommandConfig(title: L("Arka plan servisini başlat", "Start the background service"), command: "duffy daemon",
                      desc: L("Kuyruğu işleyen ve bu uygulamaya API sunan servisi açar.", "Starts the worker that processes the queue and serves this app.")),
    ]
}

struct AgentCharacter: Identifiable, Equatable {
    let id: String
    let name: String
    let roleTag: String
    let color: Color
    let shapeType: Int // 0: yuvarlak, 1: yumuşak kare, 2: köşeli
    let greeting: String
    let suggestions: [String]
    let officeRules: [String]

    static func == (a: AgentCharacter, b: AgentCharacter) -> Bool { a.id == b.id }

    static let palette: [Color] = [
        Color(red: 0.96, green: 0.18, blue: 0.28), Color(red: 0.95, green: 0.20, blue: 0.62),
        Color(red: 0.12, green: 0.48, blue: 0.98), Color(red: 0.99, green: 0.78, blue: 0.12),
        Color(red: 0.14, green: 0.74, blue: 0.66), Color(red: 0.98, green: 0.62, blue: 0.08),
        Color(red: 0.12, green: 0.80, blue: 0.38), Color(red: 0.58, green: 0.40, blue: 0.98),
    ]

    static let defaultSuggestions = [L("Kısa bir durum özeti ver", "Give me a short status update"), L("Bugün neye odaklanmalıyım?", "What should I focus on today?"), L("Son görevin sonucunu anlat", "How did your last task go?")]

    init(_ p: PersonaConfig, index: Int) {
        id = p.id
        name = p.name
        roleTag = p.role ?? L("Asistan", "Assistant")
        color = p.color.flatMap(Color.init(hex:)) ?? Self.palette[index % Self.palette.count]
        shapeType = p.shape ?? (index % 3)
        greeting = p.greeting ?? L("Merhaba, \(p.name) burada. Soru sorabilir ya da arka plan görevi verebilirsin.", "Hi, \(p.name) here. Ask me something or hand me a background task.")
        suggestions = p.suggestions ?? Self.defaultSuggestions
        officeRules = p.office ?? []
    }

    func matches(_ office: OfficeAgent) -> Bool {
        officeRules.contains { rule in
            if rule.hasPrefix("name:") {
                return office.name.lowercased().contains(rule.dropFirst(5).lowercased())
            }
            return office.id == rule
        }
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
