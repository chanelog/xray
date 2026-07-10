#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - ADDON INSTALLER: HAProxy (SNI Router)
#   Tujuan: SSH-SSL numpang di port 443 bareng Xray, dibedain via SNI.
#     - SNI cocok domain kamu   -> diteruskan ke Nginx (Xray: VMess/VLess/Trojan/SS)
#     - SNI lain / kosong       -> diteruskan ke Stunnel4 (SSH-SSL)
#   Setelah addon ini jalan: Nginx digeser dari 443 (publik) ke
#   127.0.0.1:$NGINX_TLS_INTERNAL_PORT (loopback). HAProxy yang pegang port 443.
#   Port 445 (SSH-SSL langsung) TETAP jalan seperti biasa, gak kepengaruh.
#
#   AMAN: nginx.conf di-backup dulu, "nginx -t" & "haproxy -c" divalidasi
#   SEBELUM apa pun direstart. Kalau validasi gagal, rollback otomatis.
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[ERROR]${NC} Jalankan sebagai root!"
  exit 1
fi

DOMAIN=$(get_domain)
if [[ -z "$DOMAIN" ]]; then
  echo -e "${RED}[ERROR]${NC} Domain belum di-set. Set domain lewat menu utama dulu."
  exit 1
fi

NGINX_XRAY_CONF="/etc/nginx/conf.d/xray.conf"
if [[ ! -f "$NGINX_XRAY_CONF" ]]; then
  echo -e "${RED}[ERROR]${NC} $NGINX_XRAY_CONF tidak ditemukan. Install Xray/Nginx dulu (install.sh utama)."
  exit 1
fi

if ! systemctl is-active --quiet stunnel4; then
  echo -e "${YELLOW}[CATATAN]${NC} stunnel4 belum aktif (SSH-SSL belum terpasang). HAProxy tetap"
  echo -e "${YELLOW}[CATATAN]${NC} akan dipasang, tapi jalur SSH-SSL-nya baru berfungsi setelah kamu"
  echo -e "${YELLOW}[CATATAN]${NC} install addon SSH-WS/SSL (addon/install-sshws.sh)."
fi

echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   INSTALL ADDON: HAProxy (SNI Router, port 443)   ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

# ─── 1. Install HAProxy ─────────────────────────────────────
echo -e "\n${CYAN}[*]${NC} Menginstall HAProxy..."
apt-get update -qq 2>/dev/null
apt-get install -y -qq haproxy 2>/dev/null
echo -e "${GREEN}[OK]${NC} HAProxy terinstall"

# ─── 2. Geser Nginx dari port 443 publik ke loopback ────────
echo -e "\n${CYAN}[*]${NC} Menggeser Nginx: 443 (publik) -> 127.0.0.1:$NGINX_TLS_INTERNAL_PORT (loopback)..."
NGINX_BACKUP="${NGINX_XRAY_CONF}.bak.$(date +%s)"
cp "$NGINX_XRAY_CONF" "$NGINX_BACKUP"

if grep -q "listen 127.0.0.1:$NGINX_TLS_INTERNAL_PORT ssl http2;" "$NGINX_XRAY_CONF"; then
  echo -e "${YELLOW}[SKIP]${NC} Nginx sudah digeser sebelumnya, lewati langkah ini."
else
  sed -i \
    -e "s/listen 443 ssl http2;/listen 127.0.0.1:${NGINX_TLS_INTERNAL_PORT} ssl http2;/" \
    -e "/listen \[::\]:443 ssl http2;/d" \
    "$NGINX_XRAY_CONF"

  if ! grep -q "listen 127.0.0.1:$NGINX_TLS_INTERNAL_PORT ssl http2;" "$NGINX_XRAY_CONF"; then
    echo -e "${RED}[ERROR]${NC} Gagal menemukan baris 'listen 443 ssl http2;' di $NGINX_XRAY_CONF"
    echo -e "${RED}[ERROR]${NC} (mungkin sudah dimodifikasi manual). Mengembalikan config asal, install dibatalkan."
    cp "$NGINX_BACKUP" "$NGINX_XRAY_CONF"
    exit 1
  fi
