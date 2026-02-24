import SwiftUI
import Foundation

// MARK: - Data Models

struct TeamMember: Identifiable, Codable {
    let agentId: String
    let name: String
    let agentType: String
    let model: String
    let joinedAt: Double?
    let cwd: String?

    var id: String { agentId }

    var modelShort: String {
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
        return model
    }
}

struct TeamConfig: Identifiable, Codable {
    let name: String
    let description: String
    let createdAt: Double
    let members: [TeamMember]

    var id: String { name }

    var createdDate: Date {
        Date(timeIntervalSince1970: createdAt / 1000)
    }
}

struct TaskItem: Identifiable, Codable {
    let id: String
    let subject: String
    let description: String
    let status: String
    let owner: String?
    let blockedBy: [String]?
    let blocks: [String]?
    let activeForm: String?

    var isBlocked: Bool {
        guard let deps = blockedBy else { return false }
        return !deps.isEmpty
    }
}

// MARK: - Data Manager

@Observable
class AgentDataManager {
    var teams: [TeamConfig] = []
    var tasksByTeam: [String: [TaskItem]] = [:]
    var lastRefresh = Date()

    private let claudeDir: String
    private var timer: Timer?

    init() {
        claudeDir = NSHomeDirectory() + "/.claude"
        refresh()
        startAutoRefresh()
    }

    func startAutoRefresh() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        loadTeams()
        loadTasks()
        lastRefresh = Date()
    }

    private func loadTeams() {
        let teamsDir = claudeDir + "/teams"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: teamsDir) else {
            teams = []
            return
        }

        var loaded: [TeamConfig] = []
        for entry in entries where !entry.hasPrefix(".") {
            let configPath = teamsDir + "/" + entry + "/config.json"
            guard let data = FileManager.default.contents(atPath: configPath),
                  let config = try? JSONDecoder().decode(TeamConfig.self, from: data) else {
                continue
            }
            loaded.append(config)
        }
        teams = loaded.sorted { $0.createdAt > $1.createdAt }
    }

    private func loadTasks() {
        let tasksDir = claudeDir + "/tasks"
        var allTasks: [String: [TaskItem]] = [:]

        for team in teams {
            let teamTaskDir = tasksDir + "/" + team.name
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: teamTaskDir) else {
                continue
            }

            var tasks: [TaskItem] = []
            for entry in entries where entry.hasSuffix(".json") {
                let taskPath = teamTaskDir + "/" + entry
                guard let data = FileManager.default.contents(atPath: taskPath),
                      let task = try? JSONDecoder().decode(TaskItem.self, from: data) else {
                    continue
                }
                tasks.append(task)
            }
            allTasks[team.name] = tasks.sorted {
                (Int($0.id) ?? 0) < (Int($1.id) ?? 0)
            }
        }
        tasksByTeam = allTasks
    }

    var totalInProgress: Int {
        tasksByTeam.values.flatMap { $0 }.filter { $0.status == "in_progress" }.count
    }

    func taskSummary(for teamName: String) -> (completed: Int, inProgress: Int, pending: Int, total: Int) {
        let tasks = tasksByTeam[teamName] ?? []
        let c = tasks.filter { $0.status == "completed" }.count
        let ip = tasks.filter { $0.status == "in_progress" }.count
        let p = tasks.filter { $0.status == "pending" }.count
        return (c, ip, p, tasks.count)
    }
}

// MARK: - Views

struct ContentView: View {
    @Bindable var manager: AgentDataManager
    @State private var selectedTeam: String? = nil

    var body: some View {
        Group {
            if let teamName = selectedTeam,
               let team = manager.teams.first(where: { $0.name == teamName }) {
                TeamDetailView(
                    team: team,
                    tasks: manager.tasksByTeam[teamName] ?? [],
                    onBack: { selectedTeam = nil }
                )
            } else {
                TeamListView(manager: manager, onSelectTeam: { selectedTeam = $0 })
            }
        }
        .frame(width: 340)
    }
}

