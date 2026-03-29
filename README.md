# GitEdit

A native macOS editor where every file type gets a purpose-built view and git history is always one keystroke away.

## What it does

GitEdit opens any folder and renders each file type with its own optimized view — no plugins, no configuration. Drop a folder in, and it just works.

### 5 Purpose-Built Editor Views

| File Type | View | Key Features |
|---|---|---|
| **Markdown** (.md, .mdx) | Split preview | Source + live rendered preview, mode switcher (Source / Split / Preview) |
| **CSV / TSV** | Sortable table | Column type badges (Num/Date/Text/Bool), row filtering, sort by column, raw toggle |
| **JSON / YAML / TOML** | Collapsible tree | Type-colored values, expand/collapse all, parse error banner with raw fallback |
| **.env** | Key-value table | Secret masking for sensitive keys (PASSWORD, SECRET, TOKEN, KEY), show/hide all |
| **Plain text** | Clean prose | Centered 720px column, no chrome — pure writing surface |

### Ambient Git Integration

When you open a folder with a `.git` directory, git features activate automatically:

- **Gutter indicators** — shape + color coded (accessible): added, modified, deleted
- **Diff panel** — unified diff view with green/red line coloring
- **File history** — commit list with author, message, relative date
- **Blame** — per-line annotations with hover popover for full commit details

> Note: Git panel views currently use placeholder data. Real libgit2 integration is planned for v1.5.

### Core Features

- Three-column layout: file tree sidebar + editor + git panel
- Quick Open (**Cmd+P**) with fuzzy search
- Scrollable tab bar with modified indicators
- Drag-and-drop folder opening
- Recent workspaces on welcome screen
- Full dark/light mode support via macOS semantic colors
- File tree with type-colored icons and git status decorations
- Context menu: Reveal in Finder, Copy Path, Rename, Delete

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| Cmd+O | Open folder |
| Cmd+P | Quick Open |
| Cmd+W | Close tab |
| Shift+Cmd+E | Toggle sidebar |
| Shift+Cmd+G | Toggle git panel |
| Shift+Cmd+D | Toggle diff |
| Shift+Cmd+H | File history |
| Shift+Cmd+B | Toggle blame |

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.10+
- Xcode 15+ (for development)

## Build & Run

```bash
# Clone
git clone https://github.com/shayke-cohen/GitEdit.git
cd GitEdit

# Build and run
swift run GitEdit

# Run tests (99 tests across 7 suites)
swift test
```

## Project Structure

```
GitEdit/
├── GitEditCore/           # Testable business logic (library target)
│   ├── Models/            # FileType, WorkspaceItem, EditorTab, GitTypes
│   ├── Services/          # WorkspaceService, CSVParser, EnvParser, FileWatcher
│   └── Utilities/         # FuzzySearch
├── GitEditApp/            # SwiftUI macOS app (executable target)
│   ├── GitEditApp.swift   # App entry point, commands, keyboard shortcuts
│   ├── AppState.swift     # Global state: workspace, tabs, UI toggles
│   └── Views/
│       ├── Welcome/       # Empty state with Open Folder CTA
│       ├── Sidebar/       # File tree with filter, icons, git decorations
│       ├── Editor/        # All 5 editor views + tab bar + Quick Open
│       ├── Git/           # Diff, History, Blame panels
│       └── StatusBar/     # File path, word count, file type
├── GitEditTests/          # 99 unit tests across 7 suites
└── Package.swift
```

## Tech Stack

- **SwiftUI + AppKit** — fully native macOS
- **FSEvents** — real-time file watching
- **CommonMark** — markdown rendering (via AttributedString)
- **Swift Package Manager** — build system

## Roadmap

- **v1.0** (current) — File rendering, UI shell, placeholder git views
- **v1.5** — libgit2 integration (real diff/blame/history data), stage hunks, commit from app
- **v2.0** — Branch switcher, merge conflict resolution, stash support

## License

MIT
