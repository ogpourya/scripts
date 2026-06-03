#!/usr/bin/env bash
set -euo pipefail

# ── dependency check ──────────────────────────────────────────────────────────
if ! command -v gum &>/dev/null; then
  echo ""
  echo "  ✗ 'gum' is not installed."
  echo ""
  echo "  Install it:"
  echo "    brew install gum"
  echo "    sudo apt install gum"
  echo "    go install github.com/charmbracelet/gum@latest"
  echo ""
  echo "  Docs: https://github.com/charmbracelet/gum"
  exit 1
fi

# ── rewrite: swap host only, touch nothing else ───────────────────────────────
rewrite() {
  local uri="$1"
  local new_ip="$2"

  local scheme after_scheme fragment no_frag query no_query user hostpath path hostport host port

  scheme="${uri%%://*}"
  after_scheme="${uri#*://}"

  fragment="${after_scheme##*#}"
  no_frag="${after_scheme%#*}"

  query="${no_frag#*\?}"
  no_query="${no_frag%%\?*}"

  user="${no_query%%@*}"
  hostpath="${no_query#*@}"

  if [[ "$hostpath" == */* ]]; then
    path="/${hostpath#*/}"
    hostport="${hostpath%%/*}"
  else
    path=""
    hostport="$hostpath"
  fi

  port="${hostport##*:}"

  echo "${scheme}://${user}@${new_ip}:${port}${path}?${query}#${fragment}"
}

# ── UI ────────────────────────────────────────────────────────────────────────
gum style \
  --border double --border-foreground 99 \
  --padding "1 4" --margin "1 0" \
  "VLESS / Trojan Config IP Rewriter"

gum style --foreground 212 "① Paste your config URI:"
CONFIG=$(gum input \
  --placeholder "vless://uuid@host:port?...#name" \
  --width 120)

[[ -z "$CONFIG" ]] && { gum style --foreground 196 "✗ No config. Aborting."; exit 1; }

gum style --foreground 212 "② Paste your clean IPs (one per line):"
RAW=$(gum write \
  --placeholder "1.2.3.4
5.6.7.8
..." \
  --width 60 --height 15)

[[ -z "$RAW" ]] && { gum style --foreground 196 "✗ No IPs. Aborting."; exit 1; }

gum style --foreground 212 "③ Output filename:"
OUT=$(gum input --placeholder "output.txt" --value "output.txt")
[[ -z "$OUT" ]] && OUT="output.txt"

# ── process ───────────────────────────────────────────────────────────────────
> "$OUT"
count=0
while IFS= read -r ip; do
  [[ -z "$ip" ]] && continue
  rewrite "$CONFIG" "$ip" >> "$OUT"
  (( count++ ))
done <<< "$RAW"

gum style --foreground 76 "✓ $count configs saved to: $OUT"
