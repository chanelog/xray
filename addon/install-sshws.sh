#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - ADDON INSTALLER (ALL-IN-ONE)
#   Fitur:
#     - SSH-WS  (backend OpenSSH)  -> port publik langsung $WS_OPENSSH_PORT
#     - SSH-WS  (backend Dropbear) -> port publik langsung $WS_DROPBEAR_PORT
#     - SSH-SSL (Stunnel4 -> ws-stunnel) -> port publik $STUNNEL_SSL_PORT
#   Client CONNECT LANGSUNG ke port ws-openssh/ws-dropbear (TIDAK lewat Nginx).
#   Script ini bersifat REPLACER: menghapus instalasi ws-proxy (versi lama,
#   asyncio python3 + nginx location /ssh-ws) sebelum memasang komponen baru.
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

echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   INSTALL ADDON: SSH-WS (OpenSSH/Dropbear) + SSH-SSL   ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

# ─── 0. Bersihkan instalasi WS LAMA (ws-proxy asyncio) ─────
echo -e "\n${CYAN}[*]${NC} Membersihkan instalasi SSH-WS lama (ws-proxy)..."
systemctl stop ws-proxy 2>/dev/null
systemctl disable ws-proxy 2>/dev/null
rm -f /etc/systemd/system/ws-proxy.service
rm -f /usr/local/bin/ws-proxy.py
systemctl daemon-reload 2>/dev/null
echo -e "${GREEN}[OK]${NC} ws-proxy lama sudah dibersihkan (jika ada)"

# ─── 1. Dependensi ─────────────────────────────────────────
echo -e "\n${CYAN}[*]${NC} Menginstall dependensi (stunnel4, python3 untuk helper)..."
apt-get update -qq 2>/dev/null
apt-get install -y -qq stunnel4 python3 2>/dev/null
echo -e "${GREEN}[OK]${NC} Dependensi terinstall"

# ─── 2. Pastikan Python 2 tersedia ─────────────────────────
# ws-openssh / ws-dropbear / ws-stunnel memakai sintaks Python 2
# (statement 'print', 'import thread'). Ubuntu 22.04+/Debian 11+ TIDAK
# lagi menyediakan python2 di repo resmi -> ini kemungkinan besar
# penyebab fitur SSH-WS lama "tidak mau jalan" walau Xray tetap jalan.
PY2_BIN=""
find_python2() {
  if command -v python2 &>/dev/null; then
    PY2_BIN=$(command -v python2)
  elif command -v python2.7 &>/dev/null; then
    PY2_BIN=$(command -v python2.7)
  fi
}

echo -e "\n${CYAN}[*]${NC} Memeriksa ketersediaan Python 2..."
find_python2
if [[ -z "$PY2_BIN" ]]; then
  apt-get install -y -qq python2 2>/dev/null || apt-get install -y -qq python2.7 2>/dev/null
  find_python2
fi

if [[ -z "$PY2_BIN" ]]; then
  echo -e "${RED}[PERINGATAN]${NC} Python 2 TIDAK ditemukan & TIDAK tersedia di repo apt OS ini."
  echo -e "${YELLOW}[INFO]${NC} ws-openssh / ws-dropbear / ws-stunnel BUTUH Python 2 untuk jalan."
  echo -e "${YELLOW}[INFO]${NC} Service systemd akan tetap dipasang tapi KEMUNGKINAN BESAR GAGAL START"
  echo -e "${YELLOW}[INFO]${NC} sampai Python 2 terpasang manual (mis. build dari source, atau ambil"
  echo -e "${YELLOW}[INFO]${NC} paket python2 dari repo Ubuntu versi lama / PPA pihak ketiga)."
  echo -e "${YELLOW}[INFO]${NC} Lanjut memasang file & service, tapi cek 'systemctl status ws-openssh'"
  echo -e "${YELLOW}[INFO]${NC} setelah ini selesai."
  PY2_BIN="/usr/bin/python2"
else
  echo -e "${GREEN}[OK]${NC} Python 2 ditemukan di: $PY2_BIN"
fi

# ─── 3. Download aset ws-openssh / ws-dropbear / ws-stunnel + service ──
# Semua file ini diambil dari repo (addon/files/...), BUKAN di-embed lagi
# di dalam script ini. Supaya gampang di-edit langsung di GitHub tanpa
# bongkar heredoc.
ASSET_BASE="$UPDATE_RAW/addon/files"
FILES_TMP=$(mktemp -d)

