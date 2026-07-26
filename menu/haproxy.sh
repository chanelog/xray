#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - HAProxy Status & Toggle Menu
#   Menampilkan status HAProxy SSH-WS SSL dengan ON/OFF toggle
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

haproxy_header() {
  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}         ⚡  HAProxy SSH-WS SSL Management  ⚡${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  
  local haproxy_status
  if systemctl is-active --quiet haproxy 2>/dev/null; then
    haproxy_status="${GREEN}● ON${NC}"
  else
    haproxy_status="${RED}● OFF${NC}"
  fi
  
  echo -e "  ${YELLOW}HAProxy Status${NC}      : $haproxy_status"
  echo -e "  ${YELLOW}Service${NC}             : haproxy"
  echo -e "  ${YELLOW}Port${NC}                : ${HAPROXY_SSL_PORT:-444} (SSL -> OpenSSH, langsung; pasangan Stunnel4 di port $STUNNEL_SSL_PORT -> Dropbear)"
  echo -e "  ${YELLOW}Config${NC}              : /etc/haproxy/conf.d/sshws-ssl.cfg"
  echo -e "  ${YELLOW}Certificate${NC}        : /etc/ssl/xray/xray.pem"
  echo -e "  ${YELLOW}Stats Dashboard${NC}    : http://127.0.0.1:8404/stats"
  
  echo -e "${CYAN}$LINE${NC}"
}

haproxy_toggle_menu() {
  haproxy_header
  echo ""
  echo -e "  ${WHITE}HAProxy SSH-WS SSL ACTIONS${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}[1]${NC}  Start HAProxy"
  echo -e "  ${RED}[2]${NC}  Stop HAProxy"
  echo -e "  ${YELLOW}[3]${NC}  Restart HAProxy"
  echo -e "  ${CYAN}[4]${NC}  Enable Auto-Start (boot)"
  echo -e "  ${CYAN}[5]${NC}  Disable Auto-Start (boot)"
  echo -e "  ${BLUE}[6]${NC}  View HAProxy Config"
  echo -e "  ${BLUE}[7]${NC}  View HAProxy Logs"
  echo -e "  ${BLUE}[8]${NC}  Check Configuration"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${DIM}[0]${NC}  Kembali ke Menu Utama"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${WHITE}Pilih aksi [0-8]${NC}: "
  read -r choice

  case "$choice" in
    0)
      bash "$SCRIPT_DIR/menu.sh"
      return
      ;;
    1)
      if [[ ! -f /etc/haproxy/conf.d/sshws-ssl.cfg ]]; then
        echo -e "\n${YELLOW}[*]${NC} HAProxy belum pernah dikonfigurasi, menjalankan setup dulu..."
        bash "$SCRIPT_DIR/addon/haproxy-sshws-ssl.sh"
      else
        echo -e "\n${CYAN}[*]${NC} Starting HAProxy..."
        systemctl start haproxy 2>/dev/null
      fi
      if systemctl is-active --quiet haproxy; then
        echo -e "${GREEN}[✓]${NC} HAProxy started successfully"
      else
        echo -e "${RED}[✗]${NC} HAProxy failed to start"
      fi
      sleep 2
      haproxy_toggle_menu
      ;;
    2)
      echo -e "\n${CYAN}[*]${NC} Stopping HAProxy..."
      systemctl stop haproxy 2>/dev/null
      echo -e "${YELLOW}[✓]${NC} HAProxy stopped"
      sleep 2
      haproxy_toggle_menu
      ;;
    3)
      echo -e "\n${CYAN}[*]${NC} Restarting HAProxy..."
      systemctl restart haproxy 2>/dev/null
      if systemctl is-active --quiet haproxy; then
        echo -e "${GREEN}[✓]${NC} HAProxy restarted successfully"
      else
        echo -e "${RED}[✗]${NC} HAProxy restart failed"
      fi
      sleep 2
      haproxy_toggle_menu
      ;;
    4)
      echo -e "\n${CYAN}[*]${NC} Enabling auto-start on boot..."
      systemctl enable haproxy 2>/dev/null
      echo -e "${GREEN}[✓]${NC} Auto-start enabled"
      sleep 2
      haproxy_toggle_menu
      ;;
    5)
      echo -e "\n${CYAN}[*]${NC} Disabling auto-start on boot..."
      systemctl disable haproxy 2>/dev/null
      echo -e "${YELLOW}[✓]${NC} Auto-start disabled"
      sleep 2
      haproxy_toggle_menu
      ;;
    6)
      echo -e "\n${CYAN}[*]${NC} HAProxy Configuration:"
      echo -e "${CYAN}$LINE${NC}"
      if [[ -f /etc/haproxy/conf.d/sshws-ssl.cfg ]]; then
        cat /etc/haproxy/conf.d/sshws-ssl.cfg
      else
        echo -e "${RED}[!] HAProxy SSH-WS SSL config not found${NC}"
      fi
      echo -e "${CYAN}$LINE${NC}"
      echo ""
      echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
      haproxy_toggle_menu
      ;;
    7)
      echo -e "\n${CYAN}[*]${NC} HAProxy Logs (last 50 lines):"
      echo -e "${CYAN}$LINE${NC}"
      journalctl -u haproxy -n 50 --no-pager 2>/dev/null || echo "No logs available"
      echo -e "${CYAN}$LINE${NC}"
      echo ""
      echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
      haproxy_toggle_menu
      ;;
    8)
      echo -e "\n${CYAN}[*]${NC} Checking HAProxy configuration..."
      echo -e "${CYAN}$LINE${NC}"
      haproxy -f /etc/haproxy/haproxy.cfg -c 2>&1
      echo -e "${CYAN}$LINE${NC}"
      echo ""
      echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
      haproxy_toggle_menu
      ;;
    *)
      echo -e "  ${RED}[!] Pilihan tidak valid${NC}"
      sleep 1
      haproxy_toggle_menu
      ;;
  esac
}

haproxy_toggle_menu
