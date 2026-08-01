#!/bin/bash
# ============================================================
#  ADDON: Multiplex Port 443 (Xray/WS + Raw SSH-SSL) — via HAProxy
#  ------------------------------------------------------------
#  Versi 2: pakai HAProxy (TCP mode + inspeksi SNI) buat baca SNI
#  dari ClientHello TLS, BUKAN Nginx stream module lagi (versi 1
#  yang berbasis Nginx stream/ssl_preread terbukti gak reliable
#  buat trafik Xray yang sustained/panjang).
#
#  Membuat port 443 bisa dipakai BARENG oleh:
#   - Xray (VMess/VLess/Trojan/SS) + SSH-WS TLS (/ssh-ws, /ssh-ws-ssh)
#     -> tetap ditangani Nginx (internal, 127.0.0.1:8443)
#   - SSH-SSL murni (SNI-only, TANPA payload HTTP)
#     -> diteruskan langsung ke Stunnel4 -> Dropbear (raw)
#
#  Caranya: HAProxy (mode tcp) mengintip SNI dari ClientHello TLS
#  SEBELUM didekripsi (req.ssl_sni), lalu meneruskan koneksi APA
#  ADANYA (masih terenkripsi) ke salah satu dari dua tujuan:
#   - SNI == domain asli ATAU SNI kosong -> Nginx (127.0.0.1:8443)
#   - SNI lainnya (fronting acak)        -> Stunnel4 (127.0.0.1:$STUNNEL_SSL_PORT)
#
#  PERINGATAN PENTING:
#  Kalau ada user yang connect ke /ssh-ws atau /ssh-ws-ssh (mode payload)
#  dengan SNI yang BEDA dari domain asli (SNI fronting/acak), koneksi
#  itu akan ikut kesasar ke jalur SSH-SSL (Stunnel4) dan GAGAL, karena
#  Nginx gak akan pernah lihat koneksinya. Pastikan user pakai SNI =
#  domain asli untuk mode payload WS.
#
#  Safety: full backup + haproxy -c + nginx -t + verifikasi FUNGSIONAL
#  (bukan cuma syntax check) + rollback otomatis kalau gagal.
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

MARKER="/etc/vpn-script/.multiplex-443-active"
HAPROXY_CONF="/etc/haproxy/haproxy.cfg"
MARKER_START="# >>> MULTIPLEX-443-ADDON (jangan edit manual, dikelola addon) >>>"
MARKER_END="# <<< MULTIPLEX-443-ADDON <<<"

ACTION="${1:-enable}"

echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   MULTIPLEX PORT 443 (via HAProxy): XRAY/WS + SSH-SSL   ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

remove_haproxy_block() {
  awk -v start="$MARKER_START" -v end="$MARKER_END" '
    $0==start {skip=1; next}
    skip && $0==end {skip=0; next}
    !skip {print}
  ' "$HAPROXY_CONF" > "$HAPROXY_CONF.tmp" && mv "$HAPROXY_CONF.tmp" "$HAPROXY_CONF"
}

# ------------------------------------------------------------
# DISABLE
# ------------------------------------------------------------
if [[ "$ACTION" == "disable" ]]; then
  echo -e "${CYAN}[*]${NC} Menonaktifkan multiplex, mengembalikan port 443 ke Nginx langsung..."
  rm -f "$MARKER"
  rm -f /etc/nginx/stream.d/ssh-ssl-multiplex.conf
  cp "$HAPROXY_CONF" "$HAPROXY_CONF.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null
  remove_haproxy_block

  if ! haproxy -c -f "$HAPROXY_CONF" > /tmp/haproxy_check.log 2>&1; then
    echo -e "${RED}[GAGAL]${NC} haproxy.cfg invalid setelah dibersihkan, cek manual:"
    cat /tmp/haproxy_check.log
  else
    systemctl reload haproxy 2>/dev/null || systemctl restart haproxy 2>/dev/null
  fi

  if regenerate_nginx_conf "$DOMAIN"; then
    echo -e "${GREEN}[OK]${NC} Multiplex dimatikan. Port 443 kembali murni Nginx (Xray/WS)."
  else
    echo -e "${RED}[GAGAL]${NC} Regenerate config Nginx gagal, cek manual: nginx -t"
    exit 1
  fi
  exit 0
fi

# ------------------------------------------------------------
# ENABLE
# ------------------------------------------------------------

# --- 1. Pastikan HAProxy terpasang ---
if ! command -v haproxy >/dev/null 2>&1; then
  echo -e "${CYAN}[*]${NC} Menginstall HAProxy..."
  apt-get install -y -qq haproxy 2>/dev/null
fi
if ! command -v haproxy >/dev/null 2>&1; then
  echo -e "${RED}[GAGAL]${NC} HAProxy gagal terinstall. Batal."
  exit 1
fi
echo -e "${GREEN}[OK]${NC} HAProxy tersedia"

# --- 2. Pastikan Stunnel4 (SSH-SSL -> Dropbear) sudah aktif dulu ---
if ! systemctl is-active --quiet stunnel4; then
  echo -e "${RED}[GAGAL]${NC} Stunnel4 belum aktif. Jalankan addon SSH-WS dulu (install-sshws.sh)."
  exit 1
fi

# --- 3. Backup ---
BACKUP_DIR="/etc/vpn-script/.backup-multiplex-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp "$HAPROXY_CONF" "$BACKUP_DIR/haproxy.cfg" 2>/dev/null
cp /etc/nginx/conf.d/xray.conf "$BACKUP_DIR/xray.conf" 2>/dev/null
echo -e "${GREEN}[OK]${NC} Backup dibuat di $BACKUP_DIR"

