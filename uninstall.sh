#!/bin/bash
# file-clerk uninstaller
# Removes cron job, desktop launchers, and optionally the index.
# Never touches your organized documents.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[ok]${NC} $1"; }
warn() { echo -e "${YELLOW}[warn]${NC} $1"; }
ask()  { echo -en "${BOLD}$1${NC}"; }

CLERK_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$CLERK_DIR/config.env" 2>/dev/null || true

echo ""
echo -e "${BOLD}File Clerk — Uninstaller${NC}"
echo ""

# 1. Remove cron job
if crontab -l 2>/dev/null | grep -qF "clerk.sh"; then
    echo "Removing cron job..."
    (crontab -l 2>/dev/null | grep -vF "file-clerk" | grep -vF "clerk.sh") | crontab - 2>/dev/null || true
    ok "Cron job removed"
else
    echo "  No cron job found."
fi

# 2. Remove .desktop launchers
OS="$(uname -s)"
if [ "$OS" = "Linux" ]; then
    DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
    for f in \
        "$DESKTOP_DIR/File-Finder.desktop" \
        "$HOME/.local/share/applications/file-finder.desktop" \
        ; do
        if [ -f "$f" ]; then
            echo "  Removing launcher: $f"
            rm "$f"
        fi
    done
    ok "Desktop launchers removed"
fi

# 3. Ask about the index
echo ""
echo "  Your search index contains metadata about your organized files."
ask "  Delete the search index? [y/N] "
read -r REPLY
if [[ "$REPLY" =~ ^[Yy] ]]; then
    rm -f "$CLERK_DIR/index.sqlite" "$CLERK_DIR/index.sqlite-journal" "$CLERK_DIR/index.sqlite-wal"
    ok "Index deleted"
else
    echo "  Index kept."
fi

# 4. Ask about config
ask "  Delete configuration? [y/N] "
read -r REPLY
if [[ "$REPLY" =~ ^[Yy] ]]; then
    rm -f "$CLERK_DIR/config.env"
    ok "Config deleted"
else
    echo "  Config kept."
fi

# 5. Clean up logs
ask "  Delete log files? [y/N] "
read -r REPLY
if [[ "$REPLY" =~ ^[Yy] ]]; then
    rm -rf "$CLERK_DIR/logs"
    ok "Logs deleted"
else
    echo "  Logs kept."
fi

# 6. Final note
echo ""
echo "  NOTE: Your organized files in ${DOCS_DIR:-your Documents folder} were NOT touched."
echo "        File Clerk only removes its own configuration and tools."
echo ""
echo "  To fully remove the file-clerk source code:"
echo "    rm -rf $CLERK_DIR"
echo ""
ok "Uninstall complete."
