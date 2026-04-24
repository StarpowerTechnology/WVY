//
//  Item.swift
//  WVY
//
//  Created by Spaceman on 4/19/26.
//

import Foundation

enum WVYChatMode: String, Codable, CaseIterable, Identifiable {
    case wvy = "WVY"
    case wvyGroupchat = "WVY Groupchat"

    var id: String { rawValue }
}

struct AgentProfile: Identifiable, Codable, Hashable {
    let id: UUID
    var slotIndex: Int
    var isEnabled: Bool
    var modelID: String
    var name: String
    var identityPrompt: String
    var instructionPrompt: String

    init(
        id: UUID = UUID(),
        slotIndex: Int,
        isEnabled: Bool,
        modelID: String,
        name: String,
        identityPrompt: String,
        instructionPrompt: String
    ) {
        self.id = id
        self.slotIndex = slotIndex
        self.isEnabled = isEnabled
        self.modelID = modelID
        self.name = name
        self.identityPrompt = identityPrompt
        self.instructionPrompt = instructionPrompt
    }
}

extension AgentProfile {
    static func defaultAgents() -> [AgentProfile] {
        let defaultModelID = OpenRouterConfig.defaultModelID

        return [
            AgentProfile(
                slotIndex: 0,
                isEnabled: true,
                modelID: defaultModelID,
                name: "WVY",
                identityPrompt: "You are WVY.",
                instructionPrompt: OpenRouterConfig.defaultInstructionPrompt
            ),
            AgentProfile(
                slotIndex: 1,
                isEnabled: false,
                modelID: defaultModelID,
                name: "",
                identityPrompt: "",
                instructionPrompt: ""
            ),
            AgentProfile(
                slotIndex: 2,
                isEnabled: false,
                modelID: defaultModelID,
                name: "",
                identityPrompt: "",
                instructionPrompt: ""
            ),
            AgentProfile(
                slotIndex: 3,
                isEnabled: false,
                modelID: defaultModelID,
                name: "",
                identityPrompt: "",
                instructionPrompt: ""
            )
        ]
    }
}

struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var isUser: Bool
    var createdAt: Date
    var agentName: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case isUser
        case createdAt
        case agentName
    }

    init(
        id: UUID = UUID(),
        text: String,
        isUser: Bool,
        createdAt: Date = .now,
        agentName: String? = nil
    ) {
        self.id = id
        self.text = text
        self.isUser = isUser
        self.createdAt = createdAt
        self.agentName = agentName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        isUser = try container.decode(Bool.self, forKey: .isUser)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        agentName = try container.decodeIfPresent(String.self, forKey: .agentName)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(isUser, forKey: .isUser)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(agentName, forKey: .agentName)
    }
}

struct ChatSession: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isUntitled: Bool
    var projectName: String?
    var messages: [ChatMessage]
    var mode: WVYChatMode
    var agents: [AgentProfile]
    var maxRepliesPerAgent: Int
    var maxResponsesPerAgent: Int
    var recommendedSleepMinutes: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt
        case updatedAt
        case isUntitled
        case projectName
        case messages
        case mode
        case agents
        case maxRepliesPerAgent
        case maxResponsesPerAgent
        case recommendedSleepMinutes
    }

    init(
        id: UUID = UUID(),
        title: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isUntitled: Bool = true,
        projectName: String? = nil,
        messages: [ChatMessage] = [],
        mode: WVYChatMode = .wvy,
        agents: [AgentProfile] = AgentProfile.defaultAgents(),
        maxRepliesPerAgent: Int = 1,
        maxResponsesPerAgent: Int = 1,
        recommendedSleepMinutes: Int = 3
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isUntitled = isUntitled
        self.projectName = projectName
        self.messages = messages
        self.mode = mode
        self.agents = agents
        self.maxRepliesPerAgent = maxRepliesPerAgent
        self.maxResponsesPerAgent = maxResponsesPerAgent
        self.recommendedSleepMinutes = recommendedSleepMinutes
        repairAgentState()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isUntitled = try container.decode(Bool.self, forKey: .isUntitled)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName)
        messages = try container.decode([ChatMessage].self, forKey: .messages)
        mode = try container.decodeIfPresent(WVYChatMode.self, forKey: .mode) ?? .wvy
        agents = try container.decodeIfPresent([AgentProfile].self, forKey: .agents) ?? AgentProfile.defaultAgents()
        maxRepliesPerAgent = try container.decodeIfPresent(Int.self, forKey: .maxRepliesPerAgent) ?? 1
        maxResponsesPerAgent = try container.decodeIfPresent(Int.self, forKey: .maxResponsesPerAgent) ?? 1
        recommendedSleepMinutes = try container.decodeIfPresent(Int.self, forKey: .recommendedSleepMinutes) ?? 3
        repairAgentState()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isUntitled, forKey: .isUntitled)
        try container.encodeIfPresent(projectName, forKey: .projectName)
        try container.encode(messages, forKey: .messages)
        try container.encode(mode, forKey: .mode)
        try container.encode(agents, forKey: .agents)
        try container.encode(maxRepliesPerAgent, forKey: .maxRepliesPerAgent)
        try container.encode(maxResponsesPerAgent, forKey: .maxResponsesPerAgent)
        try container.encode(recommendedSleepMinutes, forKey: .recommendedSleepMinutes)
    }

    var displayTitle: String {
        title.isEmpty ? "New Chat" : title
    }

    mutating func repairAgentState() {
        if agents.count != 4 {
            var repairedAgents = AgentProfile.defaultAgents()

            for agent in agents.prefix(4) {
                let index = max(0, min(3, agent.slotIndex))
                repairedAgents[index] = agent
            }

            agents = repairedAgents
        }

        for index in agents.indices {
            agents[index].slotIndex = index

            if agents[index].modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                agents[index].modelID = OpenRouterConfig.defaultModelID
            }

            if index == 0 {
                agents[index].isEnabled = true
                agents[index].name = "WVY"

                if agents[index].identityPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    agents[index].identityPrompt = "You are WVY."
                }

                if agents[index].instructionPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    agents[index].instructionPrompt = OpenRouterConfig.defaultInstructionPrompt
                }
            }
        }

        if maxRepliesPerAgent < 1 {
            maxRepliesPerAgent = 1
        }

        if maxRepliesPerAgent > 5 {
            maxRepliesPerAgent = 5
        }

        if maxResponsesPerAgent < 1 {
            maxResponsesPerAgent = 1
        }

        if maxResponsesPerAgent > 10 {
            maxResponsesPerAgent = 10
        }

        if recommendedSleepMinutes < 1 {
            recommendedSleepMinutes = 1
        }

        if recommendedSleepMinutes > 60 {
            recommendedSleepMinutes = 60
        }
    }

    var primaryAgent: AgentProfile {
        agents.first ?? AgentProfile.defaultAgents()[0]
    }

    var activeAdditionalAgents: [AgentProfile] {
        agents
            .filter { $0.slotIndex > 0 }
            .filter { $0.isEnabled }
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.slotIndex < $1.slotIndex }
    }
}
