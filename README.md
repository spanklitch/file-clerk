# File Clerk — AI-Powered Desktop File Organizer

Drop files on your Desktop. File Clerk reads them, tags them, and files them into organized folders. Search them later by description, not filename.

**The problem:** You save a file, give it some name, toss it somewhere. Six months later you know you built it but can't find it. You've been doing this for decades.

**The fix:** Let AI read your files, understand what they are, and organize them into a searchable index. You drop files on your Desktop. Every morning, File Clerk wakes up, reads each new file, files it into a logical folder, and indexes it with tags and a summary. When you need something later, just describe it.

## Before & After

**Before:** 12 files on your Desktop with names like `Plain Text.txt`, `Screenshot_2025-08-05_17-23-17.png`, and `FOCUS MUSIC`.

**After:** Clean Desktop. In your Documents folder:
```
Documents/
├── Business/
│   ├── Consulting-Strategy/AI-Consulting-Strategy-2026.txt
│   └── Market-Analysis/competitive-landscape.png
├── Credentials/
│   └── Remote-Access/VPN-Server-Credentials.txt
├── System/
│   └── Troubleshooting/GPU-Driver-Fix-2026-01-29.txt
└── Reference/
    └── Focus-Music-Playlists.txt
```

Search: `./find.sh "that GPU driver fix"` — found instantly.

## Prerequisites

- **Python 3.8+** with tkinter (for the GUI; optional)
- **Claude Code CLI** — [install guide](https://docs.anthropic.com/en/docs/claude-code)

```bash
# Install Claude Code (requires Node.js)
npm install -g @anthropic-ai/claude-code

# On Ubuntu/Debian, install tkinter if needed
sudo apt install python3-tk
```

## Install

```bash
git clone https://github.com/spanklitch/file-clerk.git
cd file-clerk
./install.sh
```

The installer will walk you through setup:
1. Checks that Python and Claude Code are available
2. Asks where your inbox is (default: `~/Desktop`)
3. Asks where organized files should go (default: `~/Documents`)
4. Creates category folders (without touching existing files)
5. Sets up the search index
6. Optionally installs a daily cron job (7 AM)
7. Optionally creates a desktop shortcut for the GUI

## How It Works

```
┌─────────────┐     7 AM cron      ┌───────────┐
│   Desktop   │ ──────────────────> │ clerk.sh  │
│  (inbox)    │                     │           │
└─────────────┘                     └─────┬─────┘
                                          │
                                          v
                                 ┌────────────────┐
                                 │  Claude Code   │
                                 │  (headless)    │
                                 │  confined tools│
                                 └───────┬────────┘
                                         │
                          ┌──────────────┼──────────────┐
                          v              v              v
                  ┌──────────┐  ┌──────────────┐  ┌─────────┐
                  │ Move to  │  │ SQLite Index │  │  Log    │
                  │ Docs/    │  │ (FTS5)       │  │ results │
                  └──────────┘  └──────┬───────┘  └─────────┘
                                       │
                  ┌────────────────────┤
                  v                    v
           ┌────────────┐     ┌────────────────┐
           │  find.sh   │     │ File Finder    │
           │ (AI search)│     │ (GUI search)   │
           └────────────┘     └────────────────┘
```

1. **You** drop a file on your Desktop (or configured inbox)
2. **clerk.sh** runs at 7 AM via cron (or manually)
3. **Claude Code** reads each new file in headless mode with confined tool access:
   - Understands the file's content
   - Chooses (or creates) an appropriate folder
   - Renames the file with a descriptive name
   - Adds it to the SQLite index with tags and a summary
4. **You search later** using either:
   - **GUI:** File Finder app (instant local search, no AI cost)
   - **CLI + AI:** `./find.sh "description"` (uses Claude to search intelligently)
   - **CLI direct:** `python3 index-manager.py search "keywords"` (instant, free)

## Safety

Claude Code runs with **confined tool access** — it can only:
- Read files (`Read`, `Glob`, `Grep`)
- Move files (`Bash(mv)`, `Bash(mkdir)`)
- Query file metadata (`Bash(ls)`, `Bash(file)`)
- Update the index (`Bash(python3)`)

It **cannot** install packages, run arbitrary code, access the network, or modify file contents. It can only move and rename.

## Usage

### Automatic (cron)
Files dropped on your Desktop are organized every morning at 7 AM. Check the logs:
```bash
cat ~/file-clerk/logs/$(date +%F).log
```

### Manual
```bash
# Organize inbox right now
./clerk.sh

# Search with AI
./find.sh "that document about market analysis"

# Search instantly (no AI, queries local index)
python3 index-manager.py search "market analysis"

# Launch GUI
python3 file-finder-gui.py
```

### GUI (File Finder)
- Type in the search box — results filter live as you type
- Click a result to see its full path, summary, and tags
- Double-click to open the file
- "Open Folder" button opens the containing directory

## Configuration

After installation, edit `config.env` to change paths:

```bash
CLERK_HOME="/home/you/file-clerk"   # Where file-clerk lives
INBOX_DIR="/home/you/Desktop"        # Where new files appear
DOCS_DIR="/home/you/Documents"       # Where organized files go
CLAUDE_CMD="/home/you/.local/bin/claude"  # Path to Claude CLI
DB_PATH="/home/you/file-clerk/index.sqlite"  # Search index
```

### Change the cron schedule
```bash
crontab -e
# Edit the "0 7 * * *" part. Examples:
# 0 7 * * *     = 7:00 AM daily
# 0 7 * * 1-5   = 7:00 AM weekdays
# */30 * * * *  = Every 30 minutes
```

### Customize filing categories
Edit `prompt-filer.md` to change the folder categories or filing strategy. The AI follows these instructions when deciding where to put files.

### Customize what gets ignored
By default, `.desktop` launcher files are ignored. Edit the `clerk.sh` `find` command to change the exclusion pattern.

## Default Folder Categories

```
Documents/
├── Credentials/          # Passwords, API keys, access info
│   ├── Remote-Access/
│   └── Service-Keys/
├── Projects/             # Project-specific docs and notes
├── Business/             # Strategy, presentations, research
├── System/               # Configs, troubleshooting, scripts
│   ├── Troubleshooting/
│   └── Backup-Scripts/
├── Reference/            # Bookmarks, playlists, how-to guides
└── Archive/              # Old data, deprecated stuff
```

The AI will create new categories as needed. These are starting points.

## Uninstall

```bash
./uninstall.sh
```

This removes the cron job and desktop launcher. Your organized files are **never** deleted. You choose whether to keep or delete the search index and configuration.

## Platform Support

| Feature | Linux | macOS |
|---------|-------|-------|
| Automatic filing (cron) | Yes | Yes |
| AI search (find.sh) | Yes | Yes |
| GUI search (File Finder) | Yes | Yes |
| Desktop launcher | Yes | Manual (Automator) |
| Default directory detection | XDG + fallback | $HOME fallback |

## Requirements

- Python 3.8+ (with `sqlite3` module — included by default)
- `tkinter` for the GUI (optional — `sudo apt install python3-tk` on Debian/Ubuntu)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) for automatic filing and AI search
- `cron` for scheduled runs (included on Linux and macOS)

## License

MIT — see [LICENSE](LICENSE)
