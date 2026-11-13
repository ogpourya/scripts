#!/usr/bin/env bash
set -euo pipefail

echo "🌐 Setting up Google Translate service for selected text (GNOME Wayland / XFCE X11)"
echo "⚠️  Running it will safely install or update the service"
echo ""

# Detect session type (wayland vs x11)
SESSION_TYPE="${XDG_SESSION_TYPE:-}"
if [ -z "$SESSION_TYPE" ]; then
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        SESSION_TYPE="wayland"
    elif [ -n "${DISPLAY:-}" ]; then
        SESSION_TYPE="x11"
    fi
fi

# Check required dependencies
echo "🔍 Checking dependencies..."
MISSING_DEPS=()

if [ "$SESSION_TYPE" = "wayland" ]; then
    command -v wl-paste >/dev/null 2>&1 || MISSING_DEPS+=("wl-clipboard")
elif [ "$SESSION_TYPE" = "x11" ]; then
    if ! command -v xclip >/dev/null 2>&1 && ! command -v xsel >/dev/null 2>&1; then
        MISSING_DEPS+=("xclip")
    fi
else
    if ! command -v wl-paste >/dev/null 2>&1 && ! command -v xclip >/dev/null 2>&1 && ! command -v xsel >/dev/null 2>&1; then
        MISSING_DEPS+=("xclip or wl-clipboard")
    fi
fi

if ! command -v python3 >/dev/null 2>&1; then
    if command -v pacman >/dev/null 2>&1; then
        MISSING_DEPS+=("python")
    else
        MISSING_DEPS+=("python3")
    fi
fi
command -v zenity >/dev/null 2>&1 || MISSING_DEPS+=("zenity")

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo "❌ Missing dependencies: ${MISSING_DEPS[*]}"
    echo ""
    echo "📦 Install them with:"
    if command -v pacman >/dev/null 2>&1; then
        echo "  sudo pacman -S --needed ${MISSING_DEPS[*]}"
    else
        echo "  sudo apt update && sudo apt install -y ${MISSING_DEPS[*]}"
    fi
    exit 1
fi

echo "✅ All required core dependencies found"
echo ""

# Parse CLI arguments if provided, otherwise prompt interactively
SRC_LANG_DEFAULT="auto"
DST_LANG_DEFAULT="fa"
SRC_LANG=""
DST_LANG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--src|--source)
            SRC_LANG="$2"
            shift 2
            ;;
        -d|--dst|--target)
            DST_LANG="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [-s <source_lang>] [-d <target_lang>]"
            echo "Example: $0 -s auto -d fa"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [ -z "$SRC_LANG" ]; then
    if [ -t 0 ]; then
        read -r -p "🔤 Source language (default: ${SRC_LANG_DEFAULT}): " USER_SRC
        SRC_LANG="${USER_SRC:-$SRC_LANG_DEFAULT}"
    else
        SRC_LANG="$SRC_LANG_DEFAULT"
    fi
fi

if [ -z "$DST_LANG" ]; then
    if [ -t 0 ]; then
        read -r -p "🎯 Target language (default: ${DST_LANG_DEFAULT}): " USER_DST
        DST_LANG="${USER_DST:-$DST_LANG_DEFAULT}"
    else
        DST_LANG="$DST_LANG_DEFAULT"
    fi
fi

# Sanitize language codes (alphanumeric and hyphens only, or auto)
sanitize_lang() {
    local val="$1"
    if [[ ! "$val" =~ ^[a-zA-Z]{2,5}(-[a-zA-Z0-9]+)?$ && "$val" != "auto" ]]; then
        echo "❌ Invalid language code: '$val'. Using 'auto'." >&2
        echo "auto"
    else
        echo "$val"
    fi
}

SRC_LANG=$(sanitize_lang "$SRC_LANG")
DST_LANG=$(sanitize_lang "$DST_LANG")

echo ""
echo "✅ Configured languages: $SRC_LANG → $DST_LANG"
echo ""

# Setup directories following XDG base directory spec
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/google-translate"
LOG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/translate"

mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$LOG_DIR"

# Write user config file
CONFIG_PATH="$CONFIG_DIR/config.env"
cat > "$CONFIG_PATH" << EOFCONFIG
# Google Translate Service Configuration
SRC_LANG="$SRC_LANG"
DST_LANG="$DST_LANG"
EOFCONFIG

