import SwiftUI

struct ChatView: View {
    @EnvironmentObject var monitor: DuffyMonitor
    let agent: AgentCharacter
    @FocusState private var inputFocused: Bool

    private var msgs: [DuffyChatMsg] { monitor.messages(for: agent) }
    private var canSend: Bool { !monitor.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DS.stroke)
            taskStrip
            messageList
            Divider().overlay(DS.stroke)
            composer
        }
        .onAppear { inputFocused = true }
        .onExitCommand { monitor.activeAgent = nil }
    }

    // MARK: Header

    private var header: some View {
        let state = monitor.liveState(for: agent)
        return HStack(spacing: 11) {
            Button {
                monitor.activeAgent = nil
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.text1)
                    .frame(width: 30, height: 30)
                    .background(DS.pill, in: Circle())
            }
            .buttonStyle(.plain)
            .help(L("Geri (Esc)", "Back (Esc)"))

            CuteBlobAvatar(color: agent.color, shapeType: agent.shapeType, size: 32,
                           showStarBadge: agent.id == monitor.chief.id)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(DS.text1)
                HStack(spacing: 5) {
                    Circle().fill(DS.stateColor(state ?? (monitor.online ? "ok" : "down"))).frame(width: 6, height: 6)
                    Text(statusLine(state))
                        .font(.system(size: 11))
                        .foregroundStyle(DS.text2)
                        .lineLimit(1)
                }
            }

            Spacer()

            Menu {
                Button(L("Görevlerini konsolda aç", "Open tasks in the console")) { monitor.openConsole(.tasks, agentFilter: agent.id) }
                Button(L("Ajan ofisini aç", "Open the agent office")) { monitor.openConsole(.office) }
                Divider()
                Button(L("Sohbeti kopyala", "Copy conversation")) {
                    monitor.copy(msgs.map { "\($0.isUser ? L("Ben", "Me") : agent.name): \($0.message)" }.joined(separator: "\n\n"))
                }
                .disabled(msgs.isEmpty)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 30, height: 30)
            .background(DS.pill, in: Circle())
            .help(L("Diğer işlemler", "More"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private func statusLine(_ state: String?) -> String {
        if monitor.waitingFor == agent.id { return L("yazıyor…", "typing…") }
        if !monitor.online { return L("çevrimdışı · \(agent.roleTag)", "offline · \(agent.roleTag)") }
        if let state, state != "ok" { return L("servis uyarısı · \(agent.roleTag)", "service warning · \(agent.roleTag)") }
        return agent.roleTag
    }

    // Bu ajanın son görevi; tıklayınca konsolda tüm görevleri açılır
    @ViewBuilder private var taskStrip: some View {
        let agentTasks = monitor.tasks(for: agent)
        if let last = agentTasks.first {
            Button {
                monitor.openConsole(.tasks, agentFilter: agent.id)
            } label: {
                HStack(spacing: 8) {
                    StatusBadge(status: last.status, compact: true)
                    Text("#\(last.id) \(last.title)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.text2)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(agentTasks.count > 1 ? L("\(agentTasks.count) görev", "\(agentTasks.count) tasks") : Fmt.relative(last.lastActivity))
                        .font(.system(size: 10.5))
                        .foregroundStyle(DS.text3)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DS.text3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(DS.surface)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Görevleri konsolda aç", "Open tasks in the console"))
        }
    }

    // MARK: Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if msgs.isEmpty {
                        emptyState
                    } else {
                        ForEach(Array(msgs.enumerated()), id: \.element.id) { i, m in
                            if let d = m.date, i == 0 || !Calendar.current.isDate(d, inSameDayAs: msgs[i - 1].date ?? d) {
                                daySeparator(d)
                            }
                            bubble(m).id(m.id)
                        }
                    }
                    if monitor.waitingFor == agent.id {
                        HStack(spacing: 8) {
                            TypingDots()
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(DS.bgRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            Spacer()
                        }
                        .id("typing")
                    }
                }
                .padding(16)
            }
            .onAppear {
                // LazyVStack satırları yerleşmeden kaydırma işe yaramıyor
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { scrollToEnd(proxy, animated: false) }
            }
            .onChange(of: msgs.count) { _ in scrollToEnd(proxy) }
            .onChange(of: monitor.waitingFor) { _ in scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let target: AnyHashable? = monitor.waitingFor == agent.id ? AnyHashable("typing") : msgs.last.map { AnyHashable($0.id) }
        guard let target else { return }
        if animated { withAnimation { proxy.scrollTo(target, anchor: .bottom) } } else { proxy.scrollTo(target, anchor: .bottom) }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            CuteBlobAvatar(color: agent.color, shapeType: agent.shapeType, size: 64,
                           showStarBadge: agent.id == monitor.chief.id)
                .padding(.top, 36)
            Text(agent.greeting)
                .font(.system(size: 13))
                .foregroundStyle(DS.text2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            if let live = monitor.liveSummary(for: agent) {
                Label(live, systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.stateColor(monitor.liveState(for: agent)))
                    .lineLimit(2)
                    .padding(.horizontal, 20)
            }
            VStack(spacing: 6) {
                ForEach(agent.suggestions, id: \.self) { s in
                    Button {
                        Task { await monitor.sendChat(to: agent, text: s) }
                    } label: {
                        HStack {
                            Text(s).font(.system(size: 12))
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(DS.text1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(DS.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(DS.stroke) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private func daySeparator(_ d: Date) -> some View {
        HStack {
            Rectangle().fill(DS.stroke).frame(height: 1)
            Text(Fmt.day(d))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(DS.text3)
                .fixedSize()
            Rectangle().fill(DS.stroke).frame(height: 1)
        }
        .padding(.vertical, 6)
    }

    private func bubble(_ m: DuffyChatMsg) -> some View {
        HStack(alignment: .bottom) {
            if m.isUser { Spacer(minLength: 48) }
            VStack(alignment: m.isUser ? .trailing : .leading, spacing: 3) {
                MarkdownText(text: m.message, size: 13, color: m.isUser ? .white : DS.text1)
                    .textSelection(.enabled)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        m.isUser ? AnyShapeStyle(agent.color.opacity(0.88)) : AnyShapeStyle(DS.bgRaised),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .contextMenu {
                        Button(L("Kopyala", "Copy")) { monitor.copy(m.message) }
                        Button(L("Bunu görev yap", "Turn into a task")) { Task { _ = await monitor.addTask(title: m.message, category: agent.id) } }
                    }
                if let d = m.date {
                    Text(Fmt.time(d))
                        .font(.system(size: 9.5))
                        .foregroundStyle(DS.text3)
                        .padding(.horizontal, 4)
                }
            }
            if !m.isUser { Spacer(minLength: 48) }
        }
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField(L("\(agent.name) ile konuş…", "Message \(agent.name)…"), text: $monitor.chatInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .onSubmit { send() }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(DS.pill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(canSend ? .white : DS.text3)
                        .frame(width: 36, height: 36)
                        .background(canSend ? agent.color : DS.pill, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .help(L("Gönder (Enter)", "Send (Enter)"))
            }

            HStack(spacing: 6) {
                Button {
                    let text = monitor.chatInput
                    Task {
                        if await monitor.addTask(title: text, category: agent.id) { monitor.chatInput = "" }
                    }
                } label: {
                    Label(L("Arka plan görevi yap", "Run as background task"), systemImage: "bolt.horizontal.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(canSend ? DS.text1 : DS.text3)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help(L("Yazdığını sohbet yerine kuyruğa ekler; \(agent.name) arka planda çalışıp sonucu bildirir", "Queues what you typed instead of chatting; \(agent.name) works on it in the background and reports back"))
                Spacer()
                Text(L("Enter gönderir · ⌥Enter yeni satır", "Enter to send · ⌥Enter for a new line"))
                    .font(.system(size: 10))
                    .foregroundStyle(DS.text3)
            }
            .padding(.horizontal, 6)
        }
        .padding(14)
    }

    private func send() {
        guard canSend else { return }
        Task { await monitor.sendChat(to: agent) }
    }
}
