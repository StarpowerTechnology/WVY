//
//  ContentView.swift
//  WVY
//
//  Created by Spaceman on 4/19/26.
//

import SwiftUI
import AppKit
import AVFoundation

struct ContentView: View {
    @AppStorage(WVYSettingsKey.selectedModelID) private var selectedModelID = OpenRouterConfig.defaultModelID
    @AppStorage(WVYSettingsKey.instructionPrompt) private var instructionPrompt = OpenRouterConfig.defaultInstructionPrompt

    @State private var availableModels = OpenRouterConfig.models
    @State private var sharedAgents = AgentProfile.defaultAgents()
    @State private var chats: [ChatSession] = []
    @State private var selectedChatID: UUID?
    @State private var draftMessage = ""
    @State private var projectFolders: [String] = []
    @State private var syncedItems: [StoredItem] = []
    @State private var showFilesPopup = false
    @State private var showSettingsPopup = false
    @State private var showAgentsPopup = false
    @State private var showModesPopup = false
    @State private var isSending = false
    @State private var renameChatID: UUID?
    @State private var renameChatTitle = ""
    @State private var chatPendingDelete: ChatSession?
    @State private var messagePendingDelete: MessageDeleteRequest?
    @State private var speechSynthesizer = AVSpeechSynthesizer()

    private var selectedChatIndex: Int? {
        chats.firstIndex { $0.id == selectedChatID }
    }

    private var selectedChat: ChatSession? {
        guard let selectedChatIndex else {
            return nil
        }

        return chats[selectedChatIndex]
    }

    private var normalizedSelectedModelID: String {
        OpenRouterConfig.normalizedModelID(
            selectedModelID,
            availableModels: availableModels
        )
    }

    private var selectedPrimaryModelID: String {
        return OpenRouterConfig.normalizedModelID(
            sharedAgents.first?.modelID ?? selectedModelID,
            availableModels: availableModels
        )
    }

