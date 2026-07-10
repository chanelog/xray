#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - ADDON INSTALLER: wstunnel (Rust)
#   Fitur: SSH-WS tambahan pakai binary wstunnel (erebe/wstunnel)
#          Port publik langsung $WSTUNNEL_PORT -> backend OpenSSH 127.0.0.1:22
#   Script & service proxy--ws diambil dari template di repo
#   (addon/files/proxy--ws.tpl & proxy--ws.service.tpl), BUKAN di-embed lagi.
#   Binary wstunnel sendiri tetap diambil dari rilis resmi erebe/wstunnel
#   di GitHub (bukan dari repo chanelog).
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; WHITE='\033[1;37m'; NC='\033[0m'

set -e

WSTUNNEL_URL="https://github.com/erebe/wstunnel/releases/download/v10.5.1/wstunnel_10.5.1_linux_amd64.tar.gz"
WSTUNNEL_TAR="wstunnel_10.5.1_linux_amd64.tar.gz"
WSTUNNEL_BIN="/usr/local/bin/wstunnel"
PROXY_WS_BIN="/usr/local/bin/proxy--ws"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/proxy--ws.service"

PORT="$WSTUNNEL_PORT"
CHAIN_NAME="KIGHMU_WSPROXY"

ensure_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} Script ini harus dijalankan sebagai root."
        exit 1
    fi
}

install_dependencies() {
    echo -e "${CYAN}[*]${NC} Menginstall dependensi (iptables, netfilter-persistent, wget)..."
    apt-get update -y -qq 2>/dev/null
    apt-get install -y -qq iptables iptables-persistent netfilter-persistent wget 2>/dev/null
}

setup_iptables_rules() {
    echo -e "${CYAN}[*]${NC} Konfigurasi iptables untuk port $PORT..."

    iptables -L $CHAIN_NAME -n >/dev/null 2>&1 || iptables -N $CHAIN_NAME
    iptables -F $CHAIN_NAME
    iptables -A $CHAIN_NAME -p tcp --dport $PORT -j ACCEPT

    if ! iptables -C INPUT -j $CHAIN_NAME 2>/dev/null; then
        iptables -I INPUT 1 -j $CHAIN_NAME
    fi

    netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4 2>/dev/null
    echo -e "${GREEN}[OK]${NC} Rule iptables untuk port $PORT terpasang & tersimpan."
}

install_wstunnel() {
    if [ -x "$WSTUNNEL_BIN" ]; then
        echo -e "${YELLOW}[SKIP]${NC} wstunnel sudah ada di $WSTUNNEL_BIN."
        return
    fi

    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" ]]; then
        echo -e "${YELLOW}[CATATAN]${NC} Arsitektur server ini: $ARCH. Binary yang dipasang"
        echo -e "${YELLOW}[CATATAN]${NC} ($WSTUNNEL_TAR) itu linux_amd64. Kalau server ini ARM"
        echo -e "${YELLOW}[CATATAN]${NC} (aarch64), binary ini TIDAK akan jalan — perlu ganti URL rilis"
        echo -e "${YELLOW}[CATATAN]${NC} ke varian linux_arm64 di halaman GitHub releases wstunnel."
    fi

    echo -e "${CYAN}[*]${NC} Download wstunnel..."
    cd /tmp
    wget -q -O "$WSTUNNEL_TAR" "$WSTUNNEL_URL"
    echo -e "${CYAN}[*]${NC} Extract..."
    tar -xzf "$WSTUNNEL_TAR"
    if [ ! -f "wstunnel" ]; then
        echo -e "${RED}[ERROR]${NC} Binary wstunnel tidak ditemukan setelah extract."
        exit 1
    fi
    chmod +x wstunnel
    mv wstunnel "$WSTUNNEL_BIN"
    rm -f "$WSTUNNEL_TAR"
    echo -e "${GREEN}[OK]${NC} wstunnel terpasang di $WSTUNNEL_BIN"
}

create_proxy_ws_script() {
    echo -e "${CYAN}[*]${NC} Mengambil template proxy--ws dari repo (domain: $DOMAIN, port: $PORT)..."
    TPL_TMP=$(mktemp)
    if ! wget -q --timeout=30 "$UPDATE_RAW/addon/files/proxy--ws.tpl" -O "$TPL_TMP" || [[ ! -s "$TPL_TMP" ]]; then
        echo -e "${RED}[ERROR]${NC} Gagal download addon/files/proxy--ws.tpl dari repo."
        rm -f "$TPL_TMP"
        exit 1
    fi
    sed -e "s#__DOMAIN__#${DOMAIN:-0.0.0.0}#g" -e "s#__PORT__#$PORT#g" "$TPL_TMP" > "$PROXY_WS_BIN"
    rm -f "$TPL_TMP"
    chmod +x "$PROXY_WS_BIN"
    echo -e "${GREEN}[OK]${NC} Script proxy--ws dibuat di $PROXY_WS_BIN"
}

create_systemd_service() {
    echo -e "${CYAN}[*]${NC} Mengambil template proxy--ws.service dari repo..."
    if ! wget -q --timeout=30 "$UPDATE_RAW/addon/files/proxy--ws.service.tpl" -O "$SYSTEMD_SERVICE_FILE" || [[ ! -s "$SYSTEMD_SERVICE_FILE" ]]; then
        echo -e "${RED}[ERROR]${NC} Gagal download addon/files/proxy--ws.service.tpl dari repo."
        exit 1
    fi

    systemctl daemon-reload
    systemctl enable proxy--ws.service 2>/dev/null
    systemctl restart proxy--ws.service
    echo -e "${GREEN}[OK]${NC} Service proxy--ws aktif."
}

main() {
    ensure_root
    DOMAIN=$(get_domain)
    if [[ -z "$DOMAIN" ]]; then
        echo -e "${RED}[ERROR]${NC} Domain belum di-set. Set domain lewat menu utama dulu."
        exit 1
    fi

    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}   INSTALL ADDON: SSH-WS via wstunnel (Rust)   ${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"

    install_dependencies
    setup_iptables_rules
    install_wstunnel
    create_proxy_ws_script
    create_systemd_service

    echo ""
    echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
    if systemctl is-active --quiet proxy--ws; then
        echo -e "${WHITE}   ✓  proxy--ws AKTIF di ws://$DOMAIN:$PORT   ${NC}"
    else
        echo -e "${RED}   ✗  proxy--ws GAGAL start — cek: journalctl -u proxy--ws -n 30${NC}"
    fi
    echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
    echo -e "  Backend  : 127.0.0.1:22 (OpenSSH)"
    echo -e "  Logs     : /var/log/proxy--ws.log dan /var/log/proxy--ws.err"
    echo -e "  Status   : systemctl status proxy--ws"
}

main "$@"
