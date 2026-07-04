#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - LIBRARY FUNCTIONS
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
DB_DIR="$SCRIPT_DIR/db"
XRAY_CONFIG="/etc/xray/config.json"

# ─── Colors ────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─── Get Domain ────────────────────────────────────────────
get_domain() {
  cat $SCRIPT_DIR/domain 2>/dev/null || echo "unknown"
}

# ─── Get Server IP ─────────────────────────────────────────
get_server_ip() {
  curl -s4 --max-time 3 https://ifconfig.me 2>/dev/null || \
  curl -s4 --max-time 3 https://api.ipify.org 2>/dev/null || \
  hostname -I | awk '{print $1}'
}

# ─── Get VPS Info ──────────────────────────────────────────
get_cpu_info() {
  grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ *//'
}

get_cpu_cores() {
  nproc
}

get_cpu_usage() {
  top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d. -f1 2>/dev/null || echo "N/A"
}

get_mem_usage() {
  free -m | awk 'NR==2{printf "%sMB / %sMB (%.0f%%)", $3, $2, $3*100/$2}'
}

get_disk_usage() {
  df -h / | awk 'NR==2{printf "%s / %s (%s)", $3, $2, $5}'
}

get_uptime() {
  uptime -p 2>/dev/null | sed 's/up //' || uptime | awk '{print $3,$4}' | sed 's/,//'
}

get_os_info() {
  . /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || cat /etc/issue | head -1
}

get_kernel() {
  uname -r
}

get_load_avg() {
  uptime | awk -F'load average: ' '{print $2}'
}

get_network_usage() {
  local iface=$(ip route | grep default | awk '{print $5}' | head -1)
  if [[ -n "$iface" ]]; then
    local rx=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
    local tx=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
    echo "↓$(numfmt --to=iec $rx 2>/dev/null || echo ${rx}B) ↑$(numfmt --to=iec $tx 2>/dev/null || echo ${tx}B)"
  else
    echo "N/A"
  fi
}

# ─── Service Status ────────────────────────────────────────
service_status() {
  local svc="$1"
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    echo -e "${GREEN}● ON${NC}"
  else
    echo -e "${RED}● OFF${NC}"
  fi
}

service_status_text() {
  local svc="$1"
  systemctl is-active --quiet "$svc" 2>/dev/null && echo "ON" || echo "OFF"
}

# ─── Check Xray Protocol Status ────────────────────────────
xray_inbound_exists() {
  local tag="$1"
  jq -e --arg t "$tag" '.inbounds[] | select(.tag == $t)' "$XRAY_CONFIG" &>/dev/null
}

# ─── UUID Generator ────────────────────────────────────────
gen_uuid() {
  cat /proc/sys/kernel/random/uuid 2>/dev/null || \
  uuid 2>/dev/null || \
  python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
  openssl rand -hex 16 | sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.\{12\}\)/\1-\2-\3-\4-\5/'
}

# ─── Date Helpers ──────────────────────────────────────────
get_exp_date() {
  local days="$1"
  date -d "+${days} days" +"%Y-%m-%d"
}

days_until_exp() {
  local exp="$1"
  local today=$(date +%s)
  local expd=$(date -d "$exp" +%s 2>/dev/null || echo 0)
  echo $(( (expd - today) / 86400 ))
}

is_expired() {
  local exp="$1"
  local days=$(days_until_exp "$exp")
  [[ $days -lt 0 ]]
}

# ─── VMess Account Management ──────────────────────────────
DB_VMESS="$DB_DIR/vmess.db"
DB_VLESS="$DB_DIR/vless.db"

create_vmess() {
  local username="$1"
  local days="$2"
  local uuid=$(gen_uuid)
  local exp=$(get_exp_date "$days")
  local created=$(date +"%Y-%m-%d")

  # Add to database
  echo "$username|$uuid|$exp|$created" >> "$DB_VMESS"

  # Add to xray config
  local tmp=$(mktemp)
  jq --arg uuid "$uuid" --arg email "$username" \
    '(.inbounds[] | select(.tag == "vmess-ws-tls" or .tag == "vmess-ws-ntls") | .settings.clients) += [{"id": $uuid, "alterId": 0, "email": $email}]' \
    "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"

  systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
  echo "$uuid"
}

