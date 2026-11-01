import SwiftUI

// Ayrıntılı konsol penceresi: kenar çubuğu + bölümler
struct ConsoleView: View {
    @EnvironmentObject var monitor: DuffyMonitor

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { monitor.section }, set: { if let s = $0 { monitor.section = s } })) {
                Section {
                    ForEach(monitor.visibleSections) { s in
                        Label(s.title, systemImage: s.icon)
                            .badge(badge(for: s))
                            .tag(s)
                    }
                }
                Section(L("Bağlantı", "Connection")) {
                    connectionRow
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            ZStack {
                DS.bg.ignoresSafeArea()
                switch monitor.section {
                case .overview: OverviewSection()
                case .tasks: TasksSection()
                case .approvals: ApprovalsSection()
                case .office: OfficeSection()
                case .services: ServicesSection()
                case .commands: CommandsSection()
                case .expenses:
                    if let url = monitor.kasaURL { WebPanel(url: url) } else { EmptyView() }
                }
            }
            .navigationTitle(monitor.section.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await monitor.refresh()
                            await monitor.refreshOffice()
                        }
                    } label: {
                        Label(L("Yenile", "Refresh"), systemImage: "arrow.clockwise")
                    }
                    .help(L("Şimdi yenile (⌘R)", "Refresh now (⌘R)"))
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = monitor.toast {
                Text(toast)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(DS.bgRaised, in: Capsule())
                    .overlay { Capsule().stroke(DS.stroke) }
                    .padding(.bottom, 20)
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 900, minHeight: 580)
        .preferredColorScheme(.dark)
    }

    private func badge(for s: ConsoleSection) -> Int {
        switch s {
        case .approvals: return monitor.pendingApprovals.count
        case .tasks: return monitor.activeTasks.count
        case .office: return monitor.officeProblems.count
        default: return 0
        }
    }

    private var connectionRow: some View {
        HStack(spacing: 6) {
            StatusDot(color: monitor.online ? DS.ok : DS.bad, size: 6, pulse: monitor.online)
            VStack(alignment: .leading, spacing: 1) {
                Text(monitor.online ? "\(monitor.hostLabel) · \(monitor.linkLabel)" : L("\(monitor.hostLabel) çevrimdışı", "\(monitor.hostLabel) offline"))
                    .font(.system(size: 11.5, weight: .medium))
                Text(monitor.lastSync.map { L("güncel \(Fmt.clock($0))", "updated \(Fmt.clock($0))") } ?? L("bağlanıyor…", "connecting…"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Shared pieces

private struct SectionScroll<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(22)
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
    }
}

private struct SectionTitle: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(DS.text3)
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 11)).foregroundStyle(DS.text3)
            }
        }
        .padding(.top, 6)
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color
    var action: (() -> Void)? = nil
    @State private var hover = false

    var body: some View {
        Button { action?() } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                    Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(DS.text2).lineLimit(1)
                    Spacer()
                }
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.text1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.text3)
                    .lineLimit(1)
            }
            .card()
            .background(hover && action != nil ? DS.surface : .clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(action != nil)
        .onHover { hover = $0 }
    }
}

// MARK: - Overview

private struct OverviewSection: View {
    @EnvironmentObject var monitor: DuffyMonitor

