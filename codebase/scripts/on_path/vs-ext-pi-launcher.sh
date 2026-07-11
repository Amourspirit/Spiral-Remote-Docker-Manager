#!/usr/bin/env bash
# Pi Agent Launcher for VS Code
# 
# This script sets up environment variables needed for context-mode and Pi Agent,
# then launches the pi code agent. It sources .envrc if available, or uses defaults.
# 
# Usage: Set this script path as the "Binary Path" in the Pi Agent VS Code extension settings.

set -e

# Absolute directory containing this script (works when called from anywhere)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

PROJECT_ROOT=$SCRIPT_DIR

# Traverse upwards until we find .project-root or hit the file system root
while [[ "$PROJECT_ROOT" != "/" && ! -f "$PROJECT_ROOT/.project-root" ]]; do
  PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done

if [[ ! -f "$PROJECT_ROOT/.project-root" ]]; then
  echo "Error: Could not find .project-root in any parent directory." >&2
  exit 1
fi

# Source .envrc if it exists in project root, otherwise set defaults
if [ -f "$PROJECT_ROOT/.envrc" ]; then
    # Source .envrc from the project root
    # Use cd to ensure relative paths in .envrc resolve correctly
    cd "$PROJECT_ROOT"
    source .envrc
else
    # Set defaults if .envrc is not available
    export CONTEXT_MODE_DATA_DIR="$PROJECT_ROOT/.github"
    export CONTEXT_MODE_PROJECT_DIR="$PROJECT_ROOT"
fi

# Ensure VSCODE_CWD is always set (in case .envrc didn't set it)
export VSCODE_CWD="$PROJECT_ROOT"

export CONTEXT_MODE_PLATFORM="pi"



# Remove PI_CODING_AGENT_DIR if it exists
unset PI_CODING_AGENT_DIR
unset CLAUDE_PROJECT_DIR
unset GEMINI_PROJECT_DIR
unset OPENCODE_PROJECT_DIR
unset PI_PROJECT_DIR
unset IDEA_INITIAL_DIRECTORY
unset CURSOR_CWD

# Launch pi agent with all environment variables in place
exec pi "$@"
