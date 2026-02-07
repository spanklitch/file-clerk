#!/bin/bash
# file-clerk installer
# Interactive setup for AI-powered desktop file organizer

set -euo pipefail

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${BLUE}[info]${NC} $1"; }
ok()    { echo -e "${GREEN}[ok]${NC} $1"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $1"; }
fail()  { echo -e "${RED}[error]${NC} $1"; }
ask()   { echo -en "${BOLD}$1${NC}"; }

CLERK_HOME="$(cd "$(dirname "$0")" && pwd)"
HAS_TKINTER=true

# ══════════════════════════════════════
# Welcome
# ══════════════════════════════════════
echo ""
echo -e "${BOLD} ╔══════════════════════════════════════╗${NC}"
echo -e "${BOLD} ║    File Clerk — AI Desktop Filer     ║${NC}"
echo -e "${BOLD} ║           Installer v1.0             ║${NC}"
echo -e "${BOLD} ╚══════════════════════════════════════╝${NC}"
echo ""
echo "  This will set up File Clerk to automatically"
echo "  organize files from your Desktop into your"
echo "  Documents folder using AI."
echo ""

# ══════════════════════════════════════
# OS Detection
# ══════════════════════════════════════
OS="$(uname -s)"
case "$OS" in
    Linux)  PLATFORM="linux" ;;
    Darwin) PLATFORM="macos" ;;
    *)      fail "Unsupported OS: $OS. File Clerk supports Linux and macOS."; exit 1 ;;
esac
ok "Platform: $PLATFORM"

# ══════════════════════════════════════
# Prerequisites
# ══════════════════════════════════════
echo ""
info "Checking prerequisites..."
echo ""

# Python 3
if command -v python3 &>/dev/null; then
    PYTHON_VERSION=$(python3 --version 2>&1)
    ok "Python 3 found: $PYTHON_VERSION"
else
    fail "Python 3 is required but not found."
    echo ""
    if [ "$PLATFORM" = "linux" ]; then
        echo "  Install it with:  sudo apt install python3"
    else
        echo "  Install it with:  brew install python3"
    fi
    exit 1
fi

# tkinter
if python3 -c "import tkinter" 2>/dev/null; then
    ok "tkinter available (GUI search will work)"
else
    warn "tkinter not found. The GUI search tool won't work."
    echo ""
    if [ "$PLATFORM" = "linux" ]; then
        echo "  Install it with:  sudo apt install python3-tk"
    else
        echo "  tkinter is included with Python from python.org or brew"
    fi
    echo ""
    ask "Continue without GUI support? [Y/n] "
    read -r REPLY
    if [[ "$REPLY" =~ ^[Nn] ]]; then
        exit 1
    fi
    HAS_TKINTER=false
fi

# SQLite (via Python)
if python3 -c "import sqlite3" 2>/dev/null; then
    ok "SQLite support available"
else
    fail "Python sqlite3 module not found. This is unusual — reinstall Python."
    exit 1
fi

# Claude CLI
CLAUDE_CMD=""
for candidate in \
    "$(command -v claude 2>/dev/null || true)" \
    "$HOME/.local/bin/claude" \
    "/usr/local/bin/claude" \
    ; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        CLAUDE_CMD="$candidate"
        break
    fi
done

# Check nvm paths too
if [ -z "$CLAUDE_CMD" ] && [ -d "$HOME/.nvm/versions/node" ]; then
    NVM_NODE=$(ls "$HOME/.nvm/versions/node" 2>/dev/null | tail -1)
    if [ -n "$NVM_NODE" ] && [ -x "$HOME/.nvm/versions/node/$NVM_NODE/bin/claude" ]; then
        CLAUDE_CMD="$HOME/.nvm/versions/node/$NVM_NODE/bin/claude"
    fi
fi

if [ -n "$CLAUDE_CMD" ]; then
    ok "Claude CLI found: $CLAUDE_CMD"
