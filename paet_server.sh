#!/usr/bin/env bash
set -e

VERSION="v1.0.0-alpha.15"
BASE_URL="https://github.com/hanselime/paqet/releases/download/$VERSION"
INSTALL_DIR="/opt/paqet"
PORT=9999

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
  Darwin-x86_64)
    FILE="paqet-darwin-amd64-$VERSION.tar.gz"
    BIN_NAME="paqet_darwin_amd64"
    ;;
  *)
    echo "❌ This OS/Architecture is not supported by this installer."
    exit 1
    ;;
esac

URL="$BASE_URL/$FILE"

echo "[+] Downloading $FILE ..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

curl -L -o paqet.tar.gz "$URL"
tar -xzf paqet.tar.gz
chmod +x "$BIN_NAME"

clear
echo "=== Paqet Server Setup ==="
echo

read -p "Enter the SECRET KEY from client: " SECRET_KEY

echo
echo "[+] Detecting network details..."

apt update -y >/dev/null 2>&1 || true
apt install -y net-tools >/dev/null 2>&1 || true

IFACE=$(ip r | awk '/default/ {print $5}')
LOCAL_IP=$(ip -4 addr show "$IFACE" | awk '/inet / {print $2}' | cut -d/ -f1)
GATEWAY_IP=$(ip r | awk '/default/ {print $3}')
ping -c 1 -W 1 "$GATEWAY_IP" >/dev/null 2>&1 || true
GATEWAY_MAC=$(arp -n "$GATEWAY_IP" | awk '/ether/ {print $3}')

echo "[+] Writing server.yaml ..."

cat <<EOF > $INSTALL_DIR/server.yaml
role: "server"

log:
  level: "info"

listen:
  addr: ":$PORT"

network:
  interface: "$IFACE"
  ipv4:
    addr: "$LOCAL_IP:$PORT"
    router_mac: "$GATEWAY_MAC"

transport:
  protocol: "kcp"
  kcp:
    block: "aes"
    key: "$SECRET_KEY"
EOF

echo "[+] Applying critical iptables rules..."

iptables -t raw -A PREROUTING -p tcp --dport $PORT -j NOTRACK
iptables -t raw -A OUTPUT -p tcp --sport $PORT -j NOTRACK
iptables -t mangle -A OUTPUT -p tcp --sport $PORT --tcp-flags RST RST -j DROP
iptables -t filter -A INPUT -p tcp --dport $PORT -j ACCEPT
iptables -t filter -A OUTPUT -p tcp --sport $PORT -j ACCEPT

iptables-save > /etc/iptables/rules.v4 2>/dev/null || true

echo "[+] Creating systemd service..."

cat <<EOF > /etc/systemd/system/paqet.service
[Unit]
Description=Paqet Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$BIN_NAME run -c server.yaml
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
echo "[✓] Paqet server installed and running!"
echo "Service: systemctl status paqet"
echo "Config : $INSTALL_DIR/server.yaml"
echo "========================================"
