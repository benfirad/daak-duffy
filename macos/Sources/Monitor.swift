import SwiftUI

enum ConsoleSection: String, CaseIterable, Identifiable {
    case overview, tasks, approvals, office, services, commands
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return L("Genel Bakış", "Overview")
        case .tasks: return L("Görevler", "Tasks")
        case .approvals: return L("Onaylar", "Approvals")
        case .office: return L("Ajan Ofisi", "Agent Office")
        case .services: return L("Servisler", "Services")
        case .commands: return L("Komutlar", "Commands")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.33percent"
        case .tasks: return "list.bullet.rectangle"
        case .approvals: return "checkmark.shield"
        case .office: return "building.2"
        case .services: return "server.rack"
        case .commands: return "terminal"
        }
    }
}

@MainActor
final class DuffyMonitor: ObservableObject {
    // Bağlantı
    @Published var online = false
    @Published var lastSync: Date?
    @Published var officeOnline = false
    @Published var officeSync: Date?

    // Veri
    @Published var tasks: [DuffyTask] = []
    @Published var chats: [DuffyChatMsg] = []
    @Published var serverAgents: [String: String] = [:]
    @Published var officeAgents: [OfficeAgent] = []
    @Published var officeServices: [OfficeService] = []

    // Arayüz durumu
    @Published var activeAgent: AgentCharacter?
    @Published var showQuickTask = false
    @Published var chatInput = ""
    @Published var waitingFor: String?
    @Published var newTaskTitle = ""
    @Published var newTaskCat = ""
    @Published var toast: String?
    @Published var section: ConsoleSection = .overview
    @Published var taskStatusFilter = "all"
    @Published var taskAgentFilter: String?
    @Published var taskSearch = ""

    var openConsoleCallback: (() -> Void)?

    let config: AppConfig
    let chief: AgentCharacter
    private let configuredAgents: [AgentCharacter]?
    private let hosts: [String]
    private var hostIndex = 0
    private var timer: Timer?
    private var officeTimer: Timer?
    private var waitingSince: Date?

