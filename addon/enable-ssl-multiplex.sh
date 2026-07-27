#!/bin/bash
# ============================================================
#  ADDON: Multiplex Port 443 (Xray/WS + Raw SSH-SSL)
#  ------------------------------------------------------------
#  Membuat port 443 bisa dipakai BARENG oleh:
#   - Xray (VMess/VLess/Trojan/SS) + SSH-WS TLS (/ssh-ws, /ssh-ws-ssh)
#     -> tetap ditangani Nginx seperti biasa
#   - SSH-SSL murni (SNI-only, TANPA payload HTTP)
#     -> diteruskan langsung ke Stunnel4 -> Dropbear (raw)
#
#  Caranya: Nginx `stream` module mengintip SNI (ClientHello) SEBELUM
#  TLS didekripsi (ssl_preread), lalu meneruskan koneksi APA ADANYA
#  (masih terenkripsi) ke salah satu dari dua tujuan:
#   - SNI == domain asli   -> Nginx (internal, 127.0.0.1:8443)
#   - SNI lainnya (termasuk kosong / SNI fronting acak) -> Stunnel4
#     (127.0.0.1:$STUNNEL_SSL_PORT), yang lalu decrypt & forward ke Dropbear
#
#  PERINGATAN PENTING:
#  Kalau ada user yang connect ke /ssh-ws atau /ssh-ws-ssh (mode payload)
#  dengan SNI yang BEDA dari domain asli (SNI fronting/acak), koneksi
#  itu akan ikut kesasar ke jalur SSH-SSL (Stunnel4) dan GAGAL, karena
#  Nginx gak akan pernah lihat koneksinya. Pastikan user pakai SNI =
#  domain asli untuk mode payload WS.
#
#  Safety: full backup + nginx -t + rollback otomatis kalau gagal.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/lib.sh"

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[ERROR]${NC} Harus dijalankan sebagai root"
  exit 1
fi

DOMAIN=$(get_domain)
if [[ -z "$DOMAIN" ]]; then
  echo -e "${RED}[ERROR]${NC} Domain belum ter-set. Jalankan 'Change Domain' dulu."
  exit 1
fi

ACTION="${1:-enable}"

echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   MULTIPLEX PORT 443: XRAY/WS + SSH-SSL   ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

# ------------------------------------------------------------
# DISABLE: kembalikan ke kondisi normal (443 murni Nginx)
# ------------------------------------------------------------
if [[ "$ACTION" == "disable" ]]; then
  echo -e "${CYAN}[*]${NC} Menonaktifkan multiplex, mengembalikan port 443 ke Nginx langsung..."
  rm -f /etc/nginx/stream.d/ssh-ssl-multiplex.conf
  if regenerate_nginx_conf "$DOMAIN"; then
    echo -e "${GREEN}[OK]${NC} Multiplex dimatikan. Port 443 kembali murni Nginx (Xray/WS)."
  else
    echo -e "${RED}[GAGAL]${NC} Regenerate config gagal, cek manual: nginx -t"
    exit 1
  fi
  exit 0
fi

# ------------------------------------------------------------
# ENABLE
# ------------------------------------------------------------

# --- 1. Pastikan modul stream Nginx terpasang ---
echo -e "${CYAN}[*]${NC} Menginstall libnginx-mod-stream..."
apt-get install -y -qq libnginx-mod-stream 2>/dev/null
if ! find /usr/lib/nginx/modules -iname "*stream*" 2>/dev/null | grep -q stream; then
  echo -e "${RED}[GAGAL]${NC} Modul ngx_stream_module tidak ditemukan setelah install. Batal."
  echo -e "${YELLOW}[INFO]${NC} Cek manual: apt-get install libnginx-mod-stream"
  exit 1
fi
echo -e "${GREEN}[OK]${NC} Modul stream Nginx tersedia"

# --- 2. Pastikan Stunnel4 (SSH-SSL -> Dropbear) sudah aktif dulu ---
if ! systemctl is-active --quiet stunnel4; then
  echo -e "${RED}[GAGAL]${NC} Stunnel4 belum aktif. Jalankan addon SSH-WS dulu (install-sshws.sh)."
  exit 1
fi

# --- 3. Backup ---
BACKUP_DIR="/etc/vpn-script/.backup-multiplex-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp /etc/nginx/nginx.conf "$BACKUP_DIR/nginx.conf" 2>/dev/null
cp /etc/nginx/conf.d/xray.conf "$BACKUP_DIR/xray.conf" 2>/dev/null
echo -e "${GREEN}[OK]${NC} Backup dibuat di $BACKUP_DIR"

rollback() {
  echo -e "${RED}[GAGAL]${NC} $1"
  echo -e "${YELLOW}[*]${NC} Rollback ke config sebelumnya..."
  rm -f /etc/nginx/stream.d/ssh-ssl-multiplex.conf
  [[ -f "$BACKUP_DIR/xray.conf" ]] && cp "$BACKUP_DIR/xray.conf" /etc/nginx/conf.d/xray.conf
  [[ -f "$BACKUP_DIR/nginx.conf" ]] && cp "$BACKUP_DIR/nginx.conf" /etc/nginx/nginx.conf
  systemctl reload nginx 2>/dev/null
  echo -e "${YELLOW}[INFO]${NC} Sudah dikembalikan ke config semula (port 443 tetap Nginx normal)."
  exit 1
}

