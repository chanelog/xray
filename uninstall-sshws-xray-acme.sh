#!/bin/bash
#====================================================
# Script Uninstall: SSH WebSocket + Xray (acme.sh version)
#====================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}[WARNING]${NC} Script ini akan menghapus SEMUA konfigurasi!"
read -p "Lanjutkan? (y/n): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Dibatalkan."
    exit 0
fi

echo -e "${YELLOW}[PROSES]${NC} Menghapus services..."

# Stop services
systemctl stop xray sshws nginx dropbear stunnel4 badvpn haproxy 2>/dev/null || true
systemctl disable xray sshws nginx dropbear stunnel4 badvpn haproxy 2>/dev/null || true

# Hapus systemd services
rm -f /etc/systemd/system/sshws.service
rm -f /etc/systemd/system/badvpn.service
systemctl daemon-reload

# Hapus Xray
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove 2>/dev/null || true
rm -rf /usr/local/bin/xray /usr/local/etc/xray /usr/local/share/xray

# Hapus Nginx config
rm -f /etc/nginx/sites-enabled/sshws
rm -f /etc/nginx/sites-available/sshws

# Hapus Stunnel config
rm -f /etc/stunnel/stunnel.conf

# Hapus HAProxy config
rm -f /etc/haproxy/haproxy.cfg

# Hapus scripts
rm -f /usr/local/bin/sshws-server.py
rm -f /usr/local/bin/sshws-menu
rm -f /usr/local/bin/add-user
rm -f /usr/local/bin/del-user
rm -f /usr/local/bin/list-user
rm -f /usr/local/bin/restart-xray
rm -f /usr/local/bin/restart-sshws
rm -f /usr/local/bin/restart-all

# Hapus acme.sh (jika ada)
if [[ -f /root/.acme.sh/acme.sh ]]; then
    /root/.acme.sh/acme.sh --uninstall 2>/dev/null || true
    rm -rf /root/.acme.sh
fi

# Restore Dropbear default
cat > /etc/default/dropbear << 'EOF'
NO_START=1
DROPBEAR_PORT=22
DROPBEAR_EXTRA_ARGS=""
DROPBEAR_BANNER=""
DROPBEAR_RECEIVE_WINDOW=65536
EOF

systemctl restart dropbear 2>/dev/null || true
systemctl restart nginx 2>/dev/null || true

echo -e "${GREEN}[OK]${NC} Uninstall selesai!"
echo -e "${YELLOW}[INFO]${NC} SSL certificate di /etc/letsencrypt/ TIDAK dihapus."