else
    warn "Claude Code CLI not found."
    echo ""
    echo "  File Clerk uses Claude Code to read and organize your files."
    echo "  The GUI search works without it, but automatic filing requires it."
    echo ""
    echo "  To install Claude Code later:"
    echo "    npm install -g @anthropic-ai/claude-code"
    echo ""
    ask "Continue without Claude CLI? [Y/n] "
    read -r REPLY
    if [[ "$REPLY" =~ ^[Nn] ]]; then
        exit 1
    fi
    CLAUDE_CMD="claude"
fi

# ══════════════════════════════════════
# Directory Configuration
# ══════════════════════════════════════
echo ""
info "Let's configure your directories."
echo ""

# Inbox (where new files appear)
if [ "$PLATFORM" = "linux" ] && command -v xdg-user-dir &>/dev/null; then
    DEFAULT_INBOX="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
else
    DEFAULT_INBOX="$HOME/Desktop"
fi

echo "  The inbox is where you drop files that need organizing."
echo "  (Usually your Desktop.)"
echo ""
ask "  Inbox directory [$DEFAULT_INBOX]: "
read -r INBOX_DIR
INBOX_DIR="${INBOX_DIR:-$DEFAULT_INBOX}"
INBOX_DIR="${INBOX_DIR/#\~/$HOME}"

if [ ! -d "$INBOX_DIR" ]; then
    warn "Directory does not exist: $INBOX_DIR"
    ask "  Create it? [Y/n] "
    read -r REPLY
    if [[ "$REPLY" =~ ^[Nn] ]]; then
        fail "Inbox directory must exist. Aborting."
        exit 1
    fi
    mkdir -p "$INBOX_DIR"
    ok "Created $INBOX_DIR"
else
    ok "Inbox: $INBOX_DIR"
fi

# Documents (where organized files go)
if [ "$PLATFORM" = "linux" ] && command -v xdg-user-dir &>/dev/null; then
    DEFAULT_DOCS="$(xdg-user-dir DOCUMENTS 2>/dev/null || echo "$HOME/Documents")"
else
    DEFAULT_DOCS="$HOME/Documents"
fi

echo ""
echo "  The documents directory is where organized files are stored."
echo "  File Clerk will create category subfolders here."
echo ""
ask "  Documents directory [$DEFAULT_DOCS]: "
read -r DOCS_DIR
DOCS_DIR="${DOCS_DIR:-$DEFAULT_DOCS}"
DOCS_DIR="${DOCS_DIR/#\~/$HOME}"

if [ ! -d "$DOCS_DIR" ]; then
    warn "Directory does not exist: $DOCS_DIR"
    ask "  Create it? [Y/n] "
    read -r REPLY
    if [[ "$REPLY" =~ ^[Nn] ]]; then
        fail "Documents directory must exist. Aborting."
        exit 1
    fi
    mkdir -p "$DOCS_DIR"
    ok "Created $DOCS_DIR"
else
    ok "Documents: $DOCS_DIR"
fi

# ══════════════════════════════════════
# Create Default Folder Categories
# ══════════════════════════════════════
echo ""
info "Setting up default folder categories..."
echo ""

CATEGORIES=(
    "Credentials"
    "Credentials/Remote-Access"
    "Credentials/Service-Keys"
    "Projects"
    "Business"
    "System"
    "System/Troubleshooting"
    "System/Backup-Scripts"
    "Reference"
    "Archive"
)

for cat in "${CATEGORIES[@]}"; do
    target="$DOCS_DIR/$cat"
    if [ -d "$target" ]; then
        echo "    exists:  $cat/"
    else
        mkdir -p "$target"
        echo "    created: $cat/"
    fi
done
echo ""
ok "Folder categories ready"

# ══════════════════════════════════════
# Write Configuration
# ══════════════════════════════════════
DB_PATH="$CLERK_HOME/index.sqlite"

cat > "$CLERK_HOME/config.env" << CONF
# file-clerk configuration
# Generated by install.sh on $(date)
# Edit paths below if you move things around.

CLERK_HOME="$CLERK_HOME"
INBOX_DIR="$INBOX_DIR"
DOCS_DIR="$DOCS_DIR"
CLAUDE_CMD="$CLAUDE_CMD"
DB_PATH="$DB_PATH"
CONF

ok "Configuration saved to config.env"

