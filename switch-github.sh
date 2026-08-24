#!/usr/bin/env bash
# Toggle active GitHub account between gojenaya and nayanika-goje
# Usage: bash "$(dirname "$0")/switch-github.sh"
# In Claude Code chat: ! ghswitch

ACCOUNT1="gojenaya"
ACCOUNT2="nayanika-goje"

current=$(gh auth status 2>/dev/null | awk '
    /account / { for (i=1;i<=NF;i++) if ($i=="account") { last=$(i+1); break } }
    /Active account: true/ { print last; exit }
')

if [ -z "$current" ]; then
    echo "Error: could not determine active GitHub account" >&2; exit 1
fi

if [ "$current" = "$ACCOUNT1" ]; then
    next="$ACCOUNT2"
else
    next="$ACCOUNT1"
fi

gh auth switch --user "$next" 2>/dev/null && echo "GitHub: $current → $next" || {
    echo "Error switching to $next" >&2; exit 1
}
