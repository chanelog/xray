#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - DROPBEAR MENU
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

dropbear_menu() {
  clear
  local db_st=$(service_status dropbear)

  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${WHITE}              ◈  DROPBEAR SSH MANAGEMENT  ◈                   ${CYAN}║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Status${NC}  : $db_st"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Port 1${NC}  : ${WHITE}442${NC}  (SSH utama)"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Port 2${NC}  : ${WHITE}109${NC}  (SSH alternatif)"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Port 3${NC}  : ${WHITE}143${NC}  (SSH alternatif)"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Config${NC}  : ${WHITE}/etc/default/dropbear${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  ${GREEN}[1]${NC} ${WHITE}Start Dropbear${NC}"
  echo -e "${CYAN}║${NC}  ${RED}[2]${NC} ${WHITE}Stop Dropbear${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}[3]${NC} ${WHITE}Restart Dropbear${NC}"
  echo -e "${CYAN}║${NC}  ${CYAN}[4]${NC} ${WHITE}Lihat Konfigurasi${NC}"
  echo -e "${CYAN}║${NC}  ${WHITE}[5]${NC} ${WHITE}Lihat Log Dropbear${NC}"
  echo -e "${CYAN}║${NC}  ${WHITE}[6]${NC} ${WHITE}Ubah Port Dropbear${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  ${DIM}[0]${NC} ${WHITE}Kembali ke Menu Utama${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -ne "  ${WHITE}Pilih${NC} ${CYAN}[0-6]${NC}: "
  read -r choice

  case "$choice" in
    1) systemctl start dropbear && echo -e "  ${GREEN}[✓] Dropbear started${NC}" || service dropbear start; sleep 2; dropbear_menu ;;
    2) systemctl stop dropbear && echo -e "  ${YELLOW}[✓] Dropbear stopped${NC}" || service dropbear stop; sleep 2; dropbear_menu ;;
    3) systemctl restart dropbear 2>/dev/null || service dropbear restart; echo -e "  ${GREEN}[✓] Dropbear restarted${NC}"; sleep 2; dropbear_menu ;;
    4) cat /etc/default/dropbear; echo ""; echo -ne "  ${DIM}Tekan Enter...${NC}"; read -r; dropbear_menu ;;
    5) journalctl -u dropbear -n 30 2>/dev/null || tail -30 /var/log/syslog | grep dropbear; echo ""; echo -ne "  ${DIM}Tekan Enter...${NC}"; read -r; dropbear_menu ;;
    6)
      echo -ne "  ${YELLOW}Port baru (contoh: 2222)${NC}: "
      read -r newport
      if [[ "$newport" =~ ^[0-9]+$ ]]; then
        sed -i "s/DROPBEAR_PORT=[0-9]*/DROPBEAR_PORT=$newport/" /etc/default/dropbear
        systemctl restart dropbear 2>/dev/null || service dropbear restart
        echo -e "  ${GREEN}[✓] Port diubah ke $newport${NC}"
      else
        echo -e "  ${RED}[!] Port tidak valid${NC}"
      fi
      sleep 2; dropbear_menu ;;
    0) bash $SCRIPT_DIR/menu.sh ;;
    *) echo -e "${RED}[!] Tidak valid${NC}"; sleep 1; dropbear_menu ;;
  esac
}

dropbear_menu