    private var canSendMessage: Bool {
        selectedChatIndex != nil &&
        !isSending &&
        !draftMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 280)
        } detail: {
            detailView
        }
        .frame(minWidth: 1100, minHeight: 720)
        .overlay {
            ZStack {
                if showFilesPopup {
                    FilesPopupView(isPresented: $showFilesPopup)
                }

                if showSettingsPopup {
                    SettingsPopupView(isPresented: $showSettingsPopup)
                }

                if showAgentsPopup, let selectedChat {
                    AgentsPopupView(
                        isPresented: $showAgentsPopup,
                        availableModels: availableModels,
                        chat: selectedChat,
                        onUpdateChat: { updatedChat in
                            guard updatedChat.id == selectedChat.id else {
                                return
                            }

                            var repairedChat = updatedChat
                            repairedChat.repairAgentState()
                            applySharedAgents(repairedChat.agents)
                        }
                    )
                }

                if showModesPopup, let selectedChat {
                    ModesPopupView(
                        isPresented: $showModesPopup,
                        chat: selectedChat,
                        onUpdateMode: { mode in
                            updateSelectedChat { chat in
                                chat.mode = mode
                            }
                        },
                        onUpdateMaxResponsesPerAgent: { maxResponsesPerAgent in
                            updateSelectedChat { chat in
                                chat.maxResponsesPerAgent = maxResponsesPerAgent
                            }
                        },
                        onUpdateRecommendedSleepMinutes: { recommendedSleepMinutes in
                            updateSelectedChat { chat in
                                chat.recommendedSleepMinutes = recommendedSleepMinutes
                            }
                        }
                    )
                }
            }
        }
        .alert("Rename Chat", isPresented: renameAlertBinding) {
            TextField("Chat name", text: $renameChatTitle)

            Button("Cancel", role: .cancel) {
                clearRenameState()
            }

            Button("Rename") {
                renameSelectedChat()
            }
            .disabled(renameChatTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Delete Chat", isPresented: deleteAlertBinding) {
            Button("Cancel", role: .cancel) {
                chatPendingDelete = nil
            }

            Button("Delete", role: .destructive) {
                deleteSelectedChat()
            }
        } message: {
            Text("Are you sure you want to delete this chat?")
        }
        .alert("Delete Reply", isPresented: deleteMessageAlertBinding) {
            Button("Cancel", role: .cancel) {
                messagePendingDelete = nil
            }

            Button("Delete", role: .destructive) {
                deletePendingMessage()
            }
        } message: {
            Text("Are you sure?")
        }
        .task {
            if instructionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                instructionPrompt = OpenRouterConfig.defaultInstructionPrompt
            }
            sharedAgents = GlobalAgentStore.loadAgents()
            loadChats()
            availableModels = OpenRouterConfig.deduplicatedModels(OpenRouterConfig.models)
            selectedModelID = OpenRouterConfig.normalizedModelID(
                selectedModelID,
                availableModels: availableModels
            )
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image("Starpower Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)

                Text("WVY")
                    .font(.system(size: 28, weight: .bold))

                Spacer()

                Button(action: createBlankChat) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Chats")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)

                        if chats.isEmpty {
                            Text("No chats yet")
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        } else {
                            ForEach(chats) { chat in
                                chatRow(chat)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Projects")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button(action: createProjectFolder) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                        }

                        if projectFolders.isEmpty {
                            Text("No projects yet")
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        } else {
                            ForEach(projectFolders, id: \.self) { projectName in
                                Text(projectName)
                                    .font(.system(size: 14, weight: .medium))
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.primary.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    showSettingsPopup = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(SidebarFooterButtonStyle())

                Button {
                    showFilesPopup = true
                } label: {
                    Image(systemName: "doc")
                }
                .buttonStyle(SidebarFooterButtonStyle())
            }
        }
        .padding(20)
        .background(Color(red: 0.15, green: 0.15, blue: 0.16))
    }

    private func chatRow(_ chat: ChatSession) -> some View {
        HStack(spacing: 8) {
            Button {
                selectedChatID = chat.id
            } label: {
                Text(chat.displayTitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Rename") {
                    renameChatID = chat.id
                    renameChatTitle = chat.displayTitle
                }

                Button("Delete", role: .destructive) {
                    chatPendingDelete = chat
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedChatID == chat.id ? Color.primary.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var detailView: some View {
        VStack(spacing: 0) {
            if let selectedChat {
                messagesView(for: selectedChat)
            } else {
                Spacer()
                Text("Start a new chat")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            promptBar
                .padding(24)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func messagesView(for chat: ChatSession) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(chat.messages) { message in
                        HStack {
                            if message.isUser {
                                Spacer(minLength: 120)
                            }

                            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                                Text(message.text)
                                    .font(.system(size: 15))
                                    .foregroundStyle(message.isUser ? .white : .primary)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 16)
                                    .background(
                                        message.isUser
                                        ? Color(red: 0.24, green: 0.24, blue: 0.27)
                                        : Color.clear
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                                if !message.isUser {
                                    replyMetaView(message: message, chatID: chat.id)
                                }
                            }

                            if !message.isUser {
                                Spacer(minLength: 120)
                            }
                        }
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 12)
            }
            .onChange(of: chat.messages.count) { _, _ in
                if let lastMessageID = chat.messages.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastMessageID, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func buildCurrentChatLog(from messages: [ChatMessage]) -> String {
        messages.map { message in
            if message.isUser {
                return "User: \(message.text)"
            }

            let name = message.agentName?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let name, !name.isEmpty {
                return "\(name): \(message.text)"
            }

            return "Assistant: \(message.text)"
        }
        .joined(separator: "\n\n")
    }

    private func replyMetaView(message: ChatMessage, chatID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(replyAgentName(for: message))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("•")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    copyMessage(message.text)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(ReplyActionButtonStyle())
                .help("Copy")

                Menu {
                    Button("Retry") {
                        retryAssistantMessage(message, in: chatID, mode: .retry)
                    }

                    Button("Longer") {
                        retryAssistantMessage(message, in: chatID, mode: .longer)
                    }

                    Button("Concise") {
                        retryAssistantMessage(message, in: chatID, mode: .concise)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .menuStyle(.button)
                .buttonStyle(ReplyActionButtonStyle())
                .disabled(isSending)
                .help("Retry")

                Button {
                    speakMessage(message.text)
                } label: {
                    Image(systemName: "speaker.wave.2")
                }
                .buttonStyle(ReplyActionButtonStyle())
                .help("TTS")

                Button {
                    messagePendingDelete = MessageDeleteRequest(chatID: chatID, messageID: message.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(ReplyActionButtonStyle())
                .help("Delete")
            }
        }
        .padding(.leading, 16)
    }

    private func replyAgentName(for message: ChatMessage) -> String {
        let agentName = message.agentName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return agentName.isEmpty ? "Assistant" : agentName
    }

    private var promptBar: some View {
        VStack(alignment: .leading, spacing: 18) {
            TextField("Message WVY", text: $draftMessage, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1 ... 6)

            HStack(spacing: 10) {
                Menu {
                    ForEach(ToolOption.allCases) { tool in
                        Button(tool.rawValue) { }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)

                Menu {
                    ForEach(availableModels) { model in
                        Button(model.id) {
                            updatePrimaryAgentModel(model.id)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(selectedPrimaryModelID)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 9)
                    .padding(.horizontal, 14)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)

                Button {
                    showAgentsPopup = true
                } label: {
                    Text("Agents")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 14)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    showModesPopup = true
                } label: {
                    Text("Modes")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 14)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: sendMessage) {
                    Group {
                        if isSending {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(!canSendMessage)
                .opacity(canSendMessage ? 1 : 0.45)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(red: 0.16, green: 0.16, blue: 0.17))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func updatePrimaryAgentModel(_ modelID: String) {
        var agents = repairedAgents(sharedAgents)
        agents[0].modelID = modelID
        agents[0].name = "WVY"
        selectedModelID = modelID
        applySharedAgents(agents)
    }

    private func updateSelectedChat(_ transform: (inout ChatSession) -> Void) {
        guard let selectedChatID,
              let index = chats.firstIndex(where: { $0.id == selectedChatID }) else {
            return
        }

        var chat = chats[index]
        chat.repairAgentState()
        transform(&chat)
        chat.repairAgentState()
        persist(chat)
    }

    private func repairedAgents(_ agents: [AgentProfile]) -> [AgentProfile] {
        var chat = ChatSession(agents: agents)
        chat.repairAgentState()
        return chat.agents
    }

    private func applySharedAgents(_ agents: [AgentProfile]) {
        let agents = repairedAgents(agents)
        let currentSelectedChatID = selectedChatID

        sharedAgents = agents
        GlobalAgentStore.saveAgents(agents)

        chats = chats.map { existingChat in
            var chat = existingChat
            chat.agents = agents
            chat.repairAgentState()
            LocalChatStore.save(chat: chat)
            return chat
        }
        .sorted { $0.updatedAt > $1.updatedAt }

        selectedChatID = currentSelectedChatID
    }

    private func createBlankChat() {
        var chat = ChatSession(agents: sharedAgents)
        chat.repairAgentState()
        chats.insert(chat, at: 0)
        selectedChatID = chat.id
        LocalChatStore.save(chat: chat)
        refreshStorageState()
    }

    private func createProjectFolder() {
        let projectName = LocalChatStore.nextProjectFolderName()
        LocalChatStore.createProjectFolder(named: projectName)
        refreshStorageState()
    }

    private func sendMessage() {
        guard let selectedChatID,
              let index = chats.firstIndex(where: { $0.id == selectedChatID }) else {
            return
        }

        let trimmedMessage = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            return
        }

        var chat = chats[index]
        chat.agents = sharedAgents
        chat.messages.append(ChatMessage(text: trimmedMessage, isUser: true))
        chat.repairAgentState()
        chat.updatedAt = .now

        if chat.isUntitled {
            chat.title = String(trimmedMessage.prefix(20))
            chat.isUntitled = false
        }

        draftMessage = ""
        isSending = true
        persist(chat)

        let chatSnapshot = chat
        let chatID = chat.id

        Task {
            await requestChatReply(
                for: chatID,
                chatSnapshot: chatSnapshot
            )
        }
    }

    @MainActor
    private func requestChatReply(
        for chatID: UUID,
        chatSnapshot: ChatSession
    ) async {
        let apiKey = OpenRouterSecrets.loadAPIKey().trimmingCharacters(in: .whitespacesAndNewlines)

        guard !apiKey.isEmpty else {
            appendAssistantMessage(
                "Add your OpenRouter API key in Settings > API.",
                to: chatID,
                agentName: "WVY"
            )
            isSending = false
            return
        }

        var chat = chatSnapshot
        chat.agents = sharedAgents
        chat.repairAgentState()

        defer {
            isSending = false
        }

        switch chat.mode {
        case .wvy:
            do {
                let reply = try await requestSingleAgentReply(
                    agent: chat.primaryAgent,
                    conversation: chat.messages,
                    apiKey: apiKey
                )

                appendAssistantMessage(reply, to: chatID, agentName: "WVY")
            } catch {
                appendAssistantMessage(OpenRouterConfig.unavailableModelMessage, to: chatID, agentName: "WVY")
            }
        case .wvyGroupchat:
            do {
                let reply = try await requestSingleAgentReply(
                    agent: chat.primaryAgent,
                    conversation: chat.messages,
                    apiKey: apiKey
                )

                appendAssistantMessage(reply, to: chatID, agentName: "WVY")
            } catch {
                appendAssistantMessage(OpenRouterConfig.unavailableModelMessage, to: chatID, agentName: "WVY")
                return
            }

            for _ in 1 ... chat.maxResponsesPerAgent {
                for agent in chat.activeAdditionalAgents {
                    do {
                        let reply = try await requestDecisionAgentReply(
                            agent: agent,
                            conversation: currentConversation(for: chatID),
                            apiKey: apiKey
                        )

                        if reply.trimmingCharacters(in: .whitespacesAndNewlines) == "{[Silent]}" {
                            continue
                        }

                        appendAssistantMessage(reply, to: chatID, agentName: agent.name)

                        _ = try? await requestAgentRestMinutes(
                            agent: agent,
                            conversation: currentConversation(for: chatID),
                            recommendedSleepMinutes: chat.recommendedSleepMinutes,
                            apiKey: apiKey
                        )
                    } catch {
                        appendAssistantMessage(
                            OpenRouterConfig.unavailableModelMessage,
                            to: chatID,
                            agentName: agent.name
                        )
                    }
                }
            }
        }
    }

    private func buildPerspectiveForAgent(
        agent: AgentProfile,
        conversation: [ChatMessage],
        additionalInstruction: String? = nil
    ) -> String {
        let identity = agent.identityPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "You are \(agent.name)."
            : agent.identityPrompt

        var instructions = agent.instructionPrompt.trimmingCharacters(in: .whitespacesAndNewlines)

        if instructions.isEmpty {
            instructions = OpenRouterConfig.defaultInstructionPrompt
        }

        if let additionalInstruction,
           !additionalInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            instructions += "\n\n\(additionalInstruction)"
        }

        let currentChatLog = buildCurrentChatLog(from: conversation)

        return OpenRouterConfig.buildPerspectivePrompt(
            identityPrompt: identity,
            instructionPrompt: instructions,
            currentChatLog: currentChatLog
        )
    }

    private func requestSingleAgentReply(
        agent: AgentProfile,
        conversation: [ChatMessage],
        apiKey: String
    ) async throws -> String {
        try await requestAgentReply(
            agent: agent,
            conversation: conversation,
            apiKey: apiKey
        )
    }

    private func requestAgentReply(
        agent: AgentProfile,
        conversation: [ChatMessage],
        apiKey: String,
        additionalInstruction: String? = nil
    ) async throws -> String {
        let perspectivePrompt = buildPerspectiveForAgent(
            agent: agent,
            conversation: conversation,
            additionalInstruction: additionalInstruction
        )

        let modelID = OpenRouterConfig.normalizedModelID(
            agent.modelID,
            availableModels: availableModels
        )

        return try await OpenRouterService.sendChat(
            perspectivePrompt: perspectivePrompt,
            modelID: modelID,
            apiKey: apiKey
        )
    }

    private func requestDecisionAgentReply(
        agent: AgentProfile,
        conversation: [ChatMessage],
        apiKey: String
    ) async throws -> String {
        let decisionInstruction = """
        You are \(agent.name) in a WVY Groupchat.

        WVY has already replied first.

        if you would like to add to the conversation please reply now.
        To stay silent, please respond now with {[Silent]}

        Do not explain silence.
        If staying silent, respond with exactly:
        {[Silent]}
        """

        let perspectivePrompt = buildPerspectiveForAgent(
            agent: agent,
            conversation: conversation,
            additionalInstruction: decisionInstruction
        )

        let modelID = OpenRouterConfig.normalizedModelID(
            agent.modelID,
            availableModels: availableModels
        )

        return try await OpenRouterService.sendChat(
            perspectivePrompt: perspectivePrompt,
            modelID: modelID,
            apiKey: apiKey
        )
    }

    private func requestAgentRestMinutes(
        agent: AgentProfile,
        conversation: [ChatMessage],
        recommendedSleepMinutes: Int,
        apiKey: String
    ) async throws -> Int? {
        let currentChatLog = buildCurrentChatLog(from: conversation)
        let restReflectionPrompt = OpenRouterConfig.buildRestReflectionPrompt(
            currentChatLog: currentChatLog,
            recommendedSleepMinutes: recommendedSleepMinutes
        )
        let perspectivePrompt = buildPerspectiveForAgent(
            agent: agent,
            conversation: conversation,
            additionalInstruction: restReflectionPrompt
        )
        let modelID = OpenRouterConfig.normalizedModelID(
            agent.modelID,
            availableModels: availableModels
        )
        let reply = try await OpenRouterService.sendChat(
            perspectivePrompt: perspectivePrompt,
            modelID: modelID,
            apiKey: apiKey
        )
        let trimmedReply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmedReply.components(separatedBy: CharacterSet.decimalDigits.inverted)
        let firstInteger = parts.first { !$0.isEmpty }

        guard let firstInteger else {
            return nil
        }

        return Int(firstInteger)
    }

    private func appendAssistantMessage(
        _ text: String,
        to chatID: UUID,
        agentName: String? = nil
    ) {
        guard let index = chats.firstIndex(where: { $0.id == chatID }) else {
            return
        }

        var chat = chats[index]
        chat.messages.append(ChatMessage(text: text, isUser: false, agentName: agentName))
        chat.updatedAt = .now
        persist(chat)
    }

    private func currentConversation(for chatID: UUID) -> [ChatMessage] {
        chats.first(where: { $0.id == chatID })?.messages ?? []
    }

    private func copyMessage(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func speakMessage(_ text: String) {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        speechSynthesizer.speak(AVSpeechUtterance(string: text))
    }

    private func retryAssistantMessage(
        _ message: ChatMessage,
        in chatID: UUID,
        mode: ReplyRetryMode
    ) {
        guard !isSending,
              !message.isUser,
              let chatIndex = chats.firstIndex(where: { $0.id == chatID }),
              let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }

        let conversation = Array(chats[chatIndex].messages[..<messageIndex])
        let agent = agentForReply(named: message.agentName)
        isSending = true

        Task {
            await requestReplacementReply(
                for: chatID,
                messageID: message.id,
                agent: agent,
                conversation: conversation,
                mode: mode
            )
        }
    }

    @MainActor
    private func requestReplacementReply(
        for chatID: UUID,
        messageID: UUID,
        agent: AgentProfile,
        conversation: [ChatMessage],
        mode: ReplyRetryMode
    ) async {
        let apiKey = OpenRouterSecrets.loadAPIKey().trimmingCharacters(in: .whitespacesAndNewlines)

        guard !apiKey.isEmpty else {
            replaceAssistantMessage(
                "Add your OpenRouter API key in Settings > API.",
                in: chatID,
                messageID: messageID,
                agentName: agent.name
            )
            isSending = false
            return
        }

        defer {
            isSending = false
        }

        do {
            let reply = try await requestAgentReply(
                agent: agent,
                conversation: conversation,
                apiKey: apiKey,
                additionalInstruction: mode.instruction
            )

            replaceAssistantMessage(reply, in: chatID, messageID: messageID, agentName: agent.name)
        } catch {
            replaceAssistantMessage(
                OpenRouterConfig.unavailableModelMessage,
                in: chatID,
                messageID: messageID,
                agentName: agent.name
            )
        }
    }

    private func agentForReply(named agentName: String?) -> AgentProfile {
        let name = agentName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let agents = repairedAgents(sharedAgents)

        guard !name.isEmpty else {
            return agents[0]
        }

        if name == "WVY" {
            return agents[0]
        }

        return agents.first { agent in
            agent.name.trimmingCharacters(in: .whitespacesAndNewlines) == name
        } ?? agents[0]
    }

    private func replaceAssistantMessage(
        _ text: String,
        in chatID: UUID,
        messageID: UUID,
        agentName: String? = nil
    ) {
        guard let chatIndex = chats.firstIndex(where: { $0.id == chatID }),
              let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == messageID }),
              !chats[chatIndex].messages[messageIndex].isUser else {
            return
        }

        var chat = chats[chatIndex]
        chat.messages[messageIndex].text = text
        chat.messages[messageIndex].createdAt = .now
        chat.messages[messageIndex].agentName = agentName
        chat.updatedAt = .now
        persist(chat)
    }

    private func deletePendingMessage() {
        guard let messagePendingDelete else {
            return
        }

        deleteMessage(messagePendingDelete)
        self.messagePendingDelete = nil
    }

    private func deleteMessage(_ request: MessageDeleteRequest) {
        guard let chatIndex = chats.firstIndex(where: { $0.id == request.chatID }),
              let messageIndex = chats[chatIndex].messages.firstIndex(where: { $0.id == request.messageID }),
              !chats[chatIndex].messages[messageIndex].isUser else {
            return
        }

        var chat = chats[chatIndex]
        chat.messages.remove(at: messageIndex)
        chat.updatedAt = .now
        persist(chat)
    }

    private func persist(_ chat: ChatSession) {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[index] = chat
        } else {
            chats.insert(chat, at: 0)
        }

        chats.sort { $0.updatedAt > $1.updatedAt }
        selectedChatID = chat.id
        LocalChatStore.save(chat: chat)
        refreshStorageState()
    }

    private func loadChats() {
        chats = LocalChatStore.loadChats().map { loadedChat in
            var chat = loadedChat
            chat.agents = sharedAgents
            chat.repairAgentState()
            LocalChatStore.save(chat: chat)
            return chat
        }
        refreshStorageState()

        if selectedChatID == nil {
            selectedChatID = chats.first?.id
        }
    }

    private func refreshStorageState() {
        projectFolders = LocalChatStore.projectFolders()
        syncedItems = LocalChatStore.syncedItems()
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameChatID != nil },
            set: { isPresented in
                if !isPresented {
                    clearRenameState()
                }
            }
        )
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { chatPendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    chatPendingDelete = nil
                }
            }
        )
    }

    private var deleteMessageAlertBinding: Binding<Bool> {
        Binding(
            get: { messagePendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    messagePendingDelete = nil
                }
            }
        )
    }

    private func clearRenameState() {
        renameChatID = nil
        renameChatTitle = ""
    }

    private func renameSelectedChat() {
        guard let renameChatID,
              let index = chats.firstIndex(where: { $0.id == renameChatID }) else {
            clearRenameState()
            return
        }

        let trimmedTitle = renameChatTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        var chat = chats[index]
        chat.title = trimmedTitle
        chat.isUntitled = false
        persist(chat)
        clearRenameState()
    }

    private func deleteSelectedChat() {
        guard let chatPendingDelete,
              let index = chats.firstIndex(where: { $0.id == chatPendingDelete.id }) else {
            self.chatPendingDelete = nil
            return
        }

        let removedChat = chats.remove(at: index)
        LocalChatStore.delete(chat: removedChat)

        if selectedChatID == removedChat.id {
            selectedChatID = chats.first?.id
        }

        self.chatPendingDelete = nil
        refreshStorageState()
    }
}

private struct SidebarFooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 34, height: 34)
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

private enum ToolOption: String, CaseIterable, Identifiable {
    case webSearch = "WebSearch"
    case canvas = "Canvas"
    case document = "Document"
    case fileUpload = "File Upload"

    var id: String { rawValue }
}

private struct StoredItem: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let isDirectory: Bool
}

private struct MessageDeleteRequest: Identifiable {
    let id = UUID()
    let chatID: UUID
    let messageID: UUID
}

private enum ReplyRetryMode {
    case retry
    case longer
    case concise

    var instruction: String {
        switch self {
        case .retry:
            return "Retry the reply you would give at this point in the chat."
        case .longer:
            return "Retry the reply you would give at this point in the chat with a longer response."
        case .concise:
            return "Retry the reply you would give at this point in the chat with a concise response."
        }
    }
}

private struct ReplyActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 18)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

private enum GlobalAgentStore {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func loadAgents() -> [AgentProfile] {
        guard let data = UserDefaults.standard.data(forKey: WVYSettingsKey.agents),
              let agents = try? decoder.decode([AgentProfile].self, from: data) else {
            return AgentProfile.defaultAgents()
        }

        var chat = ChatSession(agents: agents)
        chat.repairAgentState()
        return chat.agents
    }

    static func saveAgents(_ agents: [AgentProfile]) {
        var chat = ChatSession(agents: agents)
        chat.repairAgentState()

        guard let data = try? encoder.encode(chat.agents) else {
            return
        }

        UserDefaults.standard.set(data, forKey: WVYSettingsKey.agents)
    }
}

private struct FilesPopupView: View {
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Files")
                        .font(.system(size: 22, weight: .bold))

                    Spacer()

                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Text("Coming soon")
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(24)
            .frame(width: 520, height: 420)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture { }
        }
    }
}