create_vless() {
  local username="$1"
  local days="$2"
  local uuid=$(gen_uuid)
  local exp=$(get_exp_date "$days")
  local created=$(date +"%Y-%m-%d")

  echo "$username|$uuid|$exp|$created" >> "$DB_VLESS"

  local tmp=$(mktemp)
  jq --arg uuid "$uuid" --arg email "$username" \
    '(.inbounds[] | select(.tag == "vless-ws-tls" or .tag == "vless-ws-ntls") | .settings.clients) += [{"id": $uuid, "email": $email, "flow": ""}]' \
    "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"

  systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
  echo "$uuid"
}

delete_vmess() {
  local username="$1"
  local uuid=$(grep "^$username|" "$DB_VMESS" | cut -d'|' -f2)

  sed -i "/^$username|/d" "$DB_VMESS"

  local tmp=$(mktemp)
  jq --arg email "$username" \
    '(.inbounds[] | select(.tag | startswith("vmess")) | .settings.clients) |= map(select(.email != $email))' \
    "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"

  systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
}

delete_vless() {
  local username="$1"
  sed -i "/^$username|/d" "$DB_VLESS"

  local tmp=$(mktemp)
  jq --arg email "$username" \
    '(.inbounds[] | select(.tag | startswith("vless")) | .settings.clients) |= map(select(.email != $email))' \
    "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"

  systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
}

renew_vmess() {
  local username="$1"
  local days="$2"
  local exp=$(get_exp_date "$days")
  sed -i "s/^$username|\([^|]*\)|\([^|]*\)|\(.*\)$/$username|\1|$exp|\3/" "$DB_VMESS"
}

renew_vless() {
  local username="$1"
  local days="$2"
  local exp=$(get_exp_date "$days")
  sed -i "s/^$username|\([^|]*\)|\([^|]*\)|\(.*\)$/$username|\1|$exp|\3/" "$DB_VLESS"
}

get_vmess_info() {
  local username="$1"
  grep "^$username|" "$DB_VMESS"
}

get_vless_info() {
  local username="$1"
  grep "^$username|" "$DB_VLESS"
}

list_vmess() {
  cat "$DB_VMESS" 2>/dev/null
}

list_vless() {
  cat "$DB_VLESS" 2>/dev/null
}

count_vmess() {
  wc -l < "$DB_VMESS" 2>/dev/null || echo 0
}

count_vless() {
  wc -l < "$DB_VLESS" 2>/dev/null || echo 0
}

delete_expired() {
  local today=$(date +%s)
  while IFS='|' read -r user uuid exp created; do
    local expd=$(date -d "$exp" +%s 2>/dev/null || echo 0)
    if [[ $expd -lt $today ]]; then
      delete_vmess "$user"
      echo "[$(date)] Deleted expired VMess: $user (exp: $exp)"
    fi
  done < <(cat "$DB_VMESS" 2>/dev/null)

  while IFS='|' read -r user uuid exp created; do
    local expd=$(date -d "$exp" +%s 2>/dev/null || echo 0)
    if [[ $expd -lt $today ]]; then
      delete_vless "$user"
      echo "[$(date)] Deleted expired VLess: $user (exp: $exp)"
    fi
  done < <(cat "$DB_VLESS" 2>/dev/null)
}

# ─── Generate VMess Link ────────────────────────────────────
gen_vmess_link() {
  local user="$1"
  local uuid="$2"
  local domain="$3"
  local type="${4:-tls}"  # tls or ntls
  local remark="$5"

  local port path
  if [[ "$type" == "tls" ]]; then
    port=443; path="/vmess-ws"
  else
    port=80; path="/vmess-ntls"
  fi

  local json="{\"v\":\"2\",\"ps\":\"${remark:-$user-vmess-$type}\",\"add\":\"$domain\",\"port\":\"$port\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$domain\",\"path\":\"$path\",\"tls\":\"$([ "$type" == "tls" ] && echo "tls" || echo "")\",\"sni\":\"$domain\"}"
  echo "vmess://$(echo -n "$json" | base64 -w 0)"
}

