#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - UNINSTALL MENU
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

uninstall_menu() {
  clear
  echo -e "${RED}╔══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${RED}║${WHITE}              ◈  UNINSTALL SCRIPT  ◈                          ${RED}║${NC}"
  echo -e "${RED}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${RED}║${NC}"
  echo -e "${RED}║${NC}  ${RED}⚠  PERINGATAN! TINDAKAN INI TIDAK DAPAT DIBATALKAN!${NC}"
  echo -e "${RED}║${NC}"
  echo -e "${RED}║${NC}  ${WHITE}Yang akan dihapus:${NC}"
  echo -e "${RED}║${NC}  ${YELLOW}•${NC} Xray-core dan semua konfigurasi"
  echo -e "${RED}║${NC}  ${YELLOW}•${NC} Nginx dan konfigurasi VPN"
  echo -e "${RED}║${NC}  ${YELLOW}•${NC} Dropbear SSH (konfigurasi VPN)"
  echo -e "${RED}║${NC}  ${YELLOW}•${NC} SSL Certificate"
  echo -e "${RED}║${NC}  ${YELLOW}•${NC} Semua database akun VMess & VLess"
  echo -e "${RED}║${NC}  ${YELLOW}•${NC} Script /etc/vpn-script"
  echo -e "${RED}║${NC}  ${YELLOW}•${NC} Symlink /usr/local/bin/vpn"
  echo -e "${RED}║${NC}"
  echo -e "${RED}║${NC}  ${GREEN}Yang TIDAK dihapus:${NC}"
  echo -e "${RED}║${NC}  ${GREEN}•${NC} User system yang ada"
  echo -e "${RED}║${NC}  ${GREEN}•${NC} Data lain di server"
  echo -e "${RED}║${NC}"
  echo -e "${RED}╚══════════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  echo -ne "  ${RED}Ketik 'HAPUS' untuk konfirmasi uninstall${NC}: "
  read -r confirm

  if [[ "$confirm" != "HAPUS" ]]; then
    echo -e "  ${YELLOW}[!] Uninstall dibatalkan${NC}"
    sleep 2
    bash $SCRIPT_DIR/menu.sh
    return
  fi

  echo ""
  echo -e "  ${CYAN}[*]${NC} Menghentikan layanan..."
  systemctl stop xray 2>/dev/null
  systemctl disable xray 2>/dev/null

  echo -e "  ${CYAN}[*]${NC} Menghapus Xray..."
  rm -f /usr/local/bin/xray
  rm -rf /etc/xray
  rm -rf /var/log/xray
  rm -f /etc/systemd/system/xray.service

  echo -e "  ${CYAN}[*]${NC} Menghapus konfigurasi Nginx..."
  rm -f /etc/nginx/conf.d/xray.conf
  systemctl restart nginx 2>/dev/null

  echo -e "  ${CYAN}[*]${NC} Menghapus script dan database..."
  rm -rf $SCRIPT_DIR
  rm -f /usr/local/bin/vpn

  echo -e "  ${CYAN}[*]${NC} Menghapus SSL..."
  /root/.acme.sh/acme.sh --remove -d "$(cat /tmp/del_domain 2>/dev/null)" 2>/dev/null
  rm -rf /etc/ssl/xray

  echo -e "  ${CYAN}[*]${NC} Membersihkan cron..."
  crontab -l 2>/dev/null | grep -v "vpn-script\|acme" | crontab -

  systemctl daemon-reload 2>/dev/null

  echo ""
  echo -e "${GREEN}  ╔════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}  ║  ✓  Uninstall selesai!                    ║${NC}"
  echo -e "${GREEN}  ║  Script telah dihapus dari sistem.        ║${NC}"
  echo -e "${GREEN}  ╚════════════════════════════════════════════╝${NC}"
  echo ""
  exit 0
}

uninstall_menu
