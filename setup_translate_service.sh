#!/bin/bash

echo "🌐 Setting up Google Translate + TTS service for selected text"
echo "⚠️  Running it twice will override everything"
echo ""

# Check required dependencies
echo "🔍 Checking dependencies..."
MISSING_DEPS=()

command -v xclip >/dev/null 2>&1 || MISSING_DEPS+=("xclip")
command -v curl >/dev/null 2>&1 || MISSING_DEPS+=("curl")
command -v python3 >/dev/null 2>&1 || MISSING_DEPS+=("python3")
command -v zenity >/dev/null 2>&1 || MISSING_DEPS+=("zenity")
command -v espeak-ng >/dev/null 2>&1 || MISSING_DEPS+=("espeak-ng")

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo "❌ Missing dependencies: ${MISSING_DEPS[*]}"
    echo ""
    echo "📦 Install them with:"
    echo "  Debian/Ubuntu: sudo apt install ${MISSING_DEPS[*]}"
    echo "  Fedora: sudo dnf install ${MISSING_DEPS[*]}"
    echo "  Arch: sudo pacman -S ${MISSING_DEPS[*]}"
    exit 1
fi

echo "✅ All dependencies found"
echo ""

# Get language preferences
read -p "🔤 Source language (default: auto): " SRC_LANG
SRC_LANG=${SRC_LANG:-auto}

read -p "🎯 Target language (default: en): " DST_LANG
DST_LANG=${DST_LANG:-en}

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

# Get text from PRIMARY selection (the text you just selected, not clipboard)
TEXT=$(xclip -o -selection primary 2>/dev/null)

# If primary is empty, try clipboard as fallback
if [ -z "$TEXT" ]; then
    log_msg "Primary selection empty, trying clipboard"
    TEXT=$(xclip -o -selection clipboard 2>/dev/null)
fi

log_msg "Text captured (${#TEXT} chars): $TEXT"

if [ -z "$TEXT" ]; then
    zenity --info --text="No text selected! Please select text first." --timeout=3 --width=300 2>/dev/null
    log_msg "ERROR: No text captured"
    exit 1
fi

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

# Create the TTS script
TTS_SCRIPT_PATH="$SCRIPT_DIR/google-translate-tts.sh"
cat > "$TTS_SCRIPT_PATH" << 'EOFTTS'
#!/bin/bash

LOG_FILE="$HOME/.local/share/translate/tts.log"

# Function to log messages
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_msg "TTS script started"

# Get text from PRIMARY selection
TEXT=$(xclip -o -selection primary 2>/dev/null)

# If primary is empty, try clipboard as fallback
if [ -z "$TEXT" ]; then
    log_msg "Primary selection empty, trying clipboard"
    TEXT=$(xclip -o -selection clipboard 2>/dev/null)
fi

log_msg "Text captured (${#TEXT} chars): $TEXT"

if [ -z "$TEXT" ]; then
    zenity --info --text="No text selected! Please select text first." --timeout=3 --width=300 2>/dev/null
    log_msg "ERROR: No text captured"
    exit 1
fi

# Use espeak-ng for TTS
log_msg "Speaking text with espeak-ng..."
espeak-ng "$TEXT" 2>> "$LOG_FILE"

EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    zenity --error --text="TTS failed! Check logs." --timeout=3 --width=300 2>/dev/null
    log_msg "ERROR: TTS failed"
    exit 1
fi

log_msg "Success!"

EOFTTS

chmod +x "$TTS_SCRIPT_PATH"
echo "✅ TTS script created at: $TTS_SCRIPT_PATH"
echo "📝 Logs: $LOG_DIR/translate.log and $LOG_DIR/tts.log"

# Detect desktop environment
echo ""
echo "🖥️  Detecting desktop environment..."

DE=""
if [ "$XDG_CURRENT_DESKTOP" ]; then
    DE="$XDG_CURRENT_DESKTOP"
elif [ "$DESKTOP_SESSION" ]; then
    DE="$DESKTOP_SESSION"
fi

echo "📋 Desktop: $DE"