    init(config: AppConfig = .load()) {
        self.config = config
        let h = (config.hosts ?? ["127.0.0.1"]).map {
            $0.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "")
        }
        hosts = h.isEmpty ? ["127.0.0.1"] : h
        chief = AgentCharacter(
            config.chief ?? PersonaConfig(
                id: "duffy", name: "Duffy", role: L("Baş otonom işçi", "Background worker"),
                greeting: L("7/24 nöbetteyim. Bana doğrudan yazabilir ya da arka plan görevi verebilirsin.", "I'm on duty around the clock. Message me directly or hand me a background task."),
                office: ["duffy"]
            ),
            index: 5
        )
        configuredAgents = config.agents.map { list in list.enumerated().map { AgentCharacter($1, index: $0) } }
        newTaskCat = chief.id

        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        // Ofis özeti launchctl/SQLite okur; 15 sn yeterli
        Task { await refreshOffice() }
        officeTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshOffice() }
        }
    }

    // MARK: Hosts

    private var activeHost: String { hosts[hostIndex % hosts.count] }
    private var baseURL: String { "http://\(activeHost):\(config.duffyPort ?? 8899)" }
    private var officeURL: String { "http://\(activeHost):\(config.officePort ?? 8900)" }
    var hostLabel: String { config.hostLabel ?? "Duffy" }
    var linkLabel: String { config.linkLabels?[activeHost] ?? activeHost }

    // Evde kablo, dışarıda VPN gibi birden çok yol varsa çalışmayanda takılı kalma
    private func switchHost() { hostIndex = (hostIndex + 1) % hosts.count }

    // MARK: Characters

    var agents: [AgentCharacter] {
        if let configuredAgents { return configuredAgents }
        return serverAgents.keys.sorted().filter { $0 != chief.id }.enumerated().map { i, key in
            AgentCharacter(PersonaConfig(id: key, name: serverAgents[key] ?? key), index: i)
        }
    }

    var allCharacters: [AgentCharacter] { [chief] + agents }

    func character(for id: String) -> AgentCharacter? {
        allCharacters.first { $0.id.lowercased() == id.lowercased() }
    }

    func displayName(forCategory c: String) -> String { character(for: c)?.name ?? c }

    // MARK: Derived state

    var pendingApprovals: [DuffyTask] { tasks.filter { $0.status == "awaiting_approval" } }
    var activeTasks: [DuffyTask] { tasks.filter { $0.status == "running" || $0.status == "pending" || $0.status == "approved" } }
    var officeProblems: [OfficeAgent] { officeAgents.filter { !$0.isOK }.sorted { $0.severity < $1.severity } }

    var overallState: String {
        if !online { return "down" }
        if !pendingApprovals.isEmpty || !officeProblems.isEmpty { return "warn" }
        return "ok"
    }

    func officeLinks(for agent: AgentCharacter) -> [OfficeAgent] { officeAgents.filter(agent.matches) }

    func liveState(for agent: AgentCharacter) -> String? {
        let linked = officeLinks(for: agent)
        if linked.isEmpty { return nil }
        return linked.min { $0.severity < $1.severity }?.state
    }

    func liveSummary(for agent: AgentCharacter) -> String? {
        let linked = officeLinks(for: agent).sorted { $0.severity < $1.severity }
        if linked.isEmpty { return nil }
        return linked.map { a in
            let detail = ["hata", "hue", L("durum", "status"), "son", "son çalışma"]
                .compactMap { a.facts[$0]?.text }
                .first { !$0.isEmpty && $0 != "—" && $0 != "-" }
            return "\(a.name): \(detail ?? (a.isOK ? L("çalışıyor", "running") : a.state))"
        }.joined(separator: " · ")
    }

    func messages(for agent: AgentCharacter) -> [DuffyChatMsg] { chats.filter { $0.agentId == agent.id } }
    func tasks(for agent: AgentCharacter) -> [DuffyTask] { tasks.filter { $0.category.lowercased() == agent.id.lowercased() } }

    struct Preview { let text: String; let time: String; let fromLive: Bool }

    func preview(for agent: AgentCharacter) -> Preview {
        var candidates: [(text: String, date: Date)] = []
        if let m = messages(for: agent).last, let d = m.date { candidates.append((m.message, d)) }
        if let t = tasks(for: agent).first, let d = t.lastActivity {
            candidates.append(("\(TaskState.label(t.status)): \(t.resultSummary ?? t.title)", d))
        }
        let newest = candidates.max { $0.date < $1.date }
        // Son konuşma bir günden eskiyse canlı servis durumu daha anlamlı
        if let live = liveSummary(for: agent), newest.map({ Date().timeIntervalSince($0.date) > 86_400 }) ?? true {
            return Preview(text: live, time: officeSync.map(Fmt.time) ?? L("canlı", "live"), fromLive: true)
        }
        if let newest {
            return Preview(text: MarkdownText.plain(newest.text), time: Fmt.relative(newest.date), fromLive: false)
        }
        return Preview(text: L("Henüz konuşma yok, yazarak başlayabilirsin", "No messages yet. Say hi to get started"), time: "", fromLive: false)
    }

    var filteredTasks: [DuffyTask] {
        let q = taskSearch.trimmingCharacters(in: .whitespaces).lowercased()
        return tasks.filter { t in
            (taskStatusFilter == "all" || t.status == taskStatusFilter
                || (taskStatusFilter == "active" && ["running", "pending", "approved"].contains(t.status)))
                && (taskAgentFilter == nil || t.category.lowercased() == taskAgentFilter)
                && (q.isEmpty || t.title.lowercased().contains(q) || (t.resultSummary ?? "").lowercased().contains(q) || "#\(t.id)" == q)
        }
    }

    // MARK: Navigation

    func openConsole(_ s: ConsoleSection? = nil, agentFilter: String? = nil) {
        if let s { section = s }
        if s == .tasks {
            taskAgentFilter = agentFilter
            taskStatusFilter = "all"
        }
        openConsoleCallback?()
    }

    // MARK: Networking

    func refresh() async {
        guard let url = URL(string: "\(baseURL)/api/status") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                let decoded = try JSONDecoder().decode(DuffyAPIResponse.self, from: data)
                if decoded.tasks != tasks { tasks = decoded.tasks }
                let newChats = decoded.chats ?? []
                if newChats != chats { chats = newChats }
                if let a = decoded.agents, a != serverAgents { serverAgents = a }
                if let w = waitingFor,
                   let last = chats.last(where: { $0.agentId == w }), !last.isUser,
                   let d = last.date, let since = waitingSince, d >= since.addingTimeInterval(-90) {
                    waitingFor = nil
                }
                if let since = waitingSince, Date().timeIntervalSince(since) > 180 { waitingFor = nil }
                online = true
                lastSync = Date()
                return
            }
        } catch {}
        online = false
        switchHost()
    }

    func refreshOffice() async {
        guard let url = URL(string: "\(officeURL)/api/office") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                let snap = try JSONDecoder().decode(OfficeSnapshot.self, from: data)
                officeAgents = snap.agents
                officeServices = snap.services
                officeOnline = true
                officeSync = Date()
                return
            }
        } catch {}
        officeOnline = false
    }

    private func post(_ path: String, _ items: [URLQueryItem]) async -> Bool {
        guard let url = URL(string: "\(baseURL)/\(path)") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        var comps = URLComponents()
        comps.queryItems = items
        req.httpBody = comps.percentEncodedQuery?.data(using: .utf8)
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return ((resp as? HTTPURLResponse)?.statusCode ?? 500) < 400
        } catch {
            return false
        }
    }

    func sendChat(to agent: AgentCharacter, text: String? = nil) async {
        let msg = (text ?? chatInput).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { return }
        if text == nil { chatInput = "" }
        waitingFor = agent.id
        waitingSince = Date()
        if await post("chat", [URLQueryItem(name: "agent_id", value: agent.id), URLQueryItem(name: "message", value: msg)]) {
            await refresh()
        } else {
            waitingFor = nil
            if text == nil { chatInput = msg }
            showToast(L("Mesaj gönderilemedi", "Message could not be sent"))
        }
    }

    func addTask(title: String, category: String) async -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let ok = await post("add", [URLQueryItem(name: "title", value: trimmed), URLQueryItem(name: "category", value: category)])
        showToast(ok ? L("Görev kuyruğa eklendi", "Task queued") : L("Görev eklenemedi", "Could not queue the task"))
        if ok { await refresh() }
        return ok
    }

    func taskAction(_ endpoint: String, id: Int, label: String) async {
        let ok = await post(endpoint, [URLQueryItem(name: "id", value: String(id))])
        showToast(ok ? label : L("İşlem başarısız", "Action failed"))
        if ok { await refresh() }
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showToast(L("Panoya kopyalandı", "Copied to clipboard"))
    }

    func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if toast == text { withAnimation { toast = nil } }
        }
    }
}
