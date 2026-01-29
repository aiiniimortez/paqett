#!/usr/bin/env bash
set -e

echo "=== Paqet Client YAML Generator ==="
echo

read -p "Enter your OUTSIDE server IP address: " SERVER_IP
echo

if [ ! -f "./paqet_linux_amd64" ]; then
  echo "ERROR: paqet_linux_amd64 not found in this directory!"
  exit 1
fi

apt update -y >/dev/null
apt install -y net-tools >/dev/null

echo "[+] Detecting network details..."

IFACE=$(ip r | awk '/default/ {print $5}')
LOCAL_IP=$(ip -4 addr show "$IFACE" | awk '/inet / {print $2}' | cut -d/ -f1)
GATEWAY_IP=$(ip r | awk '/default/ {print $3}')

ping -c 1 -W 1 "$GATEWAY_IP" >/dev/null 2>&1 || true
GATEWAY_MAC=$(arp -n "$GATEWAY_IP" | awk '/ether/ {print $3}')

echo "    Interface: $IFACE"
echo "    Local IP: $LOCAL_IP"
echo "    Gateway MAC: $GATEWAY_MAC"

echo
echo "[+] Generating secret key using paqet..."
SECRET_KEY="$(./paqet_linux_amd64 secret | xargs)"
echo "    Secret generated."

echo
echo "[+] Writing client.yaml ..."

cat <<EOF > client.yaml
# Role must be explicitly set
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
  addr: "$SERVER_IP:9999"

transport:
  protocol: "kcp"
  kcp:
    block: "aes"
    key: "$SECRET_KEY"
EOF

echo
echo "========================================"
echo "[✓] client.yaml created successfully!"
echo
echo ">>> YOUR SECRET KEY (USE THIS ON SERVER):"
echo "$SECRET_KEY"
echo "========================================"