# --- 4. Buat config stream (map SNI -> backend) ---
echo -e "${CYAN}[*]${NC} Membuat konfigurasi stream (SNI routing)..."
mkdir -p /etc/nginx/stream.d

cat > /etc/nginx/stream.d/ssh-ssl-multiplex.conf <<EOF2
# Multiplex port 443:
#   SNI kosong (banyak client Xray/VMess gak selalu set SNI eksplisit)
#     -> Nginx internal (dianggap Xray/WS, paling aman/kompatibel)
#   SNI == domain asli -> Nginx internal (Xray/WS, termasuk /ssh-ws & /ssh-ws-ssh)
#   SNI lainnya (fronting acak) -> Stunnel4 -> Dropbear (raw SSH-SSL)
map \$ssl_preread_server_name \$ssh_multiplex_backend {
    ""             127.0.0.1:8443;
    default        127.0.0.1:$STUNNEL_SSL_PORT;
    $DOMAIN        127.0.0.1:8443;
}

server {
    listen 443;
    listen [::]:443;
    proxy_pass \$ssh_multiplex_backend;
    ssl_preread on;
    proxy_timeout 300s;
    proxy_connect_timeout 10s;
}
EOF2

# --- 5. Pastikan stream{} block ada di nginx.conf (top-level) ---
if ! grep -q "^stream {" /etc/nginx/nginx.conf; then
  echo -e "${CYAN}[*]${NC} Menambahkan block stream{} ke nginx.conf..."
  cat >> /etc/nginx/nginx.conf <<'EOF3'

stream {
    include /etc/nginx/stream.d/*.conf;
}
EOF3
fi

# --- 6. Regenerate xray.conf (otomatis pakai internal 127.0.0.1:8443 karena stream.d/ssh-ssl-multiplex.conf sudah ada) ---
echo -e "${CYAN}[*]${NC} Meregenerasi Nginx (https block -> internal 127.0.0.1:8443)..."
if ! regenerate_nginx_conf "$DOMAIN"; then
  rollback "nginx -t gagal setelah regenerate config"
fi

sleep 1
if ! systemctl is-active --quiet nginx; then
  rollback "Nginx tidak aktif setelah reload"
fi
echo -e "${GREEN}[OK]${NC} Nginx aktif dengan config multiplex"

# --- 7. Verifikasi fungsional (bukan cuma nginx -t) ---
echo -e "${CYAN}[*]${NC} Verifikasi routing SNI..."

ok_domain=false
ok_fallback=false
ok_empty=false

# SNI = domain asli -> harus nyambung ke Nginx (kirim GET, harus dibalas HTTP)
resp_domain=$(timeout 5 bash -c "printf 'GET / HTTP/1.1\r\nHost: $DOMAIN\r\nConnection: close\r\n\r\n' | openssl s_client -connect 127.0.0.1:443 -servername '$DOMAIN' -quiet 2>/dev/null")
if echo "$resp_domain" | grep -q "^HTTP/"; then
  ok_domain=true
fi

# SNI acak/fronting -> harus nyambung ke Stunnel4->Dropbear (backend SSH kirim banner duluan tanpa diminta)
resp_fallback=$(timeout 5 bash -c "echo | openssl s_client -connect 127.0.0.1:443 -servername 'cek-fallback-multiplex.test' -quiet 2>/dev/null")
if echo "$resp_fallback" | grep -q "^SSH-"; then
  ok_fallback=true
fi

# TANPA SNI sama sekali (banyak client Xray/VMess gak selalu set SNI) -> harus tetap ke Nginx
resp_empty=$(timeout 5 bash -c "printf 'GET / HTTP/1.1\r\nHost: $DOMAIN\r\nConnection: close\r\n\r\n' | openssl s_client -connect 127.0.0.1:443 -noservername -quiet 2>/dev/null")
if echo "$resp_empty" | grep -q "^HTTP/"; then
  ok_empty=true
fi

if [[ "$ok_domain" == "true" && "$ok_fallback" == "true" && "$ok_empty" == "true" ]]; then
  echo -e "${GREEN}[OK]${NC} Ketiga jalur (SNI domain -> Nginx, tanpa SNI -> Nginx, SNI lain -> Stunnel4) terverifikasi jalan"
else
  rollback "Verifikasi gagal (SNI domain -> Nginx: $ok_domain, tanpa SNI -> Nginx: $ok_empty, SNI lain -> Stunnel4: $ok_fallback)"
fi

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   MULTIPLEX PORT 443 AKTIF   ${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "  ${YELLOW}Xray + SSH-WS (payload)${NC} : $DOMAIN:443 (SNI = $DOMAIN persis, ATAU tanpa SNI sama sekali)"
echo -e "  ${YELLOW}SSH-SSL (tanpa payload)${NC} : $DOMAIN:443 (SNI diisi apapun SELAIN $DOMAIN, langsung -> Dropbear)"
echo -e "${YELLOW}[PENTING]${NC} User yang connect /ssh-ws atau /ssh-ws-ssh dengan SNI"
echo -e "  fronting/acak (bukan $DOMAIN persis) akan GAGAL setelah ini —"
echo -e "  koneksinya sekarang dianggap SSH-SSL dan dilempar ke Stunnel4."
echo -e "  Kalau mau matikan fitur ini: bash $0 disable"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