rollback() {
  echo -e "${RED}[GAGAL]${NC} $1"
  echo -e "${YELLOW}[*]${NC} Rollback ke config sebelumnya..."
  rm -f "$MARKER"
  [[ -f "$BACKUP_DIR/haproxy.cfg" ]] && cp "$BACKUP_DIR/haproxy.cfg" "$HAPROXY_CONF"
  [[ -f "$BACKUP_DIR/xray.conf" ]] && cp "$BACKUP_DIR/xray.conf" /etc/nginx/conf.d/xray.conf
  systemctl reload haproxy 2>/dev/null || systemctl restart haproxy 2>/dev/null
  systemctl reload nginx 2>/dev/null
  echo -e "${YELLOW}[INFO]${NC} Sudah dikembalikan ke config semula (port 443 tetap Nginx normal)."
  exit 1
}

# --- 4. Tandai multiplex aktif (dibaca regenerate_nginx_conf) lalu regenerasi Nginx dulu ---
touch "$MARKER"
echo -e "${CYAN}[*]${NC} Meregenerasi Nginx (https block -> internal 127.0.0.1:8443)..."
if ! regenerate_nginx_conf "$DOMAIN"; then
  rollback "nginx -t gagal setelah regenerate config"
fi
sleep 1
if ! systemctl is-active --quiet nginx; then
  rollback "Nginx tidak aktif setelah reload"
fi
echo -e "${GREEN}[OK]${NC} Nginx aktif, https block sekarang internal (127.0.0.1:8443)"

# --- 5. Sisipkan frontend/backend multiplex ke haproxy.cfg (marker-based, idempotent) ---
echo -e "${CYAN}[*]${NC} Menyisipkan config multiplex ke haproxy.cfg..."
remove_haproxy_block

{
  echo ""
  echo "$MARKER_START"
  cat <<HAPROXY_EOF
frontend multiplex_443
  bind *:443
  mode tcp
  tcp-request inspect-delay 5s
  tcp-request content accept if { req.ssl_hello_type 1 }

  acl m443_is_domain req.ssl_sni -i $DOMAIN
  acl m443_has_sni req.ssl_sni -m found

  use_backend multiplex_xray if m443_is_domain
  use_backend multiplex_xray if !m443_has_sni
  default_backend multiplex_sshssl

backend multiplex_xray
  mode tcp
  server nginx-internal 127.0.0.1:8443 check

backend multiplex_sshssl
  mode tcp
  server stunnel-dropbear 127.0.0.1:$STUNNEL_SSL_PORT check
HAPROXY_EOF
  echo "$MARKER_END"
} >> "$HAPROXY_CONF"

# --- 6. Validasi SEBELUM restart ---
if ! haproxy -c -f "$HAPROXY_CONF" > /tmp/haproxy_check.log 2>&1; then
  cat /tmp/haproxy_check.log
  rollback "haproxy.cfg invalid setelah sisip config multiplex"
fi

systemctl reload haproxy 2>/dev/null || systemctl restart haproxy 2>/dev/null
sleep 1
if ! systemctl is-active --quiet haproxy; then
  rollback "HAProxy tidak aktif setelah reload"
fi
echo -e "${GREEN}[OK]${NC} HAProxy aktif dengan config multiplex (port 443)"

# --- 7. Verifikasi fungsional (bukan cuma syntax check) ---
echo -e "${CYAN}[*]${NC} Verifikasi routing SNI..."

ok_domain=false
ok_fallback=false
ok_empty=false

resp_domain=$(timeout 5 bash -c "printf 'GET / HTTP/1.1\r\nHost: $DOMAIN\r\nConnection: close\r\n\r\n' | openssl s_client -connect 127.0.0.1:443 -servername '$DOMAIN' -quiet 2>/dev/null")
[[ "$resp_domain" == *"HTTP/"* ]] && ok_domain=true

resp_empty=$(timeout 5 bash -c "printf 'GET / HTTP/1.1\r\nHost: $DOMAIN\r\nConnection: close\r\n\r\n' | openssl s_client -connect 127.0.0.1:443 -noservername -quiet 2>/dev/null")
[[ "$resp_empty" == *"HTTP/"* ]] && ok_empty=true

resp_fallback=$(timeout 5 bash -c "echo | openssl s_client -connect 127.0.0.1:443 -servername 'cek-fallback-multiplex.test' -quiet 2>/dev/null")
[[ "$resp_fallback" == *"SSH-"* ]] && ok_fallback=true

if [[ "$ok_domain" == "true" && "$ok_fallback" == "true" && "$ok_empty" == "true" ]]; then
  echo -e "${GREEN}[OK]${NC} Ketiga jalur (SNI domain -> Nginx, tanpa SNI -> Nginx, SNI lain -> Stunnel4) terverifikasi jalan"
else
  rollback "Verifikasi gagal (SNI domain -> Nginx: $ok_domain, tanpa SNI -> Nginx: $ok_empty, SNI lain -> Stunnel4: $ok_fallback)"
fi

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   MULTIPLEX PORT 443 AKTIF (via HAProxy)   ${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "  ${YELLOW}Xray + SSH-WS (payload)${NC} : $DOMAIN:443 (SNI = $DOMAIN persis, ATAU tanpa SNI sama sekali)"
echo -e "  ${YELLOW}SSH-SSL (tanpa payload)${NC} : $DOMAIN:443 (SNI diisi apapun SELAIN $DOMAIN, langsung -> Dropbear)"
echo -e "${YELLOW}[PENTING]${NC} User yang connect /ssh-ws atau /ssh-ws-ssh dengan SNI"
echo -e "  fronting/acak (bukan $DOMAIN persis) akan GAGAL setelah ini —"
echo -e "  koneksinya sekarang dianggap SSH-SSL dan dilempar ke Stunnel4."
echo -e "  Kalau mau matikan fitur ini: bash $0 disable"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
