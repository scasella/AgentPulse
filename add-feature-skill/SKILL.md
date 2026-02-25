---
name: add-feature-skill
description: >
  Guide for adding new features to AgentPulse. Covers architecture,
  extension points, patterns, and build process.
---

## Overview

AgentPulse is a macOS menu bar app that monitors Claude Code agent teams and tasks by polling JSON files from `~/.claude/teams/` and `~/.claude/tasks/` on disk.

## Architecture

AgentPulse is a single-file SwiftUI app (`AgentPulse.swift`, ~542 lines). All data models, the data manager, views, and the app entry point live in this one file.

- **Data source**: Local JSON files under `~/.claude/` read via `FileManager` + `JSONDecoder`
- **State management**: `@Observable` class (`AgentDataManager`) with `@State` in the app and `@Bindable` in `ContentView`
- **Navigation**: Manual stack-based — `ContentView` switches between `TeamListView` and `TeamDetailView` using a `@State` optional `selectedTeam`
- **Refresh**: `Timer.scheduledTimer` in the data manager polls every 5 seconds
- **No networking**: All data comes from the local filesystem

## Key Types

| Type | Role |
|---|---|
| `TeamMember` | Codable struct — agent ID, name, type, model |
| `TeamConfig` | Codable struct — team name, description, members list |
| `TaskItem` | Codable struct — task ID, subject, status, owner, dependencies |
| `AgentDataManager` | `@Observable` class — loads teams/tasks from disk, provides computed summaries |
| `ContentView` | Root view — switches between list and detail via `selectedTeam` state |
| `TeamListView` | Scrollable list of teams with task summary badges |
| `TeamRowView` | Single team row with progress bar and member/task counts |
| `TeamDetailView` | Team detail — members section + tasks section with progress |
| `SectionHeader` | Reusable section header with title and detail text |
| `MemberRowView` | Single member row with role icon and model badge |
| `TaskRowView` | Single task row with status icon, owner label, blocked indicator |
| `AgentPulseApp` | `@main` entry point — `MenuBarExtra` with `.window` style |

## How to Add a Feature

1. **Define any new data models** at the top of `AgentPulse.swift` in the `// MARK: - Data Models` section. Make them `Codable` and `Identifiable` if they come from JSON files.

2. **Add data loading** in `AgentDataManager`. Follow the pattern of `loadTeams()` / `loadTasks()`: read a directory under `~/.claude/`, decode JSON files, store results in a `var` property. The `refresh()` method calls all loaders, so add yours there too.

3. **Add computed properties** on `AgentDataManager` for any summaries or derived data (like `totalInProgress` or `taskSummary(for:)`).

4. **Create a new view struct**. Pass data as `let` properties from the parent. For interactive state, use `@State` locally. Follow the existing pattern of `HStack`/`VStack` layouts with SF Symbols and `.font(.caption)` / `.foregroundStyle(.secondary)` styling.

5. **Wire into navigation**. If adding a new detail screen, add another case to `ContentView`'s `if/else` chain based on `selectedTeam` or a new `@State` property. If adding a section to an existing screen, insert it into `TeamDetailView`'s `VStack`.

6. **Build and test** (see Build & Test below).

## Extension Points

- **New data sources from `~/.claude/`**: Add a new `load*()` method in `AgentDataManager` that reads a new directory or file pattern, and call it from `refresh()`.
- **New view sections in TeamDetailView**: Insert a new `VStack` block between the existing Members and Tasks sections (add a `Divider()` and `SectionHeader` to match the pattern).
- **New navigation destinations**: Add a new `@State` property to `ContentView` and a new branch in the `Group` body. Wire navigation via `onTapGesture` closures and a back-button callback.
- **New menu bar info**: Modify the `label:` closure in `AgentPulseApp` to display additional summary data from `manager`.

## Conventions

- **Single file**: All code goes in `AgentPulse.swift`. Do not create additional Swift files.
- **State pattern**: `@Observable` for the data manager, `@State` for view-local state, `@Bindable` when a view needs to write to the manager.
- **SF Symbols**: Use system images consistently — `person.fill` for members, `checkmark.circle.fill` / `play.circle.fill` / `circle` for task status, `crown.fill` for team leads.
- **Color scheme**: Status colors — green for completed/running, blue for in-progress, orange for blocked, secondary/tertiary for inactive. Model colors — purple for Opus, blue for Sonnet, green for Haiku.
- **MARK comments**: Use `// MARK: -` to separate Data Models, Data Manager, Views, and App sections.
- **Naming**: PascalCase for types, camelCase for properties. View structs end with `View` (except `SectionHeader`).
- **Layout**: Fixed frame width of 340pt on `ContentView`, max scroll heights on list views.

## Build & Test

```bash
# Build
bash build.sh

# Run manually
swiftc -parse-as-library -O -o AgentPulse AgentPulse.swift && ./AgentPulse

# Test parsing logic
swift test_parse.swift
```

The build script compiles with `swiftc -parse-as-library -O` and generates `Info.plist` inline. The resulting binary runs as a menu bar app with no Dock icon (LSUIElement = true).
