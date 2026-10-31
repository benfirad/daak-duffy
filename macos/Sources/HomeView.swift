import SwiftUI

// Menü çubuğu penceresi: karakter listesi ve doğrudan sohbet
struct HomeView: View {
    @EnvironmentObject var monitor: DuffyMonitor

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()
            if let agent = monitor.activeAgent {
                ChatView(agent: agent)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                RosterView()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = monitor.toast {
                Text(toast)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.text1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(DS.bgRaised, in: Capsule())
                    .overlay { Capsule().stroke(DS.stroke) }
                    .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
                    .padding(.bottom, 92)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: monitor.activeAgent?.id)
        .frame(width: 410, height: 740)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Roster

struct RosterView: View {
    @EnvironmentObject var monitor: DuffyMonitor
    @FocusState private var quickFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CircleIconButton(systemName: "square.grid.2x2", badge: monitor.pendingApprovals.count,
                                 help: L("Konsolu aç (görevler, onaylar, ajan ofisi)", "Open the console (tasks, approvals, agent office)")) {
                    monitor.openConsole(monitor.pendingApprovals.isEmpty ? .overview : .approvals)
                }
                Spacer()
                CircleIconButton(systemName: monitor.showQuickTask ? "xmark" : "plus",
                                 help: L("Hızlı arka plan görevi ekle", "Quick background task")) {
                    withAnimation(.easeInOut(duration: 0.15)) { monitor.showQuickTask.toggle() }
                    quickFocused = monitor.showQuickTask
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)

            hero

            if monitor.showQuickTask { quickTaskBar }

            if !monitor.pendingApprovals.isEmpty { approvalBanner }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("AJANLAR", "AGENTS"))
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(DS.text3)
                        Spacer()
                        if !monitor.officeAgents.isEmpty {
                            let problems = monitor.agents.filter { monitor.liveState(for: $0).map { $0 != "ok" } ?? false }.count
                            Text(problems == 0 ? L("hepsi yolunda", "all good") : L("\(problems) ajanda sorun var", "\(problems) \(problems == 1 ? "needs" : "need") attention"))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(problems == 0 ? DS.text3 : DS.warn)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)

                    if monitor.agents.isEmpty {
                        Text(L("Sunucuda tanımlı ajan yok. ~/.duffy/app.json ile karakter ekleyebilirsin.", "No agents on the server yet. Add characters in ~/.duffy/app.json."))
                            .font(.system(size: 12))
                            .foregroundStyle(DS.text2)
                            .padding(10)
                    }
                    ForEach(monitor.agents) { agent in
                        AgentRow(agent: agent)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 8) {
            Button {
                monitor.activeAgent = monitor.chief
            } label: {
                VStack(spacing: 8) {
                    CuteBlobAvatar(color: monitor.chief.color, shapeType: 0, size: 80, showStarBadge: true)
                    Text(monitor.chief.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.text1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("\(monitor.chief.name) ile konuş", "Talk to \(monitor.chief.name)"))

            statusStrip
        }
        .padding(.bottom, 10)
    }

    // Bağlantı, kuyruk ve uyarılar tek satırda; tıklayınca ilgili konsol bölümü açılır
    private var statusStrip: some View {
        let parts: [String] = monitor.online
            ? [
                "\(monitor.hostLabel) · \(monitor.linkLabel)",
                monitor.activeTasks.isEmpty ? L("kuyruk boş", "queue empty") : L("\(monitor.activeTasks.count) görev sürüyor", "\(monitor.activeTasks.count) running"),
                monitor.officeProblems.isEmpty ? nil : L("\(monitor.officeProblems.count) uyarı", plural(monitor.officeProblems.count, "warning")),
                monitor.lastSync.map { L("güncel \(Fmt.clock($0))", "updated \(Fmt.clock($0))") },
            ].compactMap { $0 }
            : [L("\(monitor.hostLabel) sunucusuna ulaşılamıyor", "Can't reach \(monitor.hostLabel)")]
        return Button {
            monitor.openConsole(monitor.officeProblems.isEmpty ? .overview : .office)
        } label: {
            HStack(spacing: 4) {
                StatusDot(color: DS.stateColor(monitor.overallState), size: 6, pulse: monitor.online)
                Text(parts.joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.text2)
                    .lineLimit(1)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .background(DS.pill, in: Capsule())
        }
        .buttonStyle(.plain)
        .help(L("Genel bakışı aç", "Open the overview"))
    }

    private var quickTaskBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(monitor.allCharacters) { a in
                        Button(a.name) { monitor.newTaskCat = a.id }
                    }
                } label: {
                    Text(monitor.character(for: monitor.newTaskCat)?.name ?? monitor.newTaskCat)
                        .font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(L("Görevi hangi ajan yapacak", "Which agent does the task"))

                TextField(L("Ne yapılsın? Enter ile kuyruğa ekle", "What should be done? Enter to queue"), text: $monitor.newTaskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($quickFocused)
                    .onSubmit(submitQuickTask)
                    .onExitCommand { monitor.showQuickTask = false }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(DS.pill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DS.accent.opacity(0.5)) }

            Text(L("Görev arka planda çalışır; riskli adımlar senin onayını bekler.", "Runs in the background; risky steps wait for your approval."))
                .font(.system(size: 10.5))
                .foregroundStyle(DS.text3)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func submitQuickTask() {
        Task {
            if await monitor.addTask(title: monitor.newTaskTitle, category: monitor.newTaskCat) {
                monitor.newTaskTitle = ""
                monitor.showQuickTask = false
            }
        }
    }

    private var approvalBanner: some View {
        let n = monitor.pendingApprovals.count
        return Button {
            monitor.openConsole(.approvals)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.warn)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("\(n) işlem onayını bekliyor", "\(n) waiting for your approval"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(DS.text1)
                    Text(monitor.pendingApprovals.first?.approvalAction ?? monitor.pendingApprovals.first?.title ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.text2)
                        .lineLimit(1)
                }
                Spacer()
                Text(L("İncele", "Review"))
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(DS.warn, in: Capsule())
            }
            .padding(12)
            .background(DS.warn.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DS.warn.opacity(0.35)) }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }
}

struct AgentRow: View {
    @EnvironmentObject var monitor: DuffyMonitor
    let agent: AgentCharacter
    @State private var hover = false