fetch_asset() {
  local remote="$1" local_path="$2" desc="$3"
  echo -ne "  ${CYAN}[*]${NC} Download $desc..."
  if wget -q --timeout=30 "$ASSET_BASE/$remote" -O "$local_path" && [[ -s "$local_path" ]]; then
    echo -e " ${GREEN}OK${NC}"
    return 0
  else
    echo -e " ${RED}GAGAL${NC}"
    rm -f "$local_path"
    return 1
  fi
}

echo -e "\n${CYAN}[*]${NC} Mengambil script ws-openssh / ws-dropbear / ws-stunnel dari repo..."
FETCH_OK=true
fetch_asset "ws-openssh"                 "$FILES_TMP/ws-openssh"                 "ws-openssh"                 || FETCH_OK=false
fetch_asset "ws-dropbear"                "$FILES_TMP/ws-dropbear"                "ws-dropbear"                || FETCH_OK=false
fetch_asset "ws-stunnel"                 "$FILES_TMP/ws-stunnel"                 "ws-stunnel"                 || FETCH_OK=false
fetch_asset "ws-openssh.service.tpl"     "$FILES_TMP/ws-openssh.service.tpl"     "ws-openssh.service (template)"  || FETCH_OK=false
fetch_asset "ws-dropbear.service.tpl"    "$FILES_TMP/ws-dropbear.service.tpl"    "ws-dropbear.service (template)" || FETCH_OK=false
fetch_asset "ws-stunnel.service.tpl"     "$FILES_TMP/ws-stunnel.service.tpl"     "ws-stunnel.service (template)"  || FETCH_OK=false

if [[ "$FETCH_OK" != "true" ]]; then
  echo -e "${RED}[ERROR]${NC} Ada file yang gagal didownload dari $ASSET_BASE"
  echo -e "${RED}[ERROR]${NC} Pastikan folder addon/files/ sudah di-push ke repo & repo publik."
  rm -rf "$FILES_TMP"
  exit 1
fi

# ─── 4. Pasang ws-openssh & ws-dropbear (SSH-WS langsung, tanpa Nginx) ──
install -m 755 "$FILES_TMP/ws-openssh" /usr/local/bin/ws-openssh
echo -e "${GREEN}[OK]${NC} ws-openssh dipasang di /usr/local/bin/ws-openssh (port publik $WS_OPENSSH_PORT)"
echo -e "${YELLOW}[CATATAN]${NC} Fallback backend default script ini adalah 127.0.0.1:88 (dipakai"
echo -e "${YELLOW}[CATATAN]${NC} HANYA kalau client tidak mengirim header X-Real-Host). Kalau mau"
echo -e "${YELLOW}[CATATAN]${NC} default-nya OpenSSH (port 22), edit baris DEFAULT_HOST di file itu."

install -m 755 "$FILES_TMP/ws-dropbear" /usr/local/bin/ws-dropbear
echo -e "${GREEN}[OK]${NC} ws-dropbear dipasang di /usr/local/bin/ws-dropbear (port publik $WS_DROPBEAR_PORT, default backend 127.0.0.1:109)"

# ─── 5. Pasang ws-stunnel (backend untuk SSH-SSL, di belakang stunnel4) ──
install -m 755 "$FILES_TMP/ws-stunnel" /usr/local/bin/ws-stunnel
echo -e "${GREEN}[OK]${NC} ws-stunnel dipasang di /usr/local/bin/ws-stunnel (loopback 127.0.0.1:$WS_STUNNEL_LOCAL_PORT)"

# ─── 6. Systemd service units (dari template, isi placeholder sesuai server ini) ──
echo -e "\n${CYAN}[*]${NC} Membuat systemd service ws-openssh / ws-dropbear / ws-stunnel dari template..."

render_service() {
  local tpl="$1" out="$2"
  sed -e "s#__PY2_BIN__#$PY2_BIN#g" \
      -e "s#__WS_OPENSSH_PORT__#$WS_OPENSSH_PORT#g" \
      -e "s#__WS_DROPBEAR_PORT__#$WS_DROPBEAR_PORT#g" \
      -e "s#__WS_STUNNEL_LOCAL_PORT__#$WS_STUNNEL_LOCAL_PORT#g" \
      "$tpl" > "$out"
}

render_service "$FILES_TMP/ws-openssh.service.tpl"  /etc/systemd/system/ws-openssh.service
render_service "$FILES_TMP/ws-dropbear.service.tpl" /etc/systemd/system/ws-dropbear.service
render_service "$FILES_TMP/ws-stunnel.service.tpl"  /etc/systemd/system/ws-stunnel.service