# Configure keyboard shortcuts
case "${DE,,}" in
    *gnome*|*ubuntu*)
        echo "🔧 Configuring for GNOME..."

        TRANSLATE_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/translate/"
        TTS_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/tts/"

        KEY_SCHEMA="org.gnome.settings-daemon.plugins.media-keys"
        KEY_NAME="custom-keybindings"

        # get current value (may start with @as)
        CURRENT_RAW=$(gsettings get "$KEY_SCHEMA" "$KEY_NAME" 2>/dev/null || echo "[]")

        # extract quoted paths like '/org/...' into a bash array
        mapfile -t EXISTING < <(printf '%s\n' "$CURRENT_RAW" | grep -o "'[^']*'" | sed "s/'//g")

        # helper: add a path if not present
        add_if_missing() {
            local path="$1"
            for p in "${EXISTING[@]}"; do
                if [ "$p" = "$path" ]; then
                    return 0
                fi
            done
            EXISTING+=("$path")
        }

        add_if_missing "$TRANSLATE_PATH"
        add_if_missing "$TTS_PATH"

        # build GVariant array string "['p1', 'p2']"
        if [ "${#EXISTING[@]}" -eq 0 ]; then
            NEW_ARRAY="[]"
        else
            NEW_ARRAY="["
            for p in "${EXISTING[@]}"; do
                NEW_ARRAY+="'$p', "
            done
            # remove trailing comma and space, close bracket
            NEW_ARRAY=${NEW_ARRAY%, }"]"
        fi

        # set the new array
        gsettings set "$KEY_SCHEMA" "$KEY_NAME" "$NEW_ARRAY"

        # set or update each custom keybinding entry
        gsettings set "${KEY_SCHEMA}.custom-keybinding:${TRANSLATE_PATH}" name 'Google Translate'
        gsettings set "${KEY_SCHEMA}.custom-keybinding:${TRANSLATE_PATH}" command "$SCRIPT_PATH"
        gsettings set "${KEY_SCHEMA}.custom-keybinding:${TRANSLATE_PATH}" binding '<Primary>q'

        gsettings set "${KEY_SCHEMA}.custom-keybinding:${TTS_PATH}" name 'Text to Speech'
        gsettings set "${KEY_SCHEMA}.custom-keybinding:${TTS_PATH}" command "$TTS_SCRIPT_PATH"
        gsettings set "${KEY_SCHEMA}.custom-keybinding:${TTS_PATH}" binding '<Primary><Alt>q'

        echo "✅ GNOME shortcuts configured"
        echo "   Ctrl+Q = Translation"
        echo "   Ctrl+Alt+Q = TTS"
        ;;

    
    *kde*|*plasma*)
        echo "🔧 Configuring for KDE Plasma..."
        
        mkdir -p "$HOME/.local/share/kservices5"
        
        # Translation shortcut
        cat > "$HOME/.local/share/kservices5/google-translate.desktop" << EOFDESKTOP
[Desktop Entry]
Type=Application
Name=Google Translate
Exec=$SCRIPT_PATH
Icon=preferences-desktop-locale
EOFDESKTOP
        kwriteconfig5 --file kglobalshortcutsrc --group "google-translate.desktop" --key "_launch" "Ctrl+Q,none,Google Translate"
        
        # TTS shortcut
        cat > "$HOME/.local/share/kservices5/google-translate-tts.desktop" << EOFDESKTOP2
[Desktop Entry]
Type=Application
Name=Text to Speech
Exec=$TTS_SCRIPT_PATH
Icon=audio-speakers
EOFDESKTOP2
        kwriteconfig5 --file kglobalshortcutsrc --group "google-translate-tts.desktop" --key "_launch" "Ctrl+Alt+Q,none,Text to Speech"
        
        echo "✅ KDE shortcuts configured"
        echo "   Ctrl+Q = Translation"
        echo "   Ctrl+Alt+Q = TTS"
        ;;
    
    *xfce*)
        echo "🔧 Configuring for XFCE..."
        
        # Translation shortcut
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Primary>q" -n -t string -s "$SCRIPT_PATH" 2>/dev/null || \
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Primary>q" -s "$SCRIPT_PATH"
        
        # TTS shortcut
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Primary><Alt>q" -n -t string -s "$TTS_SCRIPT_PATH" 2>/dev/null || \
        xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/<Primary><Alt>q" -s "$TTS_SCRIPT_PATH"
        
        echo "✅ XFCE shortcuts configured"
        echo "   Ctrl+Q = Translation"
        echo "   Ctrl+Alt+Q = TTS"
        ;;
    
    *)
        echo "⚠️  Manual setup needed"
        echo "   Translation: $SCRIPT_PATH (Ctrl+Q)"
        echo "   TTS: $TTS_SCRIPT_PATH (Ctrl+Alt+Q)"
        ;;
esac

echo ""
echo "🎉 Setup complete!"
echo ""
echo "🧪 Usage:"
echo "   Ctrl+Q: Translate selected text"
echo "   Ctrl+Alt+Q: Read selected text aloud (TTS)"
echo ""
echo "📋 Manual test:"
echo "   Translation: $SCRIPT_PATH"
echo "   TTS: $TTS_SCRIPT_PATH"
echo ""
echo "📝 Check logs:"
echo "   tail -f $LOG_DIR/translate.log"
echo "   tail -f $LOG_DIR/tts.log"
