#!/usr/bin/env bash
set -e

PORT=9999

echo "=== Paqet Server YAML Generator ==="
echo

read -p "Enter the SECRET KEY from client: " SECRET_KEY
echo

apt update -y >/dev/null
apt install -y net-tools iptables-persistent >/dev/null

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
echo "[+] Writing server.yaml ..."

cat <<EOF > server.yaml
# Role must be explicitly set
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

echo
echo "[+] Applying critical iptables rules for pcap..."

iptables -t raw -A PREROUTING -p tcp --dport $PORT -j NOTRACK
iptables -t raw -A OUTPUT -p tcp --sport $PORT -j NOTRACK
iptables -t mangle -A OUTPUT -p tcp --sport $PORT --tcp-flags RST RST -j DROP
iptables -t filter -A INPUT -p tcp --dport $PORT -j ACCEPT
iptables -t filter -A OUTPUT -p tcp --sport $PORT -j ACCEPT

echo "[+] Saving iptables rules (persistent)..."
iptables-save > /etc/iptables/rules.v4

echo
echo "========================================"
echo "[✓] server.yaml created!"
echo "[✓] Firewall configured correctly for Paqet"
echo "========================================"