rm -rf "$FILES_TMP"
systemctl daemon-reload
echo -e "${GREEN}[OK]${NC} Service unit dibuat (ExecStart pakai: $PY2_BIN)"

# ─── 7. Konfigurasi Stunnel4 untuk SSH-SSL (depan ws-stunnel) ──
echo -e "\n${CYAN}[*]${NC} Mengkonfigurasi Stunnel4 (SSH-SSL)..."

if [[ -f /etc/ssl/xray/xray.crt && -f /etc/ssl/xray/xray.key ]]; then
  cat /etc/ssl/xray/xray.crt /etc/ssl/xray/xray.key > /etc/stunnel/stunnel.pem 2>/dev/null
else
  echo -e "${YELLOW}[WARN]${NC} Sertifikat Xray tidak ditemukan, membuat self-signed untuk stunnel..."
  openssl req -x509 -newkey rsa:2048 -keyout /tmp/stunnel.key -out /tmp/stunnel.crt \
    -days 365 -nodes -subj "/CN=${DOMAIN:-localhost}" 2>/dev/null
  cat /tmp/stunnel.crt /tmp/stunnel.key > /etc/stunnel/stunnel.pem
  rm -f /tmp/stunnel.key /tmp/stunnel.crt
fi
chmod 600 /etc/stunnel/stunnel.pem