# ─── Generate VLess Link ────────────────────────────────────
gen_vless_link() {
  local user="$1"
  local uuid="$2"
  local domain="$3"
  local type="${4:-tls}"
  local remark="$5"

  local port path security
  if [[ "$type" == "tls" ]]; then
    port=443; path="/vless-ws"; security="tls"
  else
    port=80; path="/vless-ntls"; security="none"
  fi

  echo "vless://${uuid}@${domain}:${port}?encryption=none&security=${security}&type=ws&host=${domain}&path=${path}&sni=${domain}#${remark:-$user-vless-$type}"
}

# ─── Change Domain ─────────────────────────────────────────
change_domain() {
  local new_domain="$1"
  local old_domain=$(get_domain)

  # Update nginx config
  sed -i "s/$old_domain/$new_domain/g" /etc/nginx/conf.d/xray.conf 2>/dev/null

  # Request new SSL
  systemctl stop nginx 2>/dev/null
  /root/.acme.sh/acme.sh --issue --standalone -d "$new_domain" \
    --keylength ec-256 --httpport 80 2>/dev/null

  /root/.acme.sh/acme.sh --installcert -d "$new_domain" \
    --ecc \
    --key-file /etc/ssl/xray/xray.key \
    --fullchain-file /etc/ssl/xray/xray.crt \
    --reloadcmd "systemctl restart xray nginx 2>/dev/null" 2>/dev/null

  # Update domain file
  echo "$new_domain" > $SCRIPT_DIR/domain

  nginx -t 2>/dev/null && systemctl restart nginx 2>/dev/null
  systemctl restart xray 2>/dev/null
}

# ============================================================
#   ADDON: SSH / SSH-WS / SSH-SSL(stunnel) / SSH-WS-nTLS
#   (Ditambahkan - tidak mengubah fungsi di atas)
# ============================================================
DB_SSH="$DB_DIR/ssh.db"
WS_PROXY_PORT=700          # port lokal ws-proxy (internal only) — dipakai
                           # bersama oleh Nginx (SSH-WS) dan Stunnel (SSH-SSL)
SSH_BACKEND_PORT=143       # diteruskan ke port dropbear yang sudah ada
STUNNEL_SSL_PORT=445       # port publik untuk SSH-SSL (stunnel4)

gen_ssh_password() {
  tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 10 || \
  openssl rand -base64 8 | tr -dc 'A-Za-z0-9' | head -c 10
}

create_ssh() {
  local username="$1"
  local days="$2"
  local password="${3:-$(gen_ssh_password)}"
  local exp=$(get_exp_date "$days")
  local created=$(date +"%Y-%m-%d")

  # Buat user sistem (shell dibatasi, tanpa akses login interaktif penuh)
  useradd -e "$exp" -s /bin/false -M "$username" 2>/dev/null
  echo "$username:$password" | chpasswd 2>/dev/null

  echo "$username|$password|$exp|$created" >> "$DB_SSH"
  echo "$password"
}

delete_ssh() {
  local username="$1"
  userdel -f "$username" 2>/dev/null
  sed -i "/^$username|/d" "$DB_SSH"
}

renew_ssh() {
  local username="$1"
  local days="$2"
  local exp=$(get_exp_date "$days")
  chage -E "$exp" "$username" 2>/dev/null
  sed -i "s/^$username|\([^|]*\)|\([^|]*\)|\(.*\)$/$username|\1|$exp|\3/" "$DB_SSH"
}

get_ssh_info() {
  local username="$1"
  grep "^$username|" "$DB_SSH" 2>/dev/null
}

list_ssh() {
  cat "$DB_SSH" 2>/dev/null
}

count_ssh() {
  wc -l < "$DB_SSH" 2>/dev/null || echo 0
}

delete_expired_ssh() {
  local today=$(date +%s)
  while IFS='|' read -r user pass exp created; do
    [[ -z "$user" ]] && continue
    local expd=$(date -d "$exp" +%s 2>/dev/null || echo 0)
    if [[ $expd -lt $today ]]; then
      delete_ssh "$user"
      echo "[$(date)] Deleted expired SSH: $user (exp: $exp)"
    fi
  done < <(list_ssh)
}

# ─── Layanan yang dikelola (untuk menu status on/off) ───────
MANAGED_SERVICES=(xray nginx dropbear stunnel4 ws-proxy)

