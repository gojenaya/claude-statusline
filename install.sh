#!/usr/bin/env bash
# Wire statusline.sh into ~/.claude/settings.json
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
statusline="$script_dir/statusline.sh"
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
settings="$config_dir/settings.json"

command -v jq >/dev/null || { echo "install.sh needs jq (brew install jq)" >&2; exit 1; }
chmod +x "$statusline" "$script_dir/switch-github.sh"

# Prefer $HOME over a literal path so the same settings file works across machines
cmd="bash \"${statusline/#$HOME/\$HOME}\""

mkdir -p "$config_dir"
if [ -f "$settings" ]; then
    cp "$settings" "$settings.bak-statusline-$(date +%Y%m%d%H%M%S)"
else
    echo '{}' > "$settings"
fi

tmp=$(mktemp)
jq --arg cmd "$cmd" '.statusLine = {type: "command", command: $cmd}' "$settings" > "$tmp"
mv "$tmp" "$settings"

echo "statusLine set to: $cmd"
echo "Restart Claude Code to pick it up."