if grep -q "\[ssh-ssl\]" /etc/stunnel/stunnel.conf 2>/dev/null; then
  echo -e "${YELLOW}[UPDATE]${NC} Block [ssh-ssl] sudah ada, memperbarui..."
  awk '
    /^\[ssh-ssl\]/ { skip=1; next }
    /^\[/ && skip { skip=0 }
    !skip { print }
  ' /etc/stunnel/stunnel.conf > /tmp/stunnel.conf.new
  cp /tmp/stunnel.conf.new /etc/stunnel/stunnel.conf
  rm -f /tmp/stunnel.conf.new
fi

cat >> /etc/stunnel/stunnel.conf << EOF2

[ssh-ssl]
accept = $STUNNEL_SSL_PORT
connect = 127.0.0.1:$WS_STUNNEL_LOCAL_PORT
cert = /etc/stunnel/stunnel.pem
EOF2

sed -i 's/^ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null
grep -q "^ENABLED=" /etc/default/stunnel4 2>/dev/null || echo "ENABLED=1" >> /etc/default/stunnel4

echo -e "${GREEN}[OK]${NC} Stunnel4 dikonfigurasi: $STUNNEL_SSL_PORT -> 127.0.0.1:$WS_STUNNEL_LOCAL_PORT (ws-stunnel)"

# ─── 8. Bersihkan location /ssh-ws LAMA di Nginx (kalau ada) ────
# Sekarang SSH-WS connect LANGSUNG ke port ${WS_OPENSSH_PORT}/${WS_DROPBEAR_PORT},
# TIDAK lagi lewat Nginx. Kalau server ini pernah pakai versi addon lama,
# xray.conf masih berisi "location /ssh-ws { proxy_pass http://127.0.0.1:700; }"
# di port 80/443, plus server block khusus 8880/8080/2080/2082 yang isinya
# cuma /ssh-ws. Blok-blok itu kita bersihkan di sini (aman: backup + nginx -t
# dulu sebelum reload, rollback otomatis kalau ada error).
NGINX_XRAY_CONF="/etc/nginx/conf.d/xray.conf"
if [[ -f "$NGINX_XRAY_CONF" ]] && grep -q "ssh-ws" "$NGINX_XRAY_CONF"; then
  echo -e "\n${CYAN}[*]${NC} Membersihkan location /ssh-ws lama di Nginx (${NGINX_XRAY_CONF})..."
  BACKUP="${NGINX_XRAY_CONF}.bak.$(date +%s)"
  cp "$NGINX_XRAY_CONF" "$BACKUP"

  python3 - "$NGINX_XRAY_CONF" << 'PYEOF_NGINXCLEAN'
import re, sys

def remove_blocks(text, start_pattern):
    out, i = [], 0
    pat = re.compile(start_pattern)
    while True:
        m = pat.search(text, i)
        if not m:
            out.append(text[i:]); break
        out.append(text[i:m.start()])
        depth, j = 0, m.end() - 1
        while j < len(text):
            if text[j] == '{':
                depth += 1
            elif text[j] == '}':
                depth -= 1
                if depth == 0:
                    j += 1; break
            j += 1
        i = j
    return "".join(out)

def remove_server_blocks_for_ports(text, ports):
    out, i = [], 0
    pat = re.compile(r'server\s*\{')
    while True:
        m = pat.search(text, i)
        if not m:
            out.append(text[i:]); break
        depth, j = 0, m.end() - 1
        while j < len(text):
            if text[j] == '{':
                depth += 1
            elif text[j] == '}':
                depth -= 1
                if depth == 0:
                    j += 1; break
            j += 1
        block = text[m.start():j]
        if any(re.search(r'listen\s+' + re.escape(p) + r'\b', block) for p in ports):
            out.append(text[i:m.start()])
        else:
            out.append(text[i:j])
        i = j
    return "".join(out)

path = sys.argv[1]
with open(path) as f:
    text = f.read()

text = remove_blocks(text, r'location\s+/ssh-ws\s*\{')
text = remove_server_blocks_for_ports(text, ["8880", "8080", "2080", "2082"])
text = re.sub(r'[ \t]*#.*SSH-WS.*\n', '', text)
text = re.sub(r'\n{3,}', '\n\n', text)

with open(path, "w") as f:
    f.write(text)
PYEOF_NGINXCLEAN

  if nginx -t 2>/dev/null; then
    systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null
    echo -e "${GREEN}[OK]${NC} Nginx dibersihkan dari config /ssh-ws lama & di-reload (backup: $BACKUP)"
  else
    echo -e "${RED}[ERROR]${NC} nginx -t gagal setelah dibersihkan, mengembalikan config asal..."
    cp "$BACKUP" "$NGINX_XRAY_CONF"
    echo -e "${YELLOW}[WARN]${NC} Config Nginx dikembalikan seperti semula. Cek manual: $NGINX_XRAY_CONF"
  fi
else
  echo -e "\n${CYAN}[*]${NC} Tidak ada config /ssh-ws lama di Nginx, lewati pembersihan."
fi

# ─── 9. Firewall (aditif, tidak menutup port lain) ─────────
echo -e "\n${CYAN}[*]${NC} Membuka port firewall untuk SSH-WS/SSL..."
iptables -I INPUT -p tcp --dport "$WS_OPENSSH_PORT" -j ACCEPT 2>/dev/null
iptables -I INPUT -p tcp --dport "$WS_DROPBEAR_PORT" -j ACCEPT 2>/dev/null
iptables -I INPUT -p tcp --dport "$STUNNEL_SSL_PORT" -j ACCEPT 2>/dev/null
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4 2>/dev/null
echo -e "${GREEN}[OK]${NC} Port $WS_OPENSSH_PORT, $WS_DROPBEAR_PORT, $STUNNEL_SSL_PORT dibuka"

# ─── 10. Enable & start semua service ──────────────────────
echo -e "\n${CYAN}[*]${NC} Mengaktifkan service..."
for svc in ws-openssh ws-dropbear ws-stunnel stunnel4; do
  systemctl enable "$svc" 2>/dev/null
  systemctl restart "$svc" 2>/dev/null
done

sleep 1
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   STATUS SERVICE SETELAH INSTALL   ${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
for svc in ws-openssh ws-dropbear ws-stunnel stunnel4; do
  if systemctl is-active --quiet "$svc"; then
    echo -e "  $svc : ${GREEN}● RUNNING${NC}"
  else
    echo -e "  $svc : ${RED}● STOPPED${NC}  (cek: journalctl -u $svc -n 30 --no-pager)"
  fi
done
echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${WHITE}   ✓  ADDON SSH-WS / SSH-SSL BERHASIL DIINSTALL   ${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "  SSH-WS (OpenSSH)  : $DOMAIN : $WS_OPENSSH_PORT   (connect langsung, tanpa Nginx)"
echo -e "  SSH-WS (Dropbear) : $DOMAIN : $WS_DROPBEAR_PORT  (connect langsung, tanpa Nginx)"
echo -e "  SSH-SSL           : $DOMAIN : $STUNNEL_SSL_PORT  (stunnel4 -> ws-stunnel)"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
if [[ "$PY2_BIN" == "/usr/bin/python2" ]] && ! command -v python2 &>/dev/null; then
  echo -e "${RED}[PENTING]${NC} Python 2 belum terpasang di server ini -> service ws-openssh/"
  echo -e "${RED}[PENTING]${NC} ws-dropbear/ws-stunnel KEMUNGKINAN BESAR gagal start. Pasang Python 2"
  echo -e "${RED}[PENTING]${NC} lalu jalankan: systemctl restart ws-openssh ws-dropbear ws-stunnel"
fi