# ══════════════════════════════════════
# Initialize Search Index
# ══════════════════════════════════════
info "Initializing search index..."
python3 "$CLERK_HOME/index-manager.py" init
ok "Search index ready"

# ══════════════════════════════════════
# Optional: Cron Job
# ══════════════════════════════════════
echo ""
info "File Clerk can run automatically every morning at 7:00 AM"
info "to organize any new files dropped in your inbox."
echo ""
ask "Install daily cron job? [Y/n] "
read -r REPLY

if [[ ! "$REPLY" =~ ^[Nn] ]]; then
    CRON_LINE="0 7 * * * $CLERK_HOME/clerk.sh"

    if crontab -l 2>/dev/null | grep -qF "file-clerk" || \
       crontab -l 2>/dev/null | grep -qF "$CLERK_HOME/clerk.sh"; then
        warn "A file-clerk cron job already exists. Replacing it."
        (crontab -l 2>/dev/null | grep -vF "file-clerk" | grep -vF "$CLERK_HOME/clerk.sh"; \
         echo "# file-clerk: AI desktop organizer"; \
         echo "$CRON_LINE") | crontab -
    else
        (crontab -l 2>/dev/null; \
         echo ""; \
         echo "# file-clerk: AI desktop organizer"; \
         echo "$CRON_LINE") | crontab -
    fi
    ok "Cron job installed (daily at 7:00 AM)"
    echo "    To change the schedule: crontab -e"
else
    info "Skipped. Run manually anytime: $CLERK_HOME/clerk.sh"
fi

# ══════════════════════════════════════
# Optional: Desktop Launcher (Linux)
# ══════════════════════════════════════
if [ "$PLATFORM" = "linux" ] && [ "$HAS_TKINTER" = "true" ]; then
    echo ""
    info "Create a desktop shortcut for the File Finder GUI?"
    ask "Install launcher on your desktop? [Y/n] "
    read -r REPLY

    if [[ ! "$REPLY" =~ ^[Nn] ]]; then
        DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"

        DESKTOP_FILE="$DESKTOP_DIR/File-Finder.desktop"
        cat > "$DESKTOP_FILE" << DESK
[Desktop Entry]
Version=1.0
Type=Application
Name=File Finder
Comment=Search your organized files
Exec=/usr/bin/python3 $CLERK_HOME/file-finder-gui.py
Icon=$CLERK_HOME/assets/logo.png
Terminal=false
Categories=Utility;
StartupNotify=true
DESK
        chmod +x "$DESKTOP_FILE"
        ok "Desktop launcher created"

        # Also install to applications menu
        APP_DIR="$HOME/.local/share/applications"
        mkdir -p "$APP_DIR"
        cp "$DESKTOP_FILE" "$APP_DIR/file-finder.desktop"
        ok "Added to applications menu"
    fi
elif [ "$PLATFORM" = "macos" ] && [ "$HAS_TKINTER" = "true" ]; then
    echo ""
    info "To launch the File Finder GUI on macOS:"
    echo "    python3 $CLERK_HOME/file-finder-gui.py"
    echo ""
    info "Tip: Create an Automator app or alias for quick access."
fi

# ══════════════════════════════════════
# Done!
# ══════════════════════════════════════
echo ""
echo -e "${GREEN}══════════════════════════════════════${NC}"
echo ""
ok "File Clerk is installed!"
echo ""
echo "  Configuration:  $CLERK_HOME/config.env"
echo "  Inbox:          $INBOX_DIR"
echo "  Documents:      $DOCS_DIR"
echo "  Search index:   $DB_PATH"
echo ""
echo -e "  ${BOLD}How to use:${NC}"
echo "    1. Drop files in your inbox ($INBOX_DIR)"
echo "    2. They'll be organized automatically at 7 AM"
echo "       Or run now:  $CLERK_HOME/clerk.sh"
echo "    3. Search later:"
echo "       CLI:  $CLERK_HOME/find.sh \"what you're looking for\""
if [ "$HAS_TKINTER" = "true" ]; then
echo "       GUI:  Double-click File Finder on your desktop"
fi
echo ""
echo "  To uninstall:  $CLERK_HOME/uninstall.sh"
echo ""
