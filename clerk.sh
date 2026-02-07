#!/bin/bash
# file-clerk: Daily inbox filer
# Triggered by cron to scan inbox and file new items into documents
#
# Usage: ./clerk.sh

set -euo pipefail

CLERK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$CLERK_DIR/config.env"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: config.env not found. Run install.sh first." >&2
    exit 1
fi
source "$CONFIG_FILE"

LOG_DIR="$CLERK_DIR/logs"
LOG_FILE="$LOG_DIR/$(date +%F).log"
PROMPT_FILE="$CLERK_DIR/prompt-filer.md"

mkdir -p "$LOG_DIR"

echo "=== File Clerk Run: $(date) ===" >> "$LOG_FILE"

# Check if there are any non-.desktop files in inbox
NEW_FILES=$(find "$INBOX_DIR" -maxdepth 1 -type f ! -name '*.desktop' 2>/dev/null | wc -l)
NEW_DIRS=$(find "$INBOX_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
TOTAL=$((NEW_FILES + NEW_DIRS))

if [ "$TOTAL" -eq 0 ]; then
    echo "No new files in inbox. Nothing to do." >> "$LOG_FILE"
    echo "=== Done ===" >> "$LOG_FILE"
    exit 0
fi

echo "Found $NEW_FILES new files and $NEW_DIRS directories in inbox" >> "$LOG_FILE"

echo "Inbox contents:" >> "$LOG_FILE"
ls -la "$INBOX_DIR/" >> "$LOG_FILE" 2>&1

# Render prompt template — replace {{PLACEHOLDERS}} with config values
render_prompt() {
    local template_file="$1"
    sed \
        -e "s|{{INBOX_DIR}}|$INBOX_DIR|g" \
        -e "s|{{DOCS_DIR}}|$DOCS_DIR|g" \
        -e "s|{{CLERK_HOME}}|$CLERK_HOME|g" \
        -e "s|{{DB_PATH}}|$DB_PATH|g" \
        < "$template_file"
}

PROMPT=$(render_prompt "$PROMPT_FILE")

# Add current folder structure and index for context
DOCS_TREE=$(find "$DOCS_DIR" -maxdepth 3 -type d 2>/dev/null | sort)
CURRENT_INDEX=$(python3 "$CLERK_DIR/index-manager.py" list 2>/dev/null || echo "No existing index entries")

FULL_PROMPT="$PROMPT

## Current Documents Folder Tree
\`\`\`
$DOCS_TREE
\`\`\`

## Current Index Entries
\`\`\`
$CURRENT_INDEX
\`\`\`

Now scan $INBOX_DIR and process any new files (ignore .desktop launcher files)."

# Run Claude Code headless with confined tools
"$CLAUDE_CMD" -p "$FULL_PROMPT" \
    --allowedTools "Read,Glob,Grep,Bash(ls),Bash(file),Bash(mv),Bash(mkdir),Bash(cp),Bash(python3)" \
    --max-turns 20 \
    --output-format text \
    >> "$LOG_FILE" 2>&1

echo "=== Done: $(date) ===" >> "$LOG_FILE"
