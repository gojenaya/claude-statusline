#!/usr/bin/env bash
# Claude Code status line — 2 lines: Claude session | GitHub
# https://github.com/gojenaya/claude-statusline

set -f

usage_dir="${CLAUDE_USAGE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/usage}"

# ---- Subcommands (budget, usage, sync, fetch-refresh) ----
if [ "${1:-}" = "budget" ] && [ -n "${2:-}" ]; then
    [ ! -f "$usage_dir/.config" ] && echo "no config at $usage_dir/.config" && exit 1
    sed -i '' "s/^budget=.*/budget=$2/" "$usage_dir/.config"
    cat "$usage_dir/.config"; exit 0
fi
if [ "${1:-}" = "usage" ] && [ -n "${2:-}" ]; then
    [ ! -f "$usage_dir/.config" ] && echo "no config at $usage_dir/.config" && exit 1
    sed -i '' "s/^initial_usage=.*/initial_usage=$2/" "$usage_dir/.config"
    cat "$usage_dir/.config"; exit 0
fi
if [ "${1:-}" = "sync" ] && [ -n "${2:-}" ]; then
    [ ! -f "$usage_dir/.config" ] && echo "no config at $usage_dir/.config" && exit 1
    set +f
    for f in "$usage_dir"/*; do
        [ ! -f "$f" ] && continue
        base=$(basename "$f"); case "$base" in .* | *_offset) continue ;; esac
        cost=$(awk -F'\t' '{print $2}' "$f")
        [ -n "$cost" ] && printf '%s\t-%s\toffset\t0\t0\t0\n' "$(date +%s)" "$cost" > "${f}_offset"
    done
    set -f
    sed -i '' "s/^initial_usage=.*/initial_usage=$2/; s/^start_ts=.*/start_ts=0/" "$usage_dir/.config"
    cat "$usage_dir/.config"; exit 0
fi
if [ "${1:-}" = "fetch-refresh" ] && [ -n "${2:-}" ]; then
    root="$2"
    [ -d "$root/local" ] && git -C "$root" --no-optional-locks fetch --quiet 2>/dev/null
    exit 0
fi

input=$(cat)
[ -z "$input" ] && printf "Claude" && exit 0

# ===== Setup =====
# -2 safety margin: glyphs like ↻ can render 2 cols wide in some terminals,
# and an exact-width line gets its last chars clipped by the status area.
cols=$(tput cols 2>/dev/null || echo 120)
cols=$(( cols - 2 ))

# Colors: dim for labels, semantic green/orange/red for bars, blue/pink for identity
dim='\033[2m'
reset='\033[0m'
green='\033[38;2;80;200;120m'
orange='\033[38;2;255;149;0m'
red='\033[38;2;235;87;87m'
blue='\033[38;2;97;175;239m'
pink='\033[38;2;255;121;198m'

# ===== Extract =====
model=$(printf '%s' "$input"        | jq -r '.model.display_name // empty')
model="${model#Claude }"; model="${model/ context/}"
cwd=$(printf '%s' "$input"          | jq -r '.workspace.current_dir // .cwd // empty')
effort=$(printf '%s' "$input"       | jq -r '.effort.level // empty')
agent=$(printf '%s' "$input"        | jq -r '.agent.name // empty')
ctx_used=$(printf '%s' "$input"     | jq -r '.context_window.used_percentage // empty')
rl_five=$(printf '%s' "$input"      | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl_seven=$(printf '%s' "$input"     | jq -r '.rate_limits.seven_day.used_percentage // empty')
rl_resets_5h=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
now=$(date +%s)

# Rate limits come from API response headers, so a fresh session has none
# until the first message completes — fall back to the last session's values.
rl_cache="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.statusline-rate-limits"
if [ -n "$rl_five" ]; then
    printf '%s\t%s\t%s\n' "$rl_five" "$rl_resets_5h" "$rl_seven" > "$rl_cache"
elif [ -f "$rl_cache" ]; then
    IFS=$'\t' read -r c_five c_resets c_seven < "$rl_cache"
    if [ -n "$c_resets" ] && [ "$c_resets" -gt "$now" ] 2>/dev/null; then
        rl_five="$c_five"; rl_resets_5h="$c_resets"; rl_seven="$c_seven"
    fi
fi

branch=""
[ -n "$cwd" ] && branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)

