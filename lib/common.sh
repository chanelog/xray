#!/bin/bash
# =============================================================================
# common.sh - shared helpers for the tunnel-suite menu system
# Sourced by: menu.sh, ssh_manager.sh, xray_manager.sh, xray_expiry.sh
# =============================================================================

# ---- Paths --------------------------------------------------------------
# Using ${VAR:=default} so these can be overridden by exporting them before
# sourcing this file (used by the test harness; normal installs just get
# the defaults below).
: "${TS_ROOT:=/etc/tunnel-suite}"
: "${TS_BIN:=/usr/local/bin}"
: "${TS_DOMAIN_FILE:=$TS_ROOT/domain.conf}"
: "${XRAY_CONFIG:=/usr/local/etc/xray/config.json}"
: "${SSH_DB:=$TS_ROOT/ssh-users.db}"
export TS_ROOT TS_BIN TS_DOMAIN_FILE XRAY_CONFIG SSH_DB

mkdir -p "$TS_ROOT" 2>/dev/null

# ---- Colors ---------------------------------------------------------------
C_RESET='\033[0m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[0;31m'
C_CYAN='\033[0;36m'
C_BLUE='\033[0;34m'
C_BOLD='\033[1m'
LINE_COLOR='\033[0;34m'

hr() { echo -e "${LINE_COLOR}------------------------------------------------------------${C_RESET}"; }

header() {
    clear
    echo -e "${C_CYAN}${C_BOLD}"
    echo "  =============================================="
    echo "    TUNNEL SUITE - SSH/XRAY MANAGER"
    echo "  =============================================="
    echo -e "${C_RESET}"
}

pause() {
    echo
    read -rp "Tekan [Enter] untuk kembali ke menu... " _
}

need_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        echo -e "${C_RED}Script ini harus dijalankan sebagai root.${C_RESET}"
        exit 1
    fi
}

get_domain() {
    if [[ -f "$TS_DOMAIN_FILE" ]]; then
        cat "$TS_DOMAIN_FILE"
    else
        echo "domain-belum-diset.local"
    fi
}

get_ip() {
    curl -s -4 --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'
}

svc_status_dot() {
    # $1 = service name -> prints colored ON/OFF
    local svc="$1"
    if systemctl is-active --quiet "$svc" 2>/dev/null; then
        echo -e "${C_GREEN}ON${C_RESET}"
    else
        echo -e "${C_RED}OFF${C_RESET}"
    fi
}

require_cmd() {
    # $1 = command, $2 = apt package name (optional, defaults to $1)
    local cmd="$1"
    local pkg="${2:-$1}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${C_YELLOW}[*] Menginstall dependency: $pkg${C_RESET}"
        apt-get update -y -qq && apt-get install -y -qq "$pkg"
    fi
}

today() { date +%F; }

days_left() {
    # $1 = expiry date (YYYY-MM-DD) -> number of days left (can be negative)
    local exp="$1"
    local exp_s today_s
    exp_s=$(date -d "$exp" +%s 2>/dev/null) || { echo 0; return; }
    today_s=$(date -d "$(today)" +%s)
    echo $(( (exp_s - today_s) / 86400 ))
}

random_password() {
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 10
}

confirm() {
    # $1 = prompt -> returns 0 if user typed y/Y
    local ans
    read -rp "$1 [y/N]: " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}
