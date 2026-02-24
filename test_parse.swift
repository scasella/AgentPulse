import Foundation

// Duplicate data models for testing
struct TeamMember: Codable {
    let agentId: String
    let name: String
    let agentType: String
    let model: String
    let joinedAt: Double?
    let cwd: String?
}

struct TeamConfig: Codable {
    let name: String
    let description: String
    let createdAt: Double
    let members: [TeamMember]
}

struct TaskItem: Codable {
    let id: String
    let subject: String
    let description: String
    let status: String
    let owner: String?
    let blockedBy: [String]?
    let blocks: [String]?
    let activeForm: String?
}

var passed = 0
var failed = 0

func assert(_ condition: Bool, _ msg: String) {
    if condition {
        passed += 1
        print("  PASS: \(msg)")
    } else {
        failed += 1
        print("  FAIL: \(msg)")
    }
}

// Test 1: Load teams
print("--- Test: Load Teams ---")
let claudeDir = NSHomeDirectory() + "/.claude"
let teamsDir = claudeDir + "/teams"

let teamEntries = (try? FileManager.default.contentsOfDirectory(atPath: teamsDir))?.filter { !$0.hasPrefix(".") } ?? []
assert(teamEntries.count > 0, "Found \(teamEntries.count) team directories")

var loadedTeams: [TeamConfig] = []
for entry in teamEntries {
    let configPath = teamsDir + "/" + entry + "/config.json"
    if let data = FileManager.default.contents(atPath: configPath),
       let config = try? JSONDecoder().decode(TeamConfig.self, from: data) {
        loadedTeams.append(config)
        assert(true, "Parsed team: \(config.name) (\(config.members.count) members)")
    } else {
        // Not all team dirs have config.json — check if it exists
        if FileManager.default.fileExists(atPath: configPath) {
            assert(false, "Failed to parse \(entry)/config.json")
        } else {
            print("  SKIP: \(entry) has no config.json")
        }
    }
}

assert(loadedTeams.count > 0, "Loaded \(loadedTeams.count) teams total")

// Test 2: Load tasks for each team
print("\n--- Test: Load Tasks ---")
let tasksDir = claudeDir + "/tasks"

for team in loadedTeams {
    let teamTaskDir = tasksDir + "/" + team.name
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: teamTaskDir) else {
        print("  SKIP: No tasks directory for \(team.name)")
        continue
    }

    let jsonFiles = entries.filter { $0.hasSuffix(".json") }
    var tasks: [TaskItem] = []
    for file in jsonFiles {
        let path = teamTaskDir + "/" + file
        if let data = FileManager.default.contents(atPath: path),
           let task = try? JSONDecoder().decode(TaskItem.self, from: data) {
            tasks.append(task)
        } else {
            assert(false, "Failed to parse task \(file) in \(team.name)")
        }
    }

    let completed = tasks.filter { $0.status == "completed" }.count
    let inProgress = tasks.filter { $0.status == "in_progress" }.count
    let pending = tasks.filter { $0.status == "pending" }.count
    let blocked = tasks.filter { ($0.blockedBy ?? []).count > 0 }.count

    assert(tasks.count == jsonFiles.count, "\(team.name): parsed \(tasks.count)/\(jsonFiles.count) tasks")
    print("    Completed: \(completed), In Progress: \(inProgress), Pending: \(pending), Blocked: \(blocked)")
}

// Test 3: Member model parsing
print("\n--- Test: Member Models ---")
for team in loadedTeams {
    for member in team.members {
        let short: String
        if member.model.contains("opus") { short = "Opus" }
        else if member.model.contains("sonnet") { short = "Sonnet" }
        else if member.model.contains("haiku") { short = "Haiku" }
        else { short = member.model }

        assert(!short.isEmpty, "\(member.name) -> \(short) (type: \(member.agentType))")
    }
}

// Test 4: Verify specific demo team
print("\n--- Test: Demo Chat Team ---")
if let demoTeam = loadedTeams.first(where: { $0.name == "demo-chat-team" }) {
    assert(demoTeam.members.count == 4, "demo-chat-team has 4 members")
    assert(demoTeam.members.contains(where: { $0.agentType == "team-lead" }), "Has a team lead")
    assert(!demoTeam.description.isEmpty, "Has description")
} else {
    print("  SKIP: demo-chat-team not found")
}

// Summary
print("\n=== Results: \(passed) passed, \(failed) failed ===")
if failed > 0 { exit(1) }
