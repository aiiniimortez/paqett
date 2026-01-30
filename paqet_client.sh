#!/usr/bin/env bash
set -e

VERSION="v1.0.0-alpha.8"
INSTALL_DIR="/opt/paqet"
PORT=9999
MODE="$1"

echo "[+] Detecting OS and Architecture..."

OS=$(uname -s)
ARCH=$(uname -m)

case "$OS-$ARCH" in
  Linux-x86_64)
    FILE="paqet-linux-amd64-$VERSION.tar.gz"
    BIN_NAME="paqet_linux_amd64"
    ;;
  Linux-aarch64)
    FILE="paqet-linux-arm64-$VERSION.tar.gz"
    BIN_NAME="paqet_linux_arm64"
    ;;
  Darwin-arm64)
    FILE="paqet-darwin-arm64-$VERSION.tar.gz"
    BIN_NAME="paqet_darwin_arm64"
    ;;
  *)
    echo "❌ Unsupported OS/Architecture"
    exit 1
    ;;
esac

echo "[+] Required file: $FILE"
echo

mkdir -p "$INSTALL_DIR"

if [ "$MODE" = "offline" ]; then
    echo "[+] Offline mode detected"

    if [ ! -f "$FILE" ]; then
        echo "❌ Required file not found: $FILE"
        echo "Place this file in the current directory and run again."
        exit 1
    fi

    cp "$FILE" "$INSTALL_DIR/paqet.tar.gz"
else
    echo "[+] Downloading $FILE from GitHub..."
    URL="https://github.com/hanselime/paqet/releases/download/$VERSION/$FILE"
    curl -L -o "$INSTALL_DIR/paqet.tar.gz" "$URL"
fi

cd "$INSTALL_DIR"


echo "[+] Extracting..."
tar -xzf paqet.tar.gz
chmod +x "$BIN_NAME"

clear
echo "=== Paqet Client Setup (Iran Server) ==="
echo

read -p "Enter your OUTSIDE server IP address: " SERVER_IP

echo
echo "[+] Detecting network details..."

apt update -y >/dev/null 2>&1 || true
apt install -y net-tools >/dev/null 2>&1 || true

IFACE=$(ip r | awk '/default/ {print $5}')
LOCAL_IP=$(ip -4 addr show "$IFACE" | awk '/inet / {print $2}' | cut -d/ -f1)
GATEWAY_IP=$(ip r | awk '/default/ {print $3}')
ping -c 1 -W 1 "$GATEWAY_IP" >/dev/null 2>&1 || true
GATEWAY_MAC=$(arp -n "$GATEWAY_IP" | awk '/ether/ {print $3}')

echo "[+] Checking paqet binary compatibility..."

if ! $INSTALL_DIR/$BIN_NAME --help >/dev/null 2>&1; then
    echo
    echo "❌ This paqet binary is NOT compatible with your system (glibc too old)."
    echo "You need a statically built version of paqet or a newer OS."
    exit 1
fi

echo "[+] Generating secret using paqet..."
SECRET_KEY="$($INSTALL_DIR/$BIN_NAME secret | tr -d '\n')"

echo "[+] Writing client.yaml ..."

cat <<EOF > $INSTALL_DIR/client.yaml
role: "client"

log:
  level: "info"

socks5:
  - listen: "127.0.0.1:1080"

network:
  interface: "$IFACE"
  ipv4:
    addr: "$LOCAL_IP:0"
    router_mac: "$GATEWAY_MAC"

server:
  addr: "$SERVER_IP:$PORT"

transport:
  protocol: "kcp"
  kcp:
    block: "aes"
    key: "$SECRET_KEY"
EOF

echo "[+] Creating systemd service..."

cat <<EOF > /etc/systemd/system/paqet.service
[Unit]
Description=Paqet Client
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$BIN_NAME run -c client.yaml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable paqet
systemctl restart paqet

echo
echo "========================================"
echo "[✓] Paqet client installed and running!"
echo
echo ">>> YOUR SECRET KEY (give this to outside server):"
echo "$SECRET_KEY"
echo "========================================"