chmod 600 "$CONFIG_PATH"
echo "⚙️  Saved configuration to: $CONFIG_PATH"

# Create the translation execution script
SCRIPT_PATH="$BIN_DIR/google-translate.sh"
cat > "$SCRIPT_PATH" << 'EOFSCRIPT'
#!/usr/bin/env bash
set -o pipefail

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/google-translate/config.env"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

SRC_LANG="${SRC_LANG:-auto}"
DST_LANG="${DST_LANG:-fa}"
LOG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/translate"
LOG_FILE="$LOG_DIR/translate.log"

mkdir -p "$LOG_DIR"

# Prevent unbounded log growth (> 1MB rolls over)
if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)" -gt 1048576 ]; then
    tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null && mv -f "${LOG_FILE}.tmp" "$LOG_FILE"
fi

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

log_msg "Translation request started ($SRC_LANG -> $DST_LANG)"

# Safe text capture with timeout across Wayland and X11
capture_text() {
    local text=""
    if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        text=$(timeout 1.5s wl-paste -p --type text/plain 2>/dev/null || timeout 1.5s wl-paste -p 2>/dev/null || true)
        if [ -z "${text//[[:space:]]/}" ]; then
            text=$(timeout 1.5s wl-paste --type text/plain 2>/dev/null || timeout 1.5s wl-paste 2>/dev/null || true)
        fi
    elif command -v xclip >/dev/null 2>&1; then
        text=$(timeout 1.5s xclip -o -selection primary 2>/dev/null || true)
        if [ -z "${text//[[:space:]]/}" ]; then
            text=$(timeout 1.5s xclip -o -selection clipboard 2>/dev/null || true)
        fi
    elif command -v xsel >/dev/null 2>&1; then
        text=$(timeout 1.5s xsel -op 2>/dev/null || true)
        if [ -z "${text//[[:space:]]/}" ]; then
            text=$(timeout 1.5s xsel -ob 2>/dev/null || true)
        fi
    fi
    printf '%s' "$text"
}

RAW_TEXT=$(capture_text)

# Check if captured text is empty or only whitespace
if [ -z "${RAW_TEXT//[[:space:]]/}" ]; then
    log_msg "WARNING: No text selected"
    zenity --info \
        --title="Google Translate" \
        --text="No text selected! Highlight some text and try again." \
        --timeout=3 \
        --width=320 2>/dev/null &
    exit 0
fi

log_msg "Text captured (${#RAW_TEXT} chars)"

# Python translation logic via stdin and POST request
PYTHON_SCRIPT=$(cat << 'PYEOF'
import sys
import json
import urllib.request
import urllib.parse
import urllib.error

def main():
    src = sys.argv[1] if len(sys.argv) > 1 else 'auto'
    dst = sys.argv[2] if len(sys.argv) > 2 else 'fa'
    text = sys.stdin.read()

    if not text.strip():
        sys.exit(2)

    url = f"https://translate.googleapis.com/translate_a/single?client=gtx&sl={urllib.parse.quote(src)}&tl={urllib.parse.quote(dst)}&dt=t"
    
    # Send via POST to support long text without hitting HTTP 414 URI length limits
    post_data = urllib.parse.urlencode({"q": text}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=post_data,
        headers={
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Content-Type": "application/x-www-form-urlencoded;charset=utf-8"
        }
    )

    try:
        with urllib.request.urlopen(req, timeout=12) as response:
            payload = response.read().decode("utf-8", errors="replace")
            data = json.loads(payload)

        if data and isinstance(data, list) and len(data) > 0 and isinstance(data[0], list):
            translated_segments = [item[0] for item in data[0] if isinstance(item, list) and len(item) > 0 and item[0]]
            translated_text = "".join(translated_segments).strip()
            if translated_text:
                sys.stdout.write(translated_text)
                return 0

        sys.stderr.write("Invalid response structure from translation service.\n")
        return 1

    except urllib.error.HTTPError as e:
        sys.stderr.write(f"HTTP Error {e.code}: {e.reason}\n")
        return 1
    except urllib.error.URLError as e:
        sys.stderr.write(f"Network Error: {e.reason}\n")
        return 1
    except Exception as e:
        sys.stderr.write(f"Unexpected Error: {e}\n")
        return 1

if __name__ == '__main__':
    sys.exit(main())
PYEOF
)

