#!/usr/bin/env bash
set -euo pipefail

# ── ۱. بررسی پیش‌نیاز ────────────────────────────────────────────────────────
if ! command -v gum &> /dev/null; then
  echo "Error: 'gum' is not installed."
  echo "Install it via:"
  echo "  brew install gum"
  echo "  sudo apt install gum"
  echo "  go install github.com/charmbracelet/gum@latest"
  echo "  https://github.com/charmbracelet/gum"
  exit 1
fi

# ── ۲. تابع بازنویسی با Regex ───────────────────────────────────────────────
rewrite() {
  local uri="$1"
  local new_ip="$2"
  # این الگو فقط host/ip را جدا و جایگزین می‌کند و بقیه URI دست‌نخورده می‌ماند
  if [[ "$uri" =~ ^(.*://[^@]+@)([^:/?#]+)([:/?#].*)?$ ]]; then
    echo "${BASH_REMATCH[1]}${new_ip}${BASH_REMATCH[3]}"
  else
    echo "$uri"
  fi
}

# ── ۳. دریافت متغیرها از خط فرمان (CLI) ──────────────────────────────────────
CONFIG=""
IPS_FILE=""
OUT="output.txt"
INTERACTIVE=true

while getopts "c:i:o:h" opt; do
  case $opt in
    c) CONFIG="$OPTARG" ;;
    i) IPS_FILE="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    h) 
      echo "Usage: $0 [-c config_uri] [-i clean_ips.txt] [-o output.txt]"
      exit 0 
      ;;
    *) exit 1 ;;
  esac
done

# اگر هر دو کانفیگ و فایل IP داده شده باشند، حالت تعاملی خاموش می‌شود
if [[ -n "$CONFIG" && -n "$IPS_FILE" ]]; then
  INTERACTIVE=false
fi

# ── ۴. رابط کاربری (Interactive / Non-Interactive) ───────────────────────────
if $INTERACTIVE; then
  gum style --border normal --margin "1" --padding "1" --border-foreground 212 "VLESS/Trojan Config Rewriter"
  
  CONFIG=$(gum input --placeholder "vless://uuid@host:port?...#name" --prompt "Config: " ${CONFIG:+--value "$CONFIG"})
  [[ -z "$CONFIG" ]] && exit 0

  echo "Paste clean IPs (Ctrl+D to finish):"
  RAW=$(gum write --placeholder "1.1.1.1...")
  [[ -z "$RAW" ]] && exit 0

  OUT=$(gum input --placeholder "output.txt" --value "$OUT" --prompt "Output File: ")
else
  # حالت CLI
  if [[ ! -f "$IPS_FILE" ]]; then
    echo "Error: IPS file '$IPS_FILE' not found!"
    exit 1
  fi
  RAW=$(cat "$IPS_FILE")
fi

# ── ۵. پردازش و نوشتن فایل ──────────────────────────────────────────────────
> "$OUT"
count=0

# استفاده از || [[ -n "$ip" ]] برای جلوگیری از حذف خط آخر فایل
while IFS= read -r ip || [[ -n "$ip" ]]; do
  # پاکسازی کاراکترهای اضافی مثل اسپیس و \r
  ip="${ip//$'\r'/}"
  ip="${ip// /}"
  [[ -z "$ip" ]] && continue
  
  rewrite "$CONFIG" "$ip" >> "$OUT"
  
  # رفع باگ set -e در bash (جایگزین count++)
  count=$((count + 1))
done <<< "$RAW"

# ── ۶. پیام پایان ────────────────────────────────────────────────────────────
if $INTERACTIVE; then
  gum style --foreground 212 "✓ $count configs saved to: $OUT"
else
  echo "✓ $count configs saved to: $OUT"
fi