    var body: some View {
        let done = monitor.tasks.filter { $0.status == "done" }.count
        let failed = monitor.tasks.filter { $0.status == "failed" }.count
        SectionScroll {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                StatTile(title: L("Bağlantı", "Connection"), value: monitor.online ? L("Çevrimiçi", "Online") : L("Kopuk", "Offline"),
                         detail: monitor.online ? "\(monitor.hostLabel) · \(monitor.linkLabel)" : L("Tüm adresler denendi", "Tried every address"),
                         icon: "antenna.radiowaves.left.and.right", tint: monitor.online ? DS.ok : DS.bad)
                StatTile(title: L("Süren görevler", "Running tasks"), value: "\(monitor.activeTasks.count)",
                         detail: L("\(done) tamamlandı · \(failed) hata", "\(done) done · \(failed) failed"),
                         icon: "bolt.fill", tint: DS.info) { monitor.openConsole(.tasks) }
                StatTile(title: L("Onay bekleyen", "Awaiting you"), value: "\(monitor.pendingApprovals.count)",
                         detail: monitor.pendingApprovals.isEmpty ? L("Bekleyen işlem yok", "Nothing waiting") : L("Senin kararını bekliyor", "Needs your decision"),
                         icon: "hand.raised.fill", tint: monitor.pendingApprovals.isEmpty ? DS.ok : DS.warn) { monitor.section = .approvals }
                StatTile(title: L("Servis uyarısı", "Service warnings"), value: "\(monitor.officeProblems.count)",
                         detail: monitor.officeOnline ? L("\(monitor.officeAgents.count) servis izleniyor", plural(monitor.officeAgents.count, "service") + " watched") : L("Ofis paneline ulaşılamıyor", "Office panel unreachable"),
                         icon: "exclamationmark.triangle.fill",
                         tint: monitor.officeProblems.isEmpty ? DS.ok : DS.warn) { monitor.section = .office }
            }

            if let devices = monitor.config.devices, !devices.isEmpty {
                SectionTitle(title: L("Cihazlar", "Devices"))
                HStack(spacing: 8) {
                    ForEach(devices) { d in deviceChip(d.name, link: monitor.deviceLinks[d.name]) }
                    Spacer()
                }
            }

            SectionTitle(title: L("Dikkat gerektirenler", "Needs attention"))
            if monitor.pendingApprovals.isEmpty && monitor.officeProblems.isEmpty && monitor.online {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.ok)
                    Text(L("Her şey yolunda; onay bekleyen işlem ya da servis uyarısı yok.", "All good: nothing waiting for approval and no service warnings."))
                        .font(.system(size: 12.5))
                        .foregroundStyle(DS.text2)
                }
                .card()
            } else {
                VStack(spacing: 8) {
                    if !monitor.online {
                        attentionRow(icon: "wifi.slash", tint: DS.bad, title: L("\(monitor.hostLabel) sunucusuna ulaşılamıyor", "Can't reach \(monitor.hostLabel)"),
                                     detail: L("Ağ bağlantısını ya da Duffy servisini kontrol et", "Check the network or the Duffy service")) {}
                    }
                    ForEach(monitor.pendingApprovals) { t in
                        attentionRow(icon: "hand.raised.fill", tint: DS.warn, title: t.approvalAction ?? t.title,
                                     detail: L("#\(t.id) · \(monitor.displayName(forCategory: t.category)) · onay bekliyor", "#\(t.id) · \(monitor.displayName(forCategory: t.category)) · waiting for approval")) {
                            monitor.section = .approvals
                        }
                    }
                    ForEach(monitor.officeProblems) { a in
                        attentionRow(icon: "exclamationmark.triangle.fill", tint: DS.stateColor(a.state), title: a.name,
                                     detail: a.facts["hata"]?.text ?? a.facts["hue"]?.text ?? a.facts[L("durum", "status")]?.text ?? a.role) {
                            monitor.section = .office
                        }
                    }
                }
            }

            SectionTitle(title: L("Son görevler", "Recent tasks"), trailing: monitor.tasks.isEmpty ? nil : L("\(monitor.tasks.count) görev", plural(monitor.tasks.count, "task")))
            if monitor.tasks.isEmpty {
                EmptyState(icon: "tray", title: L("Henüz görev yok", "No tasks yet"), subtitle: L("Görevler sekmesinden ya da ana ekrandaki + ile ekleyebilirsin.", "Add one from Tasks or with + in the main window."))
            } else {
                VStack(spacing: 0) {
                    ForEach(monitor.tasks.prefix(6)) { t in
                        Button { monitor.openConsole(.tasks) } label: {
                            HStack(spacing: 10) {
                                StatusBadge(status: t.status, compact: true)
                                Text(t.title).font(.system(size: 12.5)).foregroundStyle(DS.text1).lineLimit(1)
                                Spacer()
                                Text(monitor.displayName(forCategory: t.category)).font(.system(size: 11)).foregroundStyle(DS.text3)
                                Text(Fmt.relative(t.lastActivity)).font(.system(size: 11)).foregroundStyle(DS.text3)
                                    .frame(width: 56, alignment: .trailing)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if t.id != monitor.tasks.prefix(6).last?.id { Divider().overlay(DS.stroke) }
                    }
                }
                .card(padding: 0)
            }
        }
    }

    private func deviceChip(_ name: String, link: String?) -> some View {
        let up = link.map { !$0.isEmpty } ?? false
        return HStack(spacing: 6) {
            StatusDot(color: link == nil ? DS.text3 : (up ? DS.ok : DS.bad), size: 6, pulse: up)
            Text(name).font(.system(size: 12, weight: .medium)).foregroundStyle(DS.text1)
            Text(link == nil ? L("bakılıyor…", "checking…") : (up ? link! : L("ulaşılamıyor", "unreachable")))
                .font(.system(size: 11))
                .foregroundStyle(DS.text3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DS.pill, in: Capsule())
    }

    private func attentionRow(icon: String, tint: Color, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(tint).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(DS.text1).lineLimit(1)
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(DS.text2).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(DS.text3)
            }
            .card(padding: 12, accent: tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tasks

private struct TasksSection: View {
    @EnvironmentObject var monitor: DuffyMonitor

    private let filters: [(String, String)] = [
        ("all", L("Tümü", "All")), ("active", L("Süren", "Running")), ("awaiting_approval", L("Onay", "Approval")),
        ("done", L("Tamamlanan", "Done")), ("failed", L("Hata", "Failed")), ("rejected", L("Reddedilen", "Rejected")),
    ]

    var body: some View {
        SectionScroll {
            composer

            HStack(spacing: 6) {
                ForEach(filters, id: \.0) { key, label in
                    let count = count(for: key)
                    Button {
                        monitor.taskStatusFilter = key
                    } label: {
                        HStack(spacing: 4) {
                            Text(label)
                            if count > 0 { Text("\(count)").foregroundStyle(monitor.taskStatusFilter == key ? .black.opacity(0.6) : DS.text3) }
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(monitor.taskStatusFilter == key ? .black : DS.text2)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(monitor.taskStatusFilter == key ? DS.accent : DS.pill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Menu {
                    Button(L("Tüm ajanlar", "All agents")) { monitor.taskAgentFilter = nil }
                    Divider()
                    ForEach(monitor.allCharacters) { a in Button(a.name) { monitor.taskAgentFilter = a.id.lowercased() } }
                } label: {
                    Label(monitor.taskAgentFilter.map { monitor.displayName(forCategory: $0) } ?? L("Tüm ajanlar", "All agents"),
                          systemImage: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 11.5))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                Text(L("\(monitor.filteredTasks.count) görev", plural(monitor.filteredTasks.count, "task")))
                    .font(.system(size: 11))
                    .foregroundStyle(DS.text3)
                TextField(L("Başlık, rapor ya da #numara ara", "Search titles, reports or #number"), text: $monitor.taskSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            let list = monitor.filteredTasks
            if list.isEmpty {
                EmptyState(icon: "line.3.horizontal.decrease", title: L("Bu filtreye uyan görev yok", "No tasks match this filter"),
                           subtitle: L("Filtreyi değiştir ya da yukarıdan yeni görev ekle.", "Change the filter or add a task above."))
            } else {
                ForEach(list) { TaskCard(task: $0) }
            }
        }
    }

    private func count(for key: String) -> Int {
        switch key {
        case "all": return 0
        case "active": return monitor.activeTasks.count
        default: return monitor.tasks.filter { $0.status == key }.count
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(monitor.allCharacters) { a in Button(a.name) { monitor.newTaskCat = a.id } }
            } label: {
                Text(monitor.character(for: monitor.newTaskCat)?.name ?? monitor.newTaskCat)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L("Görevi yapacak ajan", "Agent for this task"))

            Divider().frame(height: 18)

            TextField(L("Yeni arka plan görevi: ne yapılsın?", "New background task: what should be done?"), text: $monitor.newTaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit(submit)

            Button(L("Kuyruğa ekle", "Queue"), action: submit)
                .buttonStyle(.borderedProminent)
                .tint(DS.accent)
                .disabled(monitor.newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .card(padding: 12)
    }

    private func submit() {
        Task {
            if await monitor.addTask(title: monitor.newTaskTitle, category: monitor.newTaskCat) {
                monitor.newTaskTitle = ""
            }
        }
    }
}

private struct TaskCard: View {
    @EnvironmentObject var monitor: DuffyMonitor
    let task: DuffyTask
    @State private var expanded = false

    var body: some View {
        let summary = task.resultSummary ?? ""
        let long = summary.count > 320
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatusBadge(status: task.status)
                Text("#\(task.id)").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(DS.text3)
                if let a = monitor.character(for: task.category) {
                    Chip(text: a.name, color: a.color)
                } else {
                    Chip(text: task.category)
                }
                Spacer()
                if let m = task.modelUsed, !m.isEmpty {
                    Text(m).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(DS.text3).lineLimit(1)
                }
                Text(Fmt.relative(task.lastActivity))
                    .font(.system(size: 11))
                    .foregroundStyle(DS.text3)
                    .help(task.updatedAt ?? task.createdAt ?? "")
            }

            Text(task.title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(DS.text1)
                .lineLimit(expanded ? nil : 2)
                .textSelection(.enabled)

            if task.status == "awaiting_approval" {
                ApprovalBox(task: task)
            }

            if !summary.isEmpty {
                MarkdownText(text: expanded || !long ? summary : String(summary.prefix(320)) + "…", size: 12, color: DS.text2)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            HStack(spacing: 14) {
                if long {
                    Button(expanded ? L("Daralt", "Collapse") : L("Tüm raporu göster", "Show full report")) { withAnimation { expanded.toggle() } }
                }
                if !summary.isEmpty { Button(L("Raporu kopyala", "Copy report")) { monitor.copy(summary) } }
                Spacer()
                if TaskState.canRetry(task.status) {
                    Button {
                        Task { await monitor.taskAction("retry", id: task.id, label: L("Görev yeniden başlatıldı", "Task restarted")) }
                    } label: {
                        Label(L("Tekrar çalıştır", "Run again"), systemImage: "arrow.clockwise")
                    }
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(DS.accent)
        }
        .card(accent: TaskState.color(task.status))
    }
}

// Onay kutusu: komutu göster, onaydan önce bir kez daha sor
private struct ApprovalBox: View {
    @EnvironmentObject var monitor: DuffyMonitor
    let task: DuffyTask
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(task.approvalAction ?? L("Bu adım senin onayını bekliyor", "This step needs your approval"), systemImage: "hand.raised.fill")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(DS.warn)
            if let cmd = task.approvalCmd, !cmd.isEmpty {
                HStack(alignment: .top) {
                    Text(cmd)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(DS.text1)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { monitor.copy(cmd) } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain)
                        .foregroundStyle(DS.text2)
                        .help(L("Komutu kopyala", "Copy command"))
                }
                .padding(10)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            HStack {
                Text(L("Onaylarsan bu komut \(monitor.hostLabel) üzerinde çalıştırılır.", "If you approve, this command runs on \(monitor.hostLabel)."))
                    .font(.system(size: 11))
                    .foregroundStyle(DS.text3)
                Spacer()
                Button(L("Reddet", "Reject")) {
                    Task { await monitor.taskAction("reject", id: task.id, label: L("Reddedildi", "Rejected")) }
                }
                .buttonStyle(.bordered)
                Button(L("Onayla…", "Approve…")) { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.ok)
            }
        }
        .padding(12)
        .background(DS.warn.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(DS.warn.opacity(0.3)) }
        .confirmationDialog(L("#\(task.id) onaylansın mı?", "Approve #\(task.id)?"), isPresented: $confirming) {
            Button(L("Onayla ve çalıştır", "Approve and run")) {
                Task { await monitor.taskAction("approve", id: task.id, label: L("Onaylandı, çalıştırılıyor", "Approved, running")) }
            }
            Button(L("Vazgeç", "Cancel"), role: .cancel) {}
        } message: {
            Text(task.approvalCmd ?? task.approvalAction ?? task.title)
        }
    }
}

// MARK: - Approvals

private struct ApprovalsSection: View {
    @EnvironmentObject var monitor: DuffyMonitor

    var body: some View {
        SectionScroll {
            if monitor.pendingApprovals.isEmpty {
                EmptyState(icon: "checkmark.shield", title: L("Onay bekleyen işlem yok", "Nothing waiting for approval"),
                           subtitle: L("Ajanlar e-posta gönderme, ödeme, silme gibi riskli bir adıma geldiğinde burada durur ve senin kararını bekler.", "When an agent reaches a risky step, like sending email, paying or deleting, it stops here and waits for you."))
            } else {
                Text(L("Her onay, gösterilen komutu \(monitor.hostLabel) üzerinde çalıştırır. Emin değilsen reddet; ajan başka yol arar.", "Each approval runs the command shown on \(monitor.hostLabel). If you're not sure, reject it and the agent will find another way."))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.text2)
                ForEach(monitor.pendingApprovals) { TaskCard(task: $0) }
            }
        }
    }
}

// MARK: - Office

private struct OfficeSection: View {
    @EnvironmentObject var monitor: DuffyMonitor

    var body: some View {
        SectionScroll {
            HStack(spacing: 8) {
                StatusDot(color: monitor.officeOnline ? DS.ok : DS.bad, size: 6, pulse: monitor.officeOnline)
                Text(monitor.officeOnline ? L("Ofis paneli bağlı · \(Fmt.ago(monitor.officeSync)) güncellendi", "Office panel connected · updated \(Fmt.ago(monitor.officeSync))") : L("Ofis paneline ulaşılamıyor", "Office panel unreachable"))
                    .font(.system(size: 12))
                    .foregroundStyle(DS.text2)
            }
            if monitor.officeAgents.isEmpty {
                EmptyState(icon: "building.2", title: L("Ofis verisi yok", "No office data"),
                           subtitle: L("office.py çalışıyorsa birkaç saniye içinde görünür. Varsayılan port 8900.", "If office.py is running, its data shows up within seconds. Default port 8900."))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                    ForEach(monitor.officeAgents.sorted { ($0.severity, $0.name) < ($1.severity, $1.name) }) { OfficeCard(agent: $0) }
                }
            }
        }
    }
}

private struct OfficeCard: View {
    let agent: OfficeAgent

    var body: some View {
        let tint = DS.stateColor(agent.state)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(agent.name).font(.system(size: 13, weight: .bold)).foregroundStyle(DS.text1).lineLimit(1)
                Spacer()
                Text(agent.state == "ok" ? L("çalışıyor", "running") : (agent.state == "warn" ? L("dikkat", "warning") : L("kapalı", "down")))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(tint.opacity(0.15), in: Capsule())
            }
            Text(agent.role).font(.system(size: 11)).foregroundStyle(DS.text3).lineLimit(1)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                ForEach(agent.facts.keys.sorted(), id: \.self) { key in
                    GridRow {
                        Text(key).font(.system(size: 11)).foregroundStyle(DS.text3)
                        Text(Fmt.humanize(agent.facts[key]?.text ?? "—"))
                            .font(.system(size: 11))
                            .foregroundStyle(DS.text1)
                            .lineLimit(3)
                            .textSelection(.enabled)
                            .help(agent.facts[key]?.text ?? "")
                    }
                }
            }
        }
        .card(padding: 12, accent: tint)
    }
}

// MARK: - Services

private struct ServicesSection: View {
    @EnvironmentObject var monitor: DuffyMonitor
    @State private var query = ""
    @State private var onlyProblems = false

    // Çalışmayan ama 0 ile çıkmış servisler zamanlanmış işlerdir; arıza değil
    private func rank(_ s: OfficeService) -> Int { s.running ? 1 : (s.lastExit == "0" || s.lastExit == "—" ? 2 : 0) }

    var body: some View {
        let all = monitor.officeServices
        let running = all.filter(\.running).count
        let failing = all.filter { rank($0) == 0 }.count
        let list = all
            .filter { query.isEmpty || $0.label.localizedCaseInsensitiveContains(query) }
            .filter { !onlyProblems || rank($0) == 0 }
            .sorted { (rank($0), $0.label) < (rank($1), $1.label) }
        SectionScroll {
            HStack(spacing: 14) {
                Label(L("\(running) çalışıyor", "\(running) running"), systemImage: "circle.fill").foregroundStyle(DS.ok)
                Label(L("\(failing) hatalı", "\(failing) failing"), systemImage: "circle.fill").foregroundStyle(failing > 0 ? DS.warn : DS.text3)
                Label(L("\(all.count - running - failing) bekliyor", "\(all.count - running - failing) idle"), systemImage: "circle.fill").foregroundStyle(DS.text3)
                Spacer()
                Toggle(L("Sadece hatalılar", "Failing only"), isOn: $onlyProblems).toggleStyle(.switch).controlSize(.small)
                TextField(L("Servis ara", "Search services"), text: $query).textFieldStyle(.roundedBorder).frame(width: 180)
            }
            if list.isEmpty {
                EmptyState(icon: "server.rack",
                           title: all.isEmpty ? L("Servis listesi yok", "No service list") : (onlyProblems && query.isEmpty ? L("Hatalı servis yok", "No failing services") : L("Eşleşen servis yok", "No matching services")))
            } else {
                VStack(spacing: 0) {
                    ForEach(list) { svc in
                        let r = rank(svc)
                        HStack(spacing: 10) {
                            Circle().fill(r == 1 ? DS.ok : (r == 0 ? DS.warn : DS.muted)).frame(width: 7, height: 7)
                            Text(svc.label).font(.system(size: 12, design: .monospaced)).foregroundStyle(DS.text1).lineLimit(1)
                            Spacer()
                            Text(r == 1 ? L("çalışıyor · pid \(svc.pid!)", "running · pid \(svc.pid!)") : (r == 0 ? L("hata · çıkış kodu \(svc.lastExit)", "failed · exit code \(svc.lastExit)") : L("bekliyor", "idle")))
                                .font(.system(size: 11))
                                .foregroundStyle(r == 0 ? DS.warn : DS.text3)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        if svc.id != list.last?.id { Divider().overlay(DS.stroke) }
                    }
                }
                .card(padding: 0)
            }
        }
    }
}

// MARK: - Commands

private struct CommandsSection: View {
    @EnvironmentObject var monitor: DuffyMonitor

    var body: some View {
        SectionScroll {
            Text(L("Terminalden ya da sohbet köprüsünden aynı işleri yapmak için hazır komutlar.", "Ready-made commands for doing the same from a terminal or a chat bridge."))
                .font(.system(size: 12))
                .foregroundStyle(DS.text2)
            ForEach(monitor.config.commands ?? AppConfig.defaultCommands) { item in
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.text1)
                        Text(item.command)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(DS.accent)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
                        if let d = item.desc {
                            Text(d).font(.system(size: 11.5)).foregroundStyle(DS.text3)
                        }
                    }
                    Button { monitor.copy(item.command) } label: { Label(L("Kopyala", "Copy"), systemImage: "doc.on.doc") }
                        .buttonStyle(.bordered)
                }
                .card()
            }
        }
    }
}