TRANSLATION=$(printf '%s' "$RAW_TEXT" | python3 -c "$PYTHON_SCRIPT" "$SRC_LANG" "$DST_LANG" 2>> "$LOG_FILE")
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ] || [ -z "$TRANSLATION" ]; then
    log_msg "ERROR: Translation failed (exit code $EXIT_CODE)"
    zenity --error \
        --title="Translation Failed" \
        --text="Could not translate selected text. Check network or logs:\n$LOG_FILE" \
        --timeout=5 \
        --width=350 2>/dev/null &
    exit 1
fi

log_msg "Translation succeeded (${#TRANSLATION} chars)"

# Display translation safely with --no-markup to prevent pango markup crashes on '<' and '&'
zenity --info \
    --title="Translation ($SRC_LANG → $DST_LANG)" \
    --text="$TRANSLATION" \
    --no-markup \
    --width=460 \
    --timeout=15 2>/dev/null &

EOFSCRIPT

chmod +x "$SCRIPT_PATH"
echo "✅ Translation script installed to: $SCRIPT_PATH"
echo "📝 Log file: $LOG_DIR/translate.log"

# Configure desktop keyboard shortcut (XFCE or GNOME)
echo ""
DESKTOP_ENV="${XDG_CURRENT_DESKTOP:-}${DESKTOP_SESSION:-}"
DESKTOP_ENV_LOWER="${DESKTOP_ENV,,}"

if [[ "$DESKTOP_ENV_LOWER" == *xfce* ]] || { command -v xfconf-query >/dev/null 2>&1 && [[ "$DESKTOP_ENV_LOWER" != *gnome* ]]; }; then
    echo "🔧 Configuring shortcut for XFCE (Ctrl+Q)..."
    if xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Primary>q" -n -t string -s "$SCRIPT_PATH" 2>/dev/null; then
        echo "✅ XFCE shortcut successfully registered: Ctrl+Q"
    else
        echo "⚠️  Note: Could not set XFCE shortcut automatically."
        echo "   Map Ctrl+Q in Settings -> Keyboard -> Application Shortcuts to: $SCRIPT_PATH"
    fi
elif [[ "$DESKTOP_ENV_LOWER" == *gnome* ]] || command -v gsettings >/dev/null 2>&1; then
    echo "🔧 Configuring shortcut for GNOME (Ctrl+Q)..."
    python3 - "$SCRIPT_PATH" << 'PYCONFIG'
import subprocess
import re
import sys

schema = "org.gnome.settings-daemon.plugins.media-keys"
key = "custom-keybindings"
target_path = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/translate/"
script_path = sys.argv[1] if len(sys.argv) > 1 else ""

try:
    res = subprocess.run(["gsettings", "get", schema, key], capture_output=True, text=True, check=True)
    raw = res.stdout.strip()

    paths = re.findall(r"'([^']+)'", raw)
    if target_path not in paths:
        paths.append(target_path)

    new_list_str = "[" + ", ".join(f"'{p}'" for p in paths) + "]"
    subprocess.run(["gsettings", "set", schema, key, new_list_str], check=True)

    binding_schema = f"{schema}.custom-keybinding:{target_path}"
    subprocess.run(["gsettings", "set", binding_schema, "name", "Google Translate"], check=True)
    subprocess.run(["gsettings", "set", binding_schema, "command", script_path], check=True)
    subprocess.run(["gsettings", "set", binding_schema, "binding", "<Primary>q"], check=True)
    print("✅ GNOME shortcut successfully registered: Ctrl+Q")
except Exception as e:
    print(f"⚠️  Note: Could not set GNOME shortcut automatically ({e}).")
    print(f"   You can manually map Ctrl+Q to: {script_path}")
PYCONFIG
else
    echo "ℹ️  Desktop environment not detected in this session."
    echo "   Map your preferred hotkey (e.g. Ctrl+Q) to:"
    echo "   $SCRIPT_PATH"
fi

echo ""
echo "🎉 Setup complete!"
echo "🧪 Usage: Select text and trigger $SCRIPT_PATH (or press Ctrl+Q)"
echo ""