fi

if nginx -t 2>/dev/null; then
  systemctl reload nginx 2>/dev/null || systemctl restart nginx
  echo -e "${GREEN}[OK]${NC} Nginx sekarang cuma dengar di 127.0.0.1:$NGINX_TLS_INTERNAL_PORT (gak lagi publik)"
else
  echo -e "${RED}[ERROR]${NC} 'nginx -t' gagal setelah digeser, mengembalikan config asal..."
  cp "$NGINX_BACKUP" "$NGINX_XRAY_CONF"
  systemctl reload nginx 2>/dev/null
  echo -e "${RED}[ERROR]${NC} Install HAProxy dibatalkan. Nginx tetap seperti semula (443 publik)."
  exit 1
fi

# ─── 3. Pasang haproxy.cfg dari template ────────────────────
echo -e "\n${CYAN}[*]${NC} Mengambil & merender haproxy.cfg (domain: $DOMAIN)..."
HAPROXY_TMP=$(mktemp)
if ! wget -q --timeout=30 "$UPDATE_RAW/addon/files/haproxy.cfg.tpl" -O "$HAPROXY_TMP" || [[ ! -s "$HAPROXY_TMP" ]]; then
  echo -e "${RED}[ERROR]${NC} Gagal download haproxy.cfg.tpl dari repo."
  echo -e "${YELLOW}[WARN]${NC} Mengembalikan Nginx ke 443 publik supaya server tetap bisa diakses..."
  cp "$NGINX_BACKUP" "$NGINX_XRAY_CONF"
  systemctl reload nginx 2>/dev/null
  rm -f "$HAPROXY_TMP"
  exit 1
fi

[[ -f /etc/haproxy/haproxy.cfg ]] && cp /etc/haproxy/haproxy.cfg "/etc/haproxy/haproxy.cfg.bak.$(date +%s)"

sed -e "s#__DOMAIN__#$DOMAIN#g" \
    -e "s#__NGINX_TLS_INTERNAL_PORT__#$NGINX_TLS_INTERNAL_PORT#g" \
    -e "s#__STUNNEL_SSL_PORT__#$STUNNEL_SSL_PORT#g" \
    "$HAPROXY_TMP" > /etc/haproxy/haproxy.cfg
rm -f "$HAPROXY_TMP"

# ─── 4. Validasi & start HAProxy ────────────────────────────
if haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1; then
  systemctl enable haproxy 2>/dev/null
  systemctl restart haproxy
  echo -e "${GREEN}[OK]${NC} HAProxy aktif & valid."
else
  echo -e "${RED}[ERROR]${NC} haproxy.cfg tidak valid (haproxy -c gagal)."
  echo -e "${YELLOW}[WARN]${NC} Mengembalikan Nginx ke 443 publik supaya server tetap bisa diakses..."
  cp "$NGINX_BACKUP" "$NGINX_XRAY_CONF"
  systemctl reload nginx 2>/dev/null
  echo -e "${RED}[ERROR]${NC} Cek manual: haproxy -c -f /etc/haproxy/haproxy.cfg"
  exit 1
fi

sleep 1
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
if systemctl is-active --quiet haproxy && systemctl is-active --quiet nginx; then
  echo -e "${WHITE}   ✓  HAProxy AKTIF — port 443 sekarang di-SNI-route   ${NC}"
else
  echo -e "${RED}   ✗  Ada service yang belum aktif, cek manual${NC}"
fi
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "  SNI = $DOMAIN        -> Nginx/Xray  (127.0.0.1:$NGINX_TLS_INTERNAL_PORT)"
echo -e "  SNI lain / kosong    -> Stunnel4 SSH-SSL (127.0.0.1:$STUNNEL_SSL_PORT)"
echo -e "  Akses langsung SSH-SSL di port $STUNNEL_SSL_PORT TETAP jalan seperti biasa."
echo -e "  Sekarang SSH-SSL JUGA bisa lewat port 443 (client set SNI apa aja SELAIN $DOMAIN)."
echo -e "  Logs   : journalctl -u haproxy -n 50 --no-pager"
echo -e "  Status : systemctl status haproxy"