service_display_name() {
  case "$1" in
    xray)      echo "Xray (VMess/VLess)" ;;
    nginx)     echo "Nginx" ;;
    dropbear)  echo "Dropbear SSH" ;;
    stunnel4)  echo "Stunnel4 (SSH-SSL)" ;;
    ws-proxy)  echo "SSH-WS/SSL Proxy" ;;
    *)         echo "$1" ;;
  esac
}

is_service_installed() {
  local svc="$1"
  systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\.service" && return 0
  command -v "$svc" &>/dev/null && return 0
  return 1
}

service_toggle_start()   { systemctl start   "$1" 2>/dev/null || service "$1" start   2>/dev/null; }
service_toggle_stop()    { systemctl stop    "$1" 2>/dev/null || service "$1" stop    2>/dev/null; }
service_toggle_restart() { systemctl restart "$1" 2>/dev/null || service "$1" restart 2>/dev/null; }

# ============================================================
#   ADDON: Auto-Update Script
# ============================================================
UPDATE_RAW="https://raw.githubusercontent.com/chanelog/xray/main"
VERSION_FILE="$SCRIPT_DIR/VERSION"

get_local_version() {
  cat "$VERSION_FILE" 2>/dev/null || echo "0.0.0"
}

get_remote_version() {
  curl -s --max-time 10 "$UPDATE_RAW/VERSION" 2>/dev/null
}

check_update_available() {
  local local_v remote_v
  local_v=$(get_local_version)
  remote_v=$(get_remote_version)
  [[ -z "$remote_v" ]] && return 1
  [[ "$local_v" != "$remote_v" ]] && { echo "$remote_v"; return 0; }
  return 1
}

# Daftar file inti yang disinkronkan saat update.
# File didownload ke lokasi sementara dulu — file asli yang berjalan
# TIDAK disentuh kalau proses download gagal.
UPDATE_FILES=(
  "lib.sh"
  "menu.sh"
  "menu/vmess.sh"
  "menu/vless.sh"
  "menu/nginx.sh"
  "menu/dropbear.sh"
  "menu/sysinfo.sh"
  "menu/changedomain.sh"
  "menu/uninstall.sh"
  "menu/sshws.sh"
  "menu/services.sh"
  "menu/update.sh"
)

# Update 1 file dengan aman: download ke file sementara, hanya
# menimpa file asli jika download berhasil dan tidak kosong.
update_fetch_file() {
  local relpath="$1"
  local tmp
  tmp=$(mktemp)
  if wget -q --timeout=30 "$UPDATE_RAW/$relpath" -O "$tmp" && [[ -s "$tmp" ]]; then
    mkdir -p "$(dirname "$SCRIPT_DIR/$relpath")"
    cp "$tmp" "$SCRIPT_DIR/$relpath"
    chmod +x "$SCRIPT_DIR/$relpath" 2>/dev/null
    rm -f "$tmp"
    return 0
  else
    rm -f "$tmp"
    return 1
  fi
}

# Update binary/fitur addon (mis. sshws installer) jika tersedia versi baru
update_fetch_addon_bin() {
  local tmp
  tmp=$(mktemp)
  if wget -q --timeout=30 "$UPDATE_RAW/addon/install-sshws.sh" -O "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
    mkdir -p "$SCRIPT_DIR/addon"
    cp "$tmp" "$SCRIPT_DIR/addon/install-sshws.sh"
    chmod +x "$SCRIPT_DIR/addon/install-sshws.sh"
    rm -f "$tmp"
    return 0
  else
    rm -f "$tmp"
    return 1
  fi
}

run_update() {
  local remote_v="$1"
  local ok=true
  local f
  for f in "${UPDATE_FILES[@]}"; do
    echo -ne "  Updating $f..."
    if update_fetch_file "$f"; then
      echo -e " ${GREEN}OK${NC}"
    else
      echo -e " ${YELLOW}SKIP (tidak ditemukan / gagal)${NC}"
      ok=false
    fi
  done

  echo -ne "  Updating addon/install-sshws.sh..."
  if update_fetch_addon_bin; then
    echo -e " ${GREEN}OK${NC}"
  else
    echo -e " ${YELLOW}SKIP${NC}"
  fi

  echo "$remote_v" > "$VERSION_FILE"
  [[ "$ok" == "true" ]]
}

# Make functions available when sourced
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && "$@"
