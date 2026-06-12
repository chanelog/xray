#!/usr/bin/env bash
# ============================================================
#   CHANELOG VPN SCRIPT - SSH Menu
# ============================================================

# This menu configures OpenSSH, Dropbear, SSH WS and SSH SSL WS ports
# Place this file at menu/ssh.sh and it is invoked from main menu.

SCRIPT_DIR="/etc/vpn-script"
# lib.sh will be sourced by menu.sh before executing this file, but source again to be safe
[ -f "$SCRIPT_DIR/lib.sh" ] && source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

BIN_REPO_DIR="/opt/chanelog_bin"
BIN_KAL9="${BIN_REPO_DIR}/kal9"

OPENSSH_PORTS=(443 80 22)
DROPBEAR_PORTS=(443 109)
SSH_WS_PORTS=(80 8080 "8081-9999")
SSH_SSL_WS_PORTS=(443)
SSL_TLS_RANGE="400-900"

_backup_file() {
  local f="$1"
  if [ -f "$f" ]; then
    cp -a -- "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)" || true
  fi
}

apply_openssh_ports() {
  local cfg="/etc/ssh/sshd_config"
  if [ ! -f "$cfg" ]; then
    echo "[!] $cfg tidak ditemukan. Pastikan OpenSSH terinstal."; return 1
  fi
  _backup_file "$cfg"
  # Remove existing Port lines (case-insensitive)
  sed -i '/^[[:space:]]*Port[[:space:]]\+/Id' "$cfg" || true
  for p in "${OPENSSH_PORTS[@]}"; do
    echo "Port $p" >> "$cfg"
  done
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || service ssh restart 2>/dev/null || true
  else
    service ssh restart 2>/dev/null || service sshd restart 2>/dev/null || true
  fi
  echo "[OK] OpenSSH: diterapkan ports: ${OPENSSH_PORTS[*]}"
}

apply_dropbear_ports() {
  local default_cfg="/etc/default/dropbear"
  if [ -f "$default_cfg" ]; then
    _backup_file "$default_cfg"
    local args=""
    for p in "${DROPBEAR_PORTS[@]}"; do
      args+=" -p $p"
    done
    if grep -q "^DROPBEAR_EXTRA_ARGS=" "$default_cfg"; then
      sed -i "s|^DROPBEAR_EXTRA_ARGS=.*|DROPBEAR_EXTRA_ARGS=\"$args\"|" "$default_cfg"
    else
      echo "DROPBEAR_EXTRA_ARGS=\"$args\"" >> "$default_cfg"
    fi
    if command -v systemctl >/dev/null 2>&1; then
      systemctl restart dropbear 2>/dev/null || service dropbear restart 2>/dev/null || true
    else
      service dropbear restart 2>/dev/null || true
    fi
    echo "[OK] Dropbear: diterapkan ports: ${DROPBEAR_PORTS[*]}"
  else
    echo "[WARN] /etc/default/dropbear tidak ditemukan. Mencoba start dropbear manual jika tersedia."
    pkill -f dropbear 2>/dev/null || true
    local p_args=()
    for p in "${DROPBEAR_PORTS[@]}"; do
      p_args+=("-p" "$p")
    done
    if command -v dropbear >/dev/null 2>&1; then
      dropbear "${p_args[@]}" -E &
      echo "[OK] Dropbear started manually with ports: ${DROPBEAR_PORTS[*]}"
    else
      echo "[ERROR] Binary dropbear tidak ditemukan di PATH. Install dropbear atau sesuaikan konfigurasi.";
      return 1
    fi
  fi
}

ensure_bin_repo() {
  if [ ! -d "$BIN_REPO_DIR" ]; then
    echo "Mencoba meng-clone repo chanelog/bin ke $BIN_REPO_DIR (jika tersedia)..."
    git clone https://github.com/chanelog/bin "$BIN_REPO_DIR" || true
  fi
}

run_ssh_ws_setup() {
  ensure_bin_repo
  if [ -x "$BIN_KAL9" ]; then
    echo "Menjalankan $BIN_KAL9 untuk SSH WS/SSL WS mapping (jika mendukung)..."
    "$BIN_KAL9" --setup-ssh-ws --ports "${SSH_WS_PORTS[*]}" || true
    echo "[OK] Perintah kal9 dieksekusi (jika tersedia)."
  else
    local found
    found=$(find "$BIN_REPO_DIR" -maxdepth 2 -type f \( -iname "*ssh*ws*" -o -iname "*kal9*" \) 2>/dev/null | head -n1)
    if [ -n "$found" ]; then
      echo "Ditemukan helper di: $found — jalankan sesuai dokumentasi repo chanelog/bin."
    else
      echo "[WARN] Tidak menemukan helper 'kal9' atau skrip ssh-ws di $BIN_REPO_DIR. Mohon periksa repo chanelog/bin."
    fi
  fi
}

note_ssl_tls_range() {
  echo "Catatan: SSL/TLS range yang direkomendasikan = $SSL_TLS_RANGE"
  echo "Pastikan rentang ini konsisten dengan konfigurasi server/domain/nginx/xray Anda."
}

menu_ssh() {
  while true; do
    clear
    echo -e "$LINE"
    echo -e "   SSH / Port Configuration Menu"
    echo -e "$LINE"
    echo -e "  [1] Terapkan OpenSSH ports: ${OPENSSH_PORTS[*]}"
    echo -e "  [2] Terapkan Dropbear ports: ${DROPBEAR_PORTS[*]}"
    echo -e "  [3] Setup SSH WS (cek chanelog/bin)"
    echo -e "  [4] Catatan SSL/TLS range ($SSL_TLS_RANGE)"
    echo -e "  [0] Kembali"
    echo -n "Pilih: "; read -r opt
    case "$opt" in
      1) apply_openssh_ports; read -rp "Selesai. Tekan Enter untuk kembali...";;
      2) apply_dropbear_ports; read -rp "Selesai. Tekan Enter untuk kembali...";;
      3) run_ssh_ws_setup; read -rp "Selesai. Tekan Enter untuk kembali...";;
      4) note_ssl_tls_range; read -rp "Tekan Enter...";;
      0) break;;
      *) echo "Pilihan tidak dikenal."; sleep 1 ;;
    esac
  done
}

# If executed directly, run the menu
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  menu_ssh
fi