private struct AgentsPopupView: View {
    private static let popupWidth: CGFloat = 800
    private static let popupHeight: CGFloat = 620

    @Binding var isPresented: Bool
    let availableModels: [OpenRouterModel]
    let chat: ChatSession
    let onUpdateChat: (ChatSession) -> Void

    @State private var draftChat: ChatSession

    init(
        isPresented: Binding<Bool>,
        availableModels: [OpenRouterModel],
        chat: ChatSession,
        onUpdateChat: @escaping (ChatSession) -> Void
    ) {
        self._isPresented = isPresented
        self.availableModels = availableModels
        self.chat = chat
        self.onUpdateChat = onUpdateChat

        var repairedChat = chat
        repairedChat.repairAgentState()
        self._draftChat = State(initialValue: repairedChat)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Agents")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        primaryAgentCard
                        additionalAgentsCard
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
            .padding(20)
            .frame(width: Self.popupWidth, height: Self.popupHeight, alignment: .topLeading)
            .background(Color(red: 0.10, green: 0.10, blue: 0.11))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 18)
            .onTapGesture { }
        }
    }

    private var primaryAgentCard: some View {
        SettingsCard(title: "Primary Agent") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Name")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                TextField("Name", text: .constant("WVY"))
                    .textFieldStyle(SettingsFieldStyle())
                    .disabled(true)

                Text("Model")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                modelMenu(for: 0)

                Text("Identity Prompt")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                promptEditor(
                    text: agentBinding(index: 0, keyPath: \.identityPrompt),
                    minHeight: 90
                )

                Text("Instruction Prompt")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                promptEditor(
                    text: agentBinding(index: 0, keyPath: \.instructionPrompt),
                    minHeight: 120
                )
            }
        }
    }

    private var additionalAgentsCard: some View {
        SettingsCard(title: "Additional Agents") {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(1 ..< 4, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Agent \(index)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)

                            Spacer()

                            Toggle("Enabled", isOn: enabledBinding(index: index))
                                .toggleStyle(.switch)
                        }

                        Text("Model")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)

                        modelMenu(for: index)

                        Text("Name")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)

                        TextField("Agent name", text: agentBinding(index: index, keyPath: \.name))
                            .textFieldStyle(SettingsFieldStyle())

                        Text("Identity Prompt")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)

                        promptEditor(
                            text: agentBinding(index: index, keyPath: \.identityPrompt),
                            minHeight: 80
                        )

                        Text("Instruction Prompt")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)

                        promptEditor(
                            text: agentBinding(index: index, keyPath: \.instructionPrompt),
                            minHeight: 100
                        )
                    }

                    if index < 3 {
                        Divider()
                            .overlay(Color.white.opacity(0.10))
                    }
                }
            }
        }
    }

    private func modelMenu(for index: Int) -> some View {
        Menu {
            ForEach(availableModels) { model in
                Button(model.id) {
                    updateAgent(index: index) { agent in
                        agent.modelID = model.id
                    }
                }
            }
        } label: {
            HStack {
                Text(modelLabel(for: index))
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private func promptEditor(text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .scrollContentBackground(.hidden)
            .frame(minHeight: minHeight)
            .padding(10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func enabledBinding(index: Int) -> Binding<Bool> {
        Binding(
            get: {
                agent(at: index).isEnabled
            },
            set: { value in
                updateAgent(index: index) { agent in
                    agent.isEnabled = value
                }
            }
        )
    }

    private func agentBinding(index: Int, keyPath: WritableKeyPath<AgentProfile, String>) -> Binding<String> {
        Binding(
            get: {
                agent(at: index)[keyPath: keyPath]
            },
            set: { value in
                updateAgent(index: index) { agent in
                    agent[keyPath: keyPath] = value
                }
            }
        )
    }

    private func agent(at index: Int) -> AgentProfile {
        guard draftChat.agents.indices.contains(index) else {
            return AgentProfile.defaultAgents()[index]
        }

        return draftChat.agents[index]
    }

    private func modelLabel(for index: Int) -> String {
        OpenRouterConfig.normalizedModelID(
            agent(at: index).modelID,
            availableModels: availableModels
        )
    }

    private func saveDraft() {
        draftChat.repairAgentState()
        onUpdateChat(draftChat)
    }

    private func updateAgent(index: Int, _ transform: (inout AgentProfile) -> Void) {
        guard draftChat.agents.indices.contains(index) else {
            return
        }

        transform(&draftChat.agents[index])
        saveDraft()
    }
}

private struct ModesPopupView: View {
    private static let popupWidth: CGFloat = 520
    private static let popupHeight: CGFloat = 460

    @Binding var isPresented: Bool
    let chat: ChatSession
    let onUpdateMode: (WVYChatMode) -> Void
    let onUpdateMaxResponsesPerAgent: (Int) -> Void
    let onUpdateRecommendedSleepMinutes: (Int) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Modes")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)

                    Spacer()

                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 12) {
                    modeRow(
                        mode: .wvy,
                        title: "WVY",
                        subtitle: "Only talk to WVY."
                    )

                    modeRow(
                        mode: .wvyGroupchat,
                        title: "WVY Groupchat",
                        subtitle: "WVY replies first. Additional active agents decide if they should add a message."
                    )

                    groupchatSettings
                }

                Spacer()
            }
            .padding(20)
            .frame(width: Self.popupWidth, height: Self.popupHeight, alignment: .topLeading)
            .background(Color(red: 0.10, green: 0.10, blue: 0.11))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 18)
            .onTapGesture { }
        }
    }

    private func modeRow(
        mode: WVYChatMode,
        title: String,
        subtitle: String
    ) -> some View {
        Button {
            onUpdateMode(mode)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                chat.mode == mode
                ? Color.white.opacity(0.12)
                : Color.white.opacity(0.06)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var groupchatSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper(
                value: maxResponsesPerAgentBinding,
                in: 1 ... 10
            ) {
                HStack {
                    Text("Max responses per agent")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    Text("\(chat.maxResponsesPerAgent)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Stepper(
                value: recommendedSleepMinutesBinding,
                in: 1 ... 60
            ) {
                HStack {
                    Text("Recommended sleep rate")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    Text("\(chat.recommendedSleepMinutes) min")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var maxResponsesPerAgentBinding: Binding<Int> {
        Binding(
            get: { chat.maxResponsesPerAgent },
            set: { onUpdateMaxResponsesPerAgent($0) }
        )
    }

    private var recommendedSleepMinutesBinding: Binding<Int> {
        Binding(
            get: { chat.recommendedSleepMinutes },
            set: { onUpdateRecommendedSleepMinutes($0) }
        )
    }
}

private struct SettingsPopupView: View {
    private static let popupWidth: CGFloat = 800
    private static let popupHeight: CGFloat = 560

    @Binding var isPresented: Bool

    @AppStorage(WVYSettingsKey.appearanceMode) private var appearanceMode = "Dark"
    @AppStorage(WVYSettingsKey.autonomyMode) private var autonomyMode = "Reactive"
    @AppStorage(WVYSettingsKey.instructionPrompt) private var instructionPrompt = OpenRouterConfig.defaultInstructionPrompt
    @AppStorage(WVYSettingsKey.maxRepliesPerAgent) private var maxRepliesPerAgent = 1
    @AppStorage(WVYSettingsKey.freeWillToolUseEnabled) private var freeWillToolUseEnabled = false
    @AppStorage(WVYSettingsKey.fileManagementEnabled) private var fileManagementEnabled = false
    @AppStorage(WVYSettingsKey.dataSharingEnabled) private var dataSharingEnabled = false
    @AppStorage(WVYSettingsKey.youtubeAutoplayEnabled) private var youtubeAutoplayEnabled = false
    @AppStorage(WVYSettingsKey.ttsVoice) private var ttsVoice = "Coming soon"
    @AppStorage(WVYSettingsKey.ttsVolume) private var ttsVolume = 0.7

    @State private var selectedSection: SettingsSection = .account
    @State private var openRouterAPIKey = OpenRouterSecrets.loadAPIKey()
    @State private var apiSaveStatus = ""
    @State private var isSavingAPIKey = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Settings")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)

                    ForEach(SettingsSection.allCases) { section in
                        Button {
                            selectedSection = section
                        } label: {
                            Text(section.rawValue)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    selectedSection == section
                                    ? Color.white.opacity(0.10)
                                    : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .padding(18)
                .frame(
                    width: 180,
                    height: Self.popupHeight,
                    alignment: .topLeading
                )
                .background(Color(red: 0.13, green: 0.13, blue: 0.14))

                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(selectedSection.rawValue)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)

                        Spacer()

                        Button {
                            isPresented = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.10))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    ScrollView {
                        activeSectionView
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(20)
                .frame(
                    width: Self.popupWidth - 180,
                    height: Self.popupHeight,
                    alignment: .topLeading
                )
                .background(Color(red: 0.10, green: 0.10, blue: 0.11))
            }
            .frame(width: Self.popupWidth, height: Self.popupHeight)
            .fixedSize()
            .background(Color(red: 0.10, green: 0.10, blue: 0.11))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipped()
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 18)
            .onTapGesture { }
        }
    }

    @ViewBuilder
    private var activeSectionView: some View {
        switch selectedSection {
        case .account:
            VStack(alignment: .leading, spacing: 16) {
                SettingsCard(title: "Account") {
                    Picker("Appearance", selection: $appearanceMode) {
                        Text("Dark").tag("Dark")
                        Text("Light").tag("Light")
                    }
                    .pickerStyle(.segmented)

                    Button("Sign In / Out") { }
                        .buttonStyle(SettingsActionButtonStyle())
                        .disabled(true)

                    Text("Coming soon")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        case .autonomy:
            SettingsCard(title: "Autonomy") {
                Picker("Mode", selection: $autonomyMode) {
                    Text("Reactive").tag("Reactive")
                    Text("Proactive").tag("Proactive")
                    Text("Autonomous").tag("Autonomous")
                }
                .pickerStyle(.segmented)

                Text("Reactive: single response")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Proactive: multiple responses")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Autonomous: fully independent")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        case .agents:
            SettingsCard(title: "Agents") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Max replies per agent")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)

                    Stepper(
                        value: $maxRepliesPerAgent,
                        in: 1 ... 5
                    ) {
                        Text("\(maxRepliesPerAgent)")
                            .foregroundStyle(.white)
                    }

                    Text("Used by groupchat routing.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        case .files:
            SettingsCard(title: "Files") {
                Text("Coming soon")
                    .foregroundStyle(.secondary)
            }
        case .api:
            SettingsCard(title: "API") {
                SecureField("OpenRouter API key", text: $openRouterAPIKey)
                    .textFieldStyle(SettingsFieldStyle())

                HStack {
                    Button("Save API Key") {
                        saveAPIKey()
                    }
                    .buttonStyle(SettingsActionButtonStyle())
                    .disabled(isSavingAPIKey)

                    if !apiSaveStatus.isEmpty {
                        Text(apiSaveStatus)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("This key is used for live OpenRouter chat requests.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        case .personalization:
            SettingsCard(title: "Personalization") {
                Text("Instruction Prompt")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                TextEditor(text: $instructionPrompt)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(10)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Toggle("Free will tool use", isOn: $freeWillToolUseEnabled)
                    .toggleStyle(.switch)

                Toggle("File management", isOn: $fileManagementEnabled)
                    .toggleStyle(.switch)
            }
        case .data:
            SettingsCard(title: "Data") {
                Toggle("Share data for improvements", isOn: $dataSharingEnabled)
                    .toggleStyle(.switch)
            }
        case .mcp:
            SettingsCard(title: "MCP") {
                Text("Coming soon")
                    .foregroundStyle(.secondary)
            }
        case .audio:
            SettingsCard(title: "Audio") {
                Picker("TTS Voice", selection: $ttsVoice) {
                    Text("Coming soon").tag("Coming soon")
                }
                .disabled(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("TTS Volume")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)

                    Slider(value: $ttsVolume, in: 0 ... 1)
                        .disabled(true)
                }
            }
        case .youtube:
            SettingsCard(title: "Youtube") {
                Button("Connect Youtube Account") { }
                    .buttonStyle(SettingsActionButtonStyle())
                    .disabled(true)

                Toggle("Agent autoplay videos", isOn: $youtubeAutoplayEnabled)
                    .toggleStyle(.switch)
            }
        case .github:
            SettingsCard(title: "GitHub") {
                Button("Connect GitHub Account") { }
                    .buttonStyle(SettingsActionButtonStyle())
                    .disabled(true)

                Text("Coming soon")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func saveAPIKey() {
        let trimmedAPIKey = openRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !isSavingAPIKey else {
            return
        }

        guard !trimmedAPIKey.isEmpty else {
            let saved = OpenRouterSecrets.saveAPIKey("")
            apiSaveStatus = saved ? "API key removed" : "Unable to save key"
            return
        }

        isSavingAPIKey = true
        apiSaveStatus = "Verifying OpenRouter connection..."

        Task {
            do {
                try await OpenRouterService.validateAPIKey(trimmedAPIKey)
                let saved = OpenRouterSecrets.saveAPIKey(trimmedAPIKey)

                await MainActor.run {
                    isSavingAPIKey = false

                    guard saved else {
                        apiSaveStatus = "Unable to save key"
                        return
                    }

                    apiSaveStatus = "Connected and saved"
                }
            } catch {
                await MainActor.run {
                    isSavingAPIKey = false
                    apiSaveStatus = error.localizedDescription.isEmpty
                        ? "Unable to verify key"
                        : error.localizedDescription
                }
            }
        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case account = "Account"
    case autonomy = "Autonomy"
    case agents = "Agents"
    case files = "Files"
    case api = "API"
    case personalization = "Personalization"
    case data = "Data"
    case mcp = "MCP"
    case audio = "Audio"
    case youtube = "Youtube"
    case github = "GitHub"

    var id: String { rawValue }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SettingsActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(Color.white.opacity(configuration.isPressed ? 0.14 : 0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SettingsFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private enum LocalChatStore {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func loadChats() -> [ChatSession] {
        ensureStorageDirectories()

        return chatFileURLs()
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else {
                    return nil
                }

                return try? decoder.decode(ChatSession.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    static func save(chat: ChatSession) {
        ensureStorageDirectories()

        let url = chatFileURL(for: chat)

        do {
            let data = try encoder.encode(chat)
            try data.write(to: url, options: .atomic)
        } catch {
            assertionFailure("Failed to save chat: \(error)")
        }
    }

    static func delete(chat: ChatSession) {
        ensureStorageDirectories()
        try? FileManager.default.removeItem(at: chatFileURL(for: chat))
    }

    static func projectFolders() -> [String] {
        ensureStorageDirectories()

        let directoryURLs = (try? FileManager.default.contentsOfDirectory(
            at: projectsDirectoryURL(),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return directoryURLs
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .map(\.lastPathComponent)
            .sorted()
    }

    static func createProjectFolder(named projectName: String) {
        ensureStorageDirectories()

        let projectDirectory = projectsDirectoryURL().appendingPathComponent(projectName, isDirectory: true)
        try? FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
    }

    static func nextProjectFolderName() -> String {
        let existingFolders = Set(projectFolders())
        var index = 1

        while true {
            let name = index == 1 ? "New Project" : "New Project \(index)"

            if !existingFolders.contains(name) {
                return name
            }

            index += 1
        }
    }

    static func syncedItems() -> [StoredItem] {
        ensureStorageDirectories()

        let urls = [baseDirectoryURL(), chatsDirectoryURL(), projectsDirectoryURL()] + projectDirectoryURLs() + chatFileURLs()

        return urls.map { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true

            return StoredItem(
                name: url.lastPathComponent,
                detail: url.path,
                isDirectory: isDirectory
            )
        }
    }

    private static func ensureStorageDirectories() {
        let fileManager = FileManager.default

        [baseDirectoryURL(), chatsDirectoryURL(), projectsDirectoryURL()].forEach { url in
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private static func baseDirectoryURL() -> URL {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupportURL.appendingPathComponent("WVY", isDirectory: true)
    }

    private static func chatsDirectoryURL() -> URL {
        baseDirectoryURL().appendingPathComponent("Chats", isDirectory: true)
    }

    private static func projectsDirectoryURL() -> URL {
        baseDirectoryURL().appendingPathComponent("Projects", isDirectory: true)
    }

    private static func projectDirectoryURLs() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: projectsDirectoryURL(),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func chatFileURLs() -> [URL] {
        let rootChatFiles = jsonFiles(in: chatsDirectoryURL())
        let projectChatFiles = projectDirectoryURLs().flatMap { jsonFiles(in: $0) }
        return (rootChatFiles + projectChatFiles).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func jsonFiles(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?
            .filter { $0.pathExtension == "json" } ?? []
    }

    private static func chatFileURL(for chat: ChatSession) -> URL {
        let directory: URL

        if let projectName = chat.projectName?.trimmingCharacters(in: .whitespacesAndNewlines), !projectName.isEmpty {
            let projectDirectory = projectsDirectoryURL().appendingPathComponent(projectName, isDirectory: true)
            try? FileManager.default.createDirectory(at: projectDirectory, withIntermediateDirectories: true)
            directory = projectDirectory
        } else {
            directory = chatsDirectoryURL()
        }

        return directory.appendingPathComponent("\(chat.id.uuidString).json")
    }
}

#Preview {
    ContentView()
}
