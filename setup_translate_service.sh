#!/bin/bash

echo "🌐 Setting up Google Translate service for selected text (Ubuntu Wayland)"
echo "⚠️  Running it twice will override everything"
echo ""

# Check required dependencies
echo "🔍 Checking dependencies..."
MISSING_DEPS=()

# Using wl-clipboard for Wayland instead of xclip
command -v wl-paste >/dev/null 2>&1 || MISSING_DEPS+=("wl-clipboard")
command -v python3 >/dev/null 2>&1 || MISSING_DEPS+=("python3")
command -v zenity >/dev/null 2>&1 || MISSING_DEPS+=("zenity")

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo "❌ Missing dependencies: ${MISSING_DEPS[*]}"
    echo ""
    echo "📦 Install them with:"
    echo "  sudo apt install ${MISSING_DEPS[*]}"
    exit 1
fi

echo "✅ All dependencies found"
echo ""

# Get language preferences
read -p "🔤 Source language (default: auto): " SRC_LANG
SRC_LANG=${SRC_LANG:-auto}

read -p "🎯 Target language (default: fa): " DST_LANG
DST_LANG=${DST_LANG:-fa}

echo ""
echo "✅ Languages configured: $SRC_LANG → $DST_LANG"
echo ""

# Create script directory
SCRIPT_DIR="$HOME/.local/bin"
mkdir -p "$SCRIPT_DIR"

# Create log directory
LOG_DIR="$HOME/.local/share/translate"
mkdir -p "$LOG_DIR"

# Create the translation script
SCRIPT_PATH="$SCRIPT_DIR/google-translate.sh"
cat > "$SCRIPT_PATH" << 'EOFSCRIPT'
#!/bin/bash

SRC_LANG="__SRC_LANG__"
DST_LANG="__DST_LANG__"
LOG_FILE="$HOME/.local/share/translate/translate.log"

# Function to log messages
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_msg "Script started"

# Get text from Wayland PRIMARY selection (the text you just selected)
TEXT=$(wl-paste -p 2>/dev/null)

# If primary is empty, try regular clipboard as fallback
if [ -z "$TEXT" ]; then
    log_msg "Primary selection empty, trying clipboard"
    TEXT=$(wl-paste 2>/dev/null)
fi

if [ -z "$TEXT" ]; then
    zenity --info --text="No text selected! Please select text first." --timeout=3 --width=300 2>/dev/null
    log_msg "ERROR: No text captured"
    exit 1
fi

log_msg "Text captured (${#TEXT} chars)"
log_msg "Translating from $SRC_LANG to $DST_LANG"

# Use Python to translate
TRANSLATION=$(python3 -c "
import urllib.parse
import urllib.request
import json
import sys

text = sys.argv[1]
src = sys.argv[2]
dst = sys.argv[3]

try:
    encoded = urllib.parse.quote(text)
    url = f'https://translate.googleapis.com/translate_a/single?client=gtx&sl={src}&tl={dst}&dt=t&q={encoded}'
    
    req = urllib.request.Request(url)
    req.add_header('User-Agent', 'Mozilla/5.0')
    
    with urllib.request.urlopen(req, timeout=10) as response:
        data = json.loads(response.read().decode())
        
    if data and len(data) > 0 and len(data[0]) > 0:
        translation = ''.join([item[0] for item in data[0] if item[0]])
        print(translation)
    else:
        sys.exit(1)
        
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" "$TEXT" "$SRC_LANG" "$DST_LANG" 2>> "$LOG_FILE")

EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ] || [ -z "$TRANSLATION" ]; then
    zenity --error --text="Translation failed! Check logs." --timeout=3 --width=300 2>/dev/null
    log_msg "ERROR: Translation failed"
    exit 1
fi

log_msg "Translation: $TRANSLATION"

# Show translation in a popup window
zenity --info \
    --title="Translation" \
    --text="$TRANSLATION" \
    --width=450 \
    --timeout=8 2>/dev/null &

log_msg "Success!"

EOFSCRIPT

# Replace placeholders
sed -i "s/__SRC_LANG__/$SRC_LANG/g" "$SCRIPT_PATH"
sed -i "s/__DST_LANG__/$DST_LANG/g" "$SCRIPT_PATH"

chmod +x "$SCRIPT_PATH"
echo "✅ Translation script created at: $SCRIPT_PATH"
echo "📝 Log file: $LOG_DIR/translate.log"

# Configure keyboard shortcut for GNOME (Ubuntu default)
echo ""
echo "🔧 Configuring shortcut for GNOME..."

TRANSLATE_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/translate/"
KEY_SCHEMA="org.gnome.settings-daemon.plugins.media-keys"
KEY_NAME="custom-keybindings"

# get current value
CURRENT_RAW=$(gsettings get "$KEY_SCHEMA" "$KEY_NAME" 2>/dev/null || echo "[]")

# extract existing paths
mapfile -t EXISTING < <(printf '%s\n' "$CURRENT_RAW" | grep -o "'[^']*'" | sed "s/'//g")

# add new path if not present
FOUND=0
for p in "${EXISTING[@]}"; do
    if [ "$p" = "$TRANSLATE_PATH" ]; then
        FOUND=1
        break
    fi
done

if [ $FOUND -eq 0 ]; then
    EXISTING+=("$TRANSLATE_PATH")
fi

# build array string
if [ "${#EXISTING[@]}" -eq 0 ]; then
    NEW_ARRAY="[]"
else
    NEW_ARRAY="["
    for p in "${EXISTING[@]}"; do
        NEW_ARRAY+="'$p', "
    done
    NEW_ARRAY=${NEW_ARRAY%, }"]"
fi

# set the new array
gsettings set "$KEY_SCHEMA" "$KEY_NAME" "$NEW_ARRAY"

# set custom keybinding entry
gsettings set "${KEY_SCHEMA}.custom-keybinding:${TRANSLATE_PATH}" name 'Wayland Google Translate'
gsettings set "${KEY_SCHEMA}.custom-keybinding:${TRANSLATE_PATH}" command "$SCRIPT_PATH"
gsettings set "${KEY_SCHEMA}.custom-keybinding:${TRANSLATE_PATH}" binding '<Primary>q'

echo ""
echo "🎉 Setup complete!"
echo "🧪 Usage: Select any text and press Ctrl+Q"
echo ""
