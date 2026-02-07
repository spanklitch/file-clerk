#!/bin/bash
# file-clerk finder: Ask AI to find a file
#
# Usage: ./find.sh "that spreadsheet about the server migration"
#        ./find.sh "bob's remote access credentials"

set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: find.sh <description of what you're looking for>"
    echo ""
    echo "Examples:"
    echo '  ./find.sh "remote access credentials"'
    echo '  ./find.sh "gpu lockup fix"'
    echo '  ./find.sh "market analysis data"'
    exit 1
fi

CLERK_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$CLERK_DIR/config.env"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: config.env not found. Run install.sh first." >&2
    exit 1
fi
source "$CONFIG_FILE"

QUERY="$*"
PROMPT_FILE="$CLERK_DIR/prompt-finder.md"

# Render prompt template
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

"$CLAUDE_CMD" -p "$PROMPT

The user is looking for: $QUERY" \
    --allowedTools "Read,Glob,Grep,Bash(python3),Bash(ls)" \
    --max-turns 10 \
    --output-format text
