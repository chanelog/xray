#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - NGINX MENU
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

nginx_menu() {
  clear
  local nginx_st=$(service_status nginx)
  local domain=$(get_domain)

  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${WHITE}               ◈  NGINX MANAGEMENT  ◈                        ${CYAN}║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Status Nginx${NC}  : $nginx_st"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Domain${NC}        : ${WHITE}$domain${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Port HTTP${NC}     : ${WHITE}80${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Port HTTPS${NC}    : ${WHITE}443 (TLS)${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Port nTLS${NC}     : ${WHITE}80${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Config${NC}        : ${WHITE}/etc/nginx/conf.d/xray.conf${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  ${GREEN}[1]${NC} ${WHITE}Start Nginx${NC}"
  echo -e "${CYAN}║${NC}  ${RED}[2]${NC} ${WHITE}Stop Nginx${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}[3]${NC} ${WHITE}Restart Nginx${NC}"
  echo -e "${CYAN}║${NC}  ${CYAN}[4]${NC} ${WHITE}Reload Nginx${NC}"
  echo -e "${CYAN}║${NC}  ${WHITE}[5]${NC} ${WHITE}Test Konfigurasi Nginx${NC}"
  echo -e "${CYAN}║${NC}  ${WHITE}[6]${NC} ${WHITE}Lihat Log Nginx${NC}"
  echo -e "${CYAN}║${NC}  ${WHITE}[7]${NC} ${WHITE}Lihat Konfigurasi${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}[8]${NC} ${WHITE}Renew SSL Certificate${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  ${DIM}[0]${NC} ${WHITE}Kembali ke Menu Utama${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -ne "  ${WHITE}Pilih${NC} ${CYAN}[0-8]${NC}: "
  read -r choice

  case "$choice" in
    1) systemctl start nginx && echo -e "  ${GREEN}[✓] Nginx started${NC}" || echo -e "  ${RED}[!] Gagal${NC}"; sleep 2; nginx_menu ;;
    2) systemctl stop nginx && echo -e "  ${YELLOW}[✓] Nginx stopped${NC}" || echo -e "  ${RED}[!] Gagal${NC}"; sleep 2; nginx_menu ;;
    3) systemctl restart nginx && echo -e "  ${GREEN}[✓] Nginx restarted${NC}" || echo -e "  ${RED}[!] Gagal${NC}"; sleep 2; nginx_menu ;;
    4) systemctl reload nginx && echo -e "  ${GREEN}[✓] Nginx reloaded${NC}" || echo -e "  ${RED}[!] Gagal${NC}"; sleep 2; nginx_menu ;;
    5) nginx -t; echo ""; echo -ne "  ${DIM}Tekan Enter...${NC}"; read -r; nginx_menu ;;
    6) tail -50 /var/log/nginx/error.log 2>/dev/null; echo ""; echo -ne "  ${DIM}Tekan Enter...${NC}"; read -r; nginx_menu ;;
    7) cat /etc/nginx/conf.d/xray.conf 2>/dev/null; echo ""; echo -ne "  ${DIM}Tekan Enter...${NC}"; read -r; nginx_menu ;;
    8)
      local dom=$(get_domain)
      systemctl stop nginx
      /root/.acme.sh/acme.sh --renew -d "$dom" --ecc --force 2>/dev/null && \
        echo -e "  ${GREEN}[✓] SSL renewed${NC}" || echo -e "  ${RED}[!] Renew gagal${NC}"
      systemctl start nginx
      sleep 2; nginx_menu ;;
    0) bash $SCRIPT_DIR/menu.sh ;;
    *) echo -e "${RED}[!] Tidak valid${NC}"; sleep 1; nginx_menu ;;
  esac
}

nginx_menu