# Active GitHub account — reads local gh config, no network call
gh_account=$(gh auth status 2>/dev/null | awk '
    /account / { for (i=1;i<=NF;i++) if ($i=="account") { last=$(i+1); break } }
    /Active account: true/ { print last; exit }
')

# ===== Helpers =====

make_bar() {
    local pct="${1:-0}" width="${2:-8}"
    pct=$(printf "%.0f" "$pct" 2>/dev/null); pct=${pct:-0}
    [ "$pct" -gt 100 ] && pct=100
    local filled=$(( pct * width / 100 )) s="" i=1
    while [ $i -le $width ]; do
        [ $i -le $filled ] && s+="█" || s+="░"
        i=$(( i + 1 ))
    done
    printf '%s' "$s"
}

use_color() {
    local p; p=$(printf "%.0f" "${1:-0}" 2>/dev/null); p=${p:-0}
    [ "$p" -ge 80 ] && printf '%s' "$red"   && return
    [ "$p" -ge 50 ] && printf '%s' "$orange" && return
    printf '%s' "$green"
}

fmt_clock() {
    local ts="$1"
    date -r "$ts" +%H:%M 2>/dev/null || date -d "@$ts" +%H:%M 2>/dev/null
}

shorten_path() {
    local p="$1"
    [ "${#p}" -le 50 ] && printf '%s' "$p" && return
    printf '…/%s' "$(printf '%s' "$p" | rev | cut -d'/' -f1-2 | rev)"
}

# Print left + padding + right to fill terminal width.
# llen/rlen are passed explicitly as display-column counts so we avoid
# wc -m ambiguity with multibyte unicode bar characters (█ ░ etc).
spread() {
    local left="$1" llen="$2" right="$3" rlen="$4" pad
    pad=$(( cols - llen - rlen ))
    [ "$pad" -lt 2 ] && pad=2
    printf '%b%*s%b\n' "$left" "$pad" "" "$right"
}

# "  ·  " separator: 5 display cols (· is 2 UTF-8 bytes but 1 display col)
SEP_W=5

# ===== Line 1: Claude =====
# Left:  model  ·  effort  ·  context ██░░░░ 15%
# Right: 5h ░░░░░░░░  5%   ↻ 20:20

l1_left="" l1_llen=0

l1_left+="${blue}${model}${reset}"
l1_llen=$(( l1_llen + ${#model} ))

if [ -n "$effort" ]; then
    l1_left+="${dim}  ·  ${reset}${effort}"
    l1_llen=$(( l1_llen + SEP_W + ${#effort} ))
fi
if [ -n "$agent" ]; then
    l1_left+="${dim}  ·  ${reset}${agent}"
    l1_llen=$(( l1_llen + SEP_W + ${#agent} ))
fi
if [ -n "$ctx_used" ]; then
    ctx_pct=$(printf "%.0f" "$ctx_used")
    ctx_bar_w=6
    c=$(use_color "$ctx_pct")
    l1_left+="${dim}  ·  context ${reset}${c}$(make_bar "$ctx_pct" $ctx_bar_w)${reset} ${dim}${ctx_pct}%${reset}"
    # sep(5) + "context "(8) + bar(ctx_bar_w) + " "(1) + digits + "%"(1)
    l1_llen=$(( l1_llen + SEP_W + 8 + ctx_bar_w + 1 + ${#ctx_pct} + 1 ))
fi

l1_right="" l1_rlen=0

if [ -n "$rl_resets_5h" ] && [ "$rl_resets_5h" -gt "$now" ] 2>/dev/null; then
    reset_clock=$(fmt_clock "$rl_resets_5h")
    if [ -n "$reset_clock" ]; then
        l1_right+="${dim}↻${reset} ${reset_clock}"
        # "↻"(1 display) + " "(1) + clock(${#reset_clock}, always ASCII HH:MM)
        l1_rlen=$(( l1_rlen + 1 + 1 + ${#reset_clock} ))
    fi
fi
if [ -n "$rl_five" ]; then
    f=$(printf "%.0f" "$rl_five")
    bar_w=8
    c=$(use_color "$f")
    [ "$l1_rlen" -gt 0 ] && l1_right+="   " && l1_rlen=$(( l1_rlen + 3 ))
    l1_right+="${dim}${f}%${reset} ${c}$(make_bar "$f" $bar_w)${reset}"
    # digits + "%"(1) + " "(1) + bar(bar_w)
    l1_rlen=$(( l1_rlen + ${#f} + 1 + 1 + bar_w ))
fi

spread "$l1_left" "$l1_llen" "$l1_right" "$l1_rlen"

# ===== Line 2: GitHub / Git =====
# Left:  gojenaya  ·  ⎇ main ✓
# Right: ~/my-initiatives/ditto-workflows-mcp

l2_left="" l2_llen=0
l2_right="" l2_rlen=0

if [ -n "$gh_account" ]; then
    l2_left+="${pink}${gh_account}${reset}"
    l2_llen=$(( l2_llen + ${#gh_account} ))
fi

if [ -n "$branch" ]; then
    if [ -n "$gh_account" ]; then
        l2_left+="${dim}  ·  ${reset}"
        l2_llen=$(( l2_llen + SEP_W ))
    fi
    porcelain=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)
    git_str="${dim}⎇ ${reset}${branch}"
    # "⎇ "(2 display: ⎇=1, space=1) + branch name (ASCII)
    git_vlen=$(( 2 + ${#branch} ))
    if [ -z "$porcelain" ]; then
        git_str+=" ${green}✓${reset}"
        git_vlen=$(( git_vlen + 2 ))  # " ✓" = 2 display cols
    else
        staged=$(   printf '%s\n' "$porcelain" | awk '/^[MADRC]/' | wc -l | tr -d ' ')
        modified=$( printf '%s\n' "$porcelain" | awk '/^.[MD]/'   | wc -l | tr -d ' ')
        untracked=$(printf '%s\n' "$porcelain" | awk '/^\?\?/'    | wc -l | tr -d ' ')
        if [ "$staged"    -gt 0 ]; then
            git_str+=" ${dim}+${staged}${reset}"
            git_vlen=$(( git_vlen + 1 + 1 + ${#staged} ))
        fi
        if [ "$modified"  -gt 0 ]; then
            git_str+=" ${dim}~${modified}${reset}"
            git_vlen=$(( git_vlen + 1 + 1 + ${#modified} ))
        fi
        if [ "$untracked" -gt 0 ]; then
            git_str+=" ${dim}?${untracked}${reset}"
            git_vlen=$(( git_vlen + 1 + 1 + ${#untracked} ))
        fi
    fi
    unpushed=$(git -C "$cwd" --no-optional-locks rev-list --count @{u}..HEAD 2>/dev/null)
    if [ -n "$unpushed" ] && [ "$unpushed" -gt 0 ]; then
        git_str+=" ${dim}⇡${unpushed}${reset}"
        git_vlen=$(( git_vlen + 1 + 1 + ${#unpushed} ))  # " ⇡"(2) + digits
    fi
    unpulled=$(git -C "$cwd" --no-optional-locks rev-list --count HEAD..@{u} 2>/dev/null)
    if [ -n "$unpulled" ] && [ "$unpulled" -gt 0 ]; then
        git_str+=" ${dim}⇣${unpulled}${reset}"
        git_vlen=$(( git_vlen + 1 + 1 + ${#unpulled} ))
    fi
    l2_left+="$git_str"
    l2_llen=$(( l2_llen + git_vlen ))
fi

if [ -n "$cwd" ]; then
    # If ~/Documents is a symlink into OneDrive, undo the resolved form for display
    cwd_display="${cwd/#$HOME\/Library\/CloudStorage\/OneDrive-Astratech\/Documents/~/Documents}"
    cwd_display="${cwd_display/#$HOME/~}"
    avail=$(( cols - l2_llen - 2 ))
    if [ "${#cwd_display}" -le "$avail" ]; then
        l2_right+="${dim}${cwd_display}${reset}"
        l2_rlen=${#cwd_display}
    else
        tail=$(printf '%s' "$cwd_display" | rev | cut -d'/' -f1-2 | rev)
        l2_right+="${dim}…/${tail}${reset}"
        l2_rlen=$(( 2 + ${#tail} ))  # "…/"(2 display: …=1, /=1) + tail (ASCII)
    fi
fi

spread "$l2_left" "$l2_llen" "$l2_right" "$l2_rlen"
