#!/bin/bash
SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SLINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

nginx_menu() {
  clear
  local domain=$(get_domain)
  local st
  systemctl is-active --quiet nginx \
    && st="${GREEN}● RUNNING${NC}" || st="${RED}● STOPPED${NC}"

  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ⚡  NGINX MANAGEMENT  ⚡${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Status   ${NC}: $st"
  echo -e "  ${YELLOW}Domain   ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Port     ${NC}: ${WHITE}80${NC} (nTLS + redirect)   ${WHITE}443${NC} (TLS)"
  echo -e "  ${YELLOW}Config   ${NC}: ${WHITE}/etc/nginx/conf.d/xray.conf${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -e "  ${WHITE}NGINX MANAGEMENT${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}[1]${NC}  Start Nginx"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${RED}[2]${NC}  Stop Nginx"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}[3]${NC}  Restart Nginx"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${CYAN}[4]${NC}  Reload Nginx"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}[5]${NC}  Test Konfigurasi"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}[6]${NC}  Lihat Error Log"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}[7]${NC}  Lihat Konfigurasi"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}[8]${NC}  Renew SSL Certificate"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${DIM}[0]${NC}  Kembali ke Menu Utama"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${WHITE}Pilih [0-8]${NC}: "
  read -r choice

  case "$choice" in
    1)
      systemctl start nginx 2>/dev/null \
        && echo -e "\n  ${GREEN}[✓] Nginx berhasil distart${NC}" \
        || echo -e "\n  ${RED}[!] Gagal start Nginx${NC}"
      sleep 2; nginx_menu ;;
    2)
      systemctl stop nginx 2>/dev/null \
        && echo -e "\n  ${YELLOW}[✓] Nginx dihentikan${NC}" \
        || echo -e "\n  ${RED}[!] Gagal stop Nginx${NC}"
      sleep 2; nginx_menu ;;
    3)
      systemctl restart nginx 2>/dev/null \
        && echo -e "\n  ${GREEN}[✓] Nginx direstart${NC}" \
        || echo -e "\n  ${RED}[!] Gagal restart Nginx${NC}"
      sleep 2; nginx_menu ;;
    4)
      systemctl reload nginx 2>/dev/null \
        && echo -e "\n  ${GREEN}[✓] Nginx direload${NC}" \
        || echo -e "\n  ${RED}[!] Gagal reload Nginx${NC}"
      sleep 2; nginx_menu ;;
    5)
      echo ""
      echo -e "  ${CYAN}$LINE${NC}"
      nginx -t 2>&1 | sed 's/^/  /'
      echo -e "  ${CYAN}$LINE${NC}"
      echo -ne "\n  ${DIM}Tekan Enter...${NC}"; read -r; nginx_menu ;;
    6)
      echo ""
      echo -e "  ${CYAN}$LINE${NC}"
      tail -30 /var/log/nginx/error.log 2>/dev/null | sed 's/^/  /' \
        || echo -e "  ${YELLOW}Log kosong atau tidak ada${NC}"
      echo -e "  ${CYAN}$LINE${NC}"
      echo -ne "\n  ${DIM}Tekan Enter...${NC}"; read -r; nginx_menu ;;
    7)
      echo ""
      echo -e "  ${CYAN}$LINE${NC}"
      cat /etc/nginx/conf.d/xray.conf 2>/dev/null | sed 's/^/  /' \
        || echo -e "  ${RED}[!] File tidak ditemukan${NC}"
      echo -e "  ${CYAN}$LINE${NC}"
      echo -ne "\n  ${DIM}Tekan Enter...${NC}"; read -r; nginx_menu ;;
    8)
      local dom=$(get_domain)
      echo -e "\n  ${CYAN}[*]${NC} Renewing SSL untuk ${WHITE}$dom${NC}..."
      systemctl stop nginx 2>/dev/null
      /root/.acme.sh/acme.sh --renew -d "$dom" --ecc --force 2>/dev/null \
        && echo -e "  ${GREEN}[✓] SSL berhasil diperbarui${NC}" \
        || echo -e "  ${RED}[!] Renew gagal, cek log acme.sh${NC}"
      systemctl start nginx 2>/dev/null
      sleep 2; nginx_menu ;;
    0) bash $SCRIPT_DIR/menu.sh ;;
    *) echo -e "  ${RED}[!] Pilihan tidak valid${NC}"; sleep 1; nginx_menu ;;
  esac
}

nginx_menu
