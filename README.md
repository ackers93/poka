# Poka

A simple Obsidian-style Markdown notes app for **macOS** and **iOS**. Poka does not sync through a server — you pick a **vault folder** on disk or in **iCloud Drive**, and every note is a plain `.md` file.

## Features

- Open any folder as a vault (local or iCloud Drive)
- Sidebar list of Markdown files (including nested folders)
- Notion-style block editor (type `/` for headings, lists, quotes, code, dividers)
- Notes still save as plain `.md` on disk
- Auto-save while you type
- macOS: reveal vault in Finder, ⌘N for new note

## Requirements

- Xcode 16+ (Swift 6)
- macOS 14+ / iOS 17+

## Run the app (Xcode)

You need **Xcode** from the Mac App Store. Poka is not a script or web app — you run it from Xcode like any SwiftUI project.

1. **Open the project** in Xcode:
   ```bash
   open /Users/ackers/Desktop/code/poka/Poka.xcodeproj
   ```
   Or in Finder: open `Desktop/code/poka` and double-click **`Poka.xcodeproj`**. Swift sources live in that same folder (`Models/`, `Views/`, etc.).

2. In the **Xcode toolbar** (top left, next to the stop button), open the **scheme** menu. It does *not* say “Poka” — pick one of:
   - **`Poka_macOS`** — Mac app (recommended on your Mac)
   - **`Poka_iOS`** — iPhone/iPad simulator

3. Next to the scheme, open the **destination** menu:
   - For macOS: **My Mac**
   - For iOS: an **iPhone simulator** (e.g. iPhone 17)

4. Press **Run** (▶) or **⌘R**. The first build can take a minute.

5. When the app opens, click **Choose folder…** and select your notes directory.

### Regenerating the Xcode project

Only if you edit `project.yml`:

```bash
brew install xcodegen   # once
cd /Users/ackers/Desktop/code/poka
xcodegen generate
```

### Choosing a vault

- **macOS:** Click **Choose folder…** and select a directory (e.g. `~/Library/Mobile Documents/com~apple~CloudDocs/Notes` for iCloud Drive).
- **iOS:** Use the folder picker and select a location in Files (including iCloud Drive).

Poka remembers the folder via a security-scoped bookmark so you can reopen the app without picking again.

## Project layout

```
poka/                    repo root — app source + Xcode project
  PokaApp.swift          App entry
  Models/Note.swift
  Services/              Vault + note file I/O
  Views/                 SwiftUI screens
  Poka.xcodeproj
  project.yml            XcodeGen spec
```

## Roadmap ideas

- Wikilinks `[[note]]`, tags, and full-text search
- Optional Git sync for vaults
- Custom themes and editor modes