    var body: some View {
        let preview = monitor.preview(for: agent)
        let state = monitor.liveState(for: agent)
        let busy = monitor.tasks(for: agent).contains { $0.status == "running" }
        Button {
            monitor.activeAgent = agent
        } label: {
            HStack(alignment: .center, spacing: 13) {
                CuteBlobAvatar(color: agent.color, shapeType: agent.shapeType, size: 42)
                    .frame(width: 48, height: 48)
                    .overlay(alignment: .bottomTrailing) {
                        if let state {
                            Circle()
                                .fill(DS.stateColor(state))
                                .frame(width: 11, height: 11)
                                .overlay { Circle().stroke(DS.bg, lineWidth: 2.5) }
                                .offset(x: 1, y: 1)
                                .help(state == "ok" ? L("Bağlı servisler çalışıyor", "Linked services are up") : L("Bağlı serviste sorun var", "A linked service has a problem"))
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(agent.name)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(DS.text1)
                            .lineLimit(1)
                        Text(agent.roleTag)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(DS.text3)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if busy {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(DS.info)
                                .help(L("Görev çalışıyor", "Task running"))
                        }
                        Text(preview.time)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(DS.text3)
                    }
                    HStack(spacing: 5) {
                        if preview.fromLive {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 9))
                                .foregroundStyle(DS.stateColor(state))
                        }
                        Text(preview.text)
                            .font(.system(size: 12.5))
                            .foregroundStyle(DS.text2)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(hover ? DS.surfaceHover : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
