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

struct AppConfig: Codable {
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
        CommandConfig(title: "Yeni arka plan görevi ekle",
                      command: "duffy add \"Gelen kutusunu özetle\" -c general",
                      desc: "Görev sıraya girer, Duffy sen yokken çalışır ve sonucu bildirir."),
        CommandConfig(title: "Görevleri listele", command: "duffy list",
                      desc: "Bekleyen, çalışan ve biten görevleri terminalde gösterir."),
        CommandConfig(title: "Görev raporunu gör", command: "duffy show 1",
                      desc: "1 numaralı görevin ürettiği raporu ve onay komutunu basar."),
        CommandConfig(title: "Onayla ya da reddet", command: "duffy approve 1   |   duffy reject 1",
                      desc: "Onay bekleyen riskli adımı çalıştırır ya da iptal eder."),
        CommandConfig(title: "Arka plan servisini başlat", command: "duffy daemon",
                      desc: "Kuyruğu işleyen ve bu uygulamaya API sunan servisi açar."),
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

    static let defaultSuggestions = ["Kısa bir durum özeti ver", "Bugün neye odaklanmalıyım?", "Son görevin sonucunu anlat"]

    init(_ p: PersonaConfig, index: Int) {
        id = p.id
        name = p.name
        roleTag = p.role ?? "Asistan"
        color = p.color.flatMap(Color.init(hex:)) ?? Self.palette[index % Self.palette.count]
        shapeType = p.shape ?? (index % 3)
        greeting = p.greeting ?? "Merhaba, \(p.name) burada. Soru sorabilir ya da arka plan görevi verebilirsin."
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