struct TeamListView: View {
    let manager: AgentDataManager
    let onSelectTeam: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(.blue)
                Text("AgentPulse")
                    .font(.headline)
                Spacer()
                Text("\(manager.teams.count) team\(manager.teams.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if manager.teams.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.3.sequence")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No agent teams found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Use TeamCreate in Claude Code\nto spawn a team.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(manager.teams) { team in
                            TeamRowView(
                                team: team,
                                summary: manager.taskSummary(for: team.name)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onSelectTeam(team.name) }

                            if team.id != manager.teams.last?.id {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            Divider()

            // Footer
            HStack {
                Button(action: { manager.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Refresh")

                Spacer()

                Text("Updated \(manager.lastRefresh, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Image(systemName: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Quit AgentPulse")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

struct TeamRowView: View {
    let team: TeamConfig
    let summary: (completed: Int, inProgress: Int, pending: Int, total: Int)

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(team.name)
                    .font(.system(.body, weight: .medium))

                HStack(spacing: 8) {
                    Label("\(team.members.count)", systemImage: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if summary.total > 0 {
                        HStack(spacing: 4) {
                            if summary.completed > 0 {
                                HStack(spacing: 1) {
                                    Image(systemName: "checkmark")
                                    Text("\(summary.completed)")
                                }
                                .foregroundStyle(.green)
                            }
                            if summary.inProgress > 0 {
                                HStack(spacing: 1) {
                                    Image(systemName: "play.fill")
                                    Text("\(summary.inProgress)")
                                }
                                .foregroundStyle(.blue)
                            }
                            if summary.pending > 0 {
                                HStack(spacing: 1) {
                                    Image(systemName: "circle")
                                    Text("\(summary.pending)")
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                    }
                }
            }

            Spacer()

            if summary.total > 0 {
                ProgressView(value: Double(summary.completed), total: Double(summary.total))
                    .frame(width: 50)
                    .tint(.green)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct TeamDetailView: View {
    let team: TeamConfig
    let tasks: [TaskItem]
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with back button
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Teams")
                    }
                    .font(.callout)
                }
                .buttonStyle(.borderless)

                Spacer()

                Text(team.name)
                    .font(.headline)

                Spacer()

                // Invisible balance element
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Teams")
                }
                .font(.callout)
                .opacity(0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Description
                    if !team.description.isEmpty {
                        Text(team.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }

                    // Created date
                    Text("Created \(team.createdDate, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 16)

                    // Members
                    SectionHeader(title: "MEMBERS", detail: "\(team.members.count)")
                    ForEach(team.members) { member in
                        MemberRowView(member: member)
                    }

                    if !tasks.isEmpty {
                        Divider().padding(.horizontal, 16)

                        // Tasks
                        let completed = tasks.filter { $0.status == "completed" }.count
                        SectionHeader(title: "TASKS", detail: "\(completed)/\(tasks.count) done")

                        // Progress bar
                        ProgressView(value: Double(completed), total: Double(tasks.count))
                            .tint(.green)
                            .padding(.horizontal, 16)

                        ForEach(tasks) { task in
                            TaskRowView(task: task)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 420)
        }
    }
}

struct SectionHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
    }
}

struct MemberRowView: View {
    let member: TeamMember

    var roleIcon: String {
        member.agentType == "team-lead" ? "crown.fill" : "person.fill"
    }

    var roleColor: Color {
        member.agentType == "team-lead" ? .yellow : .secondary
    }

    var modelColor: Color {
        if member.model.contains("opus") { return .purple }
        if member.model.contains("sonnet") { return .blue }
        if member.model.contains("haiku") { return .green }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: roleIcon)
                .font(.caption)
                .foregroundStyle(roleColor)
                .frame(width: 16)

            Text(member.name)
                .font(.system(.callout, weight: .medium))

            Spacer()

            Text(member.modelShort)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(modelColor.opacity(0.15))
                .foregroundStyle(modelColor)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }
}

struct TaskRowView: View {
    let task: TaskItem

    var statusIcon: String {
        switch task.status {
        case "completed": return "checkmark.circle.fill"
        case "in_progress": return "play.circle.fill"
        case "pending":
            return task.isBlocked ? "lock.circle" : "circle"
        default: return "questionmark.circle"
        }
    }

    var statusColor: Color {
        switch task.status {
        case "completed": return .green
        case "in_progress": return .blue
        case "pending":
            return task.isBlocked ? .orange : .secondary
        default: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.subject)
                    .font(.callout)
                    .strikethrough(task.status == "completed")
                    .foregroundStyle(task.status == "completed" ? .secondary : .primary)

                HStack(spacing: 6) {
                    if let owner = task.owner, !owner.isEmpty {
                        Label(owner, systemImage: "person.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let activeForm = task.activeForm, task.status == "in_progress" {
                        Text(activeForm)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .italic()
                    }
                    if task.isBlocked {
                        Label("blocked", systemImage: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - App

@main
struct AgentPulseApp: App {
    @State private var manager = AgentDataManager()

    var body: some Scene {
        MenuBarExtra {
            ContentView(manager: manager)
        } label: {
            let ip = manager.totalInProgress
            HStack(spacing: 2) {
                Image(systemName: "person.3.fill")
                if ip > 0 {
                    Text("\(ip)")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
