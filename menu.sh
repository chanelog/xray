#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - MAIN MENU
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

show_header() {
  clear
  local domain=$(get_domain)
  local ip=$(get_server_ip)
  local mem=$(get_mem_usage)
  local disk=$(get_disk_usage)
  local uptime=$(get_uptime)
  local os=$(get_os_info)
  local kernel=$(get_kernel)
  local load=$(get_load_avg)
  local cpu_cores=$(get_cpu_cores)
  local net=$(get_network_usage)
  local vmess_count=$(count_vmess)
  local vless_count=$(count_vless)
  local ssh_count=$(count_ssh)

  local xray_st nginx_st db_st wsp_st stunnel_st
  systemctl is-active --quiet xray              && xray_st="${GREEN}● ON${NC}"    || xray_st="${RED}● OFF${NC}"
  systemctl is-active --quiet nginx             && nginx_st="${GREEN}● ON${NC}"   || nginx_st="${RED}● OFF${NC}"
  systemctl is-active --quiet dropbear          && db_st="${GREEN}● ON${NC}"      || db_st="${RED}● OFF${NC}"
  systemctl is-active --quiet ws-proxy 2>/dev/null   && wsp_st="${GREEN}● ON${NC}"     || wsp_st="${RED}● OFF${NC}"
  systemctl is-active --quiet stunnel4 2>/dev/null   && stunnel_st="${GREEN}● ON${NC}" || stunnel_st="${RED}● OFF${NC}"

  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}         ⚡  CHANELOG VPN TUNNEL MANAGER  ⚡${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Domain   ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}IP VPS   ${NC}: ${WHITE}$ip${NC}"
  echo -e "  ${YELLOW}OS       ${NC}: ${WHITE}$os${NC}"
  echo -e "  ${YELLOW}Kernel   ${NC}: ${WHITE}$kernel${NC}"
  echo -e "  ${YELLOW}CPU Core ${NC}: ${WHITE}$cpu_cores Core${NC}   ${YELLOW}Load Avg${NC}: ${WHITE}$load${NC}"
  echo -e "  ${YELLOW}Memory   ${NC}: ${WHITE}$mem${NC}"
  echo -e "  ${YELLOW}Disk     ${NC}: ${WHITE}$disk${NC}"
  echo -e "  ${YELLOW}Uptime   ${NC}: ${WHITE}$uptime${NC}"
  echo -e "  ${YELLOW}Network  ${NC}: ${WHITE}$net${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  Xray: $xray_st   Nginx: $nginx_st   Dropbear: $db_st   SSH-WS: $wsp_st   Stunnel4: $stunnel_st"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Akun VMess${NC}: ${WHITE}$vmess_count${NC}   ${YELLOW}Akun VLess${NC}: ${WHITE}$vless_count${NC}   ${YELLOW}Akun SSHWS${NC}: ${WHITE}$ssh_count${NC}"
  echo -e "${CYAN}$LINE${NC}"
}

main_menu() {
  show_header
  echo ""
  echo -e "  ${WHITE}MAIN MENU${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}[1]${NC}  SSHWS"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}[2]${NC}  VMess WS"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}[3]${NC}  VLess WS"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}[4]${NC}  Nginx Management"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}[5]${NC}  Dropbear Management"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}[6]${NC}  Change Domain"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}[7]${NC}  Update Script"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${RED}[8]${NC}  Uninstall"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}[9]${NC}  Status Layanan"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}[10]${NC} System"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${DIM}[0]${NC}  Exit"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${WHITE}Pilih menu [0-10]${NC}: "
  read -r choice

  case "$choice" in
    1) bash $SCRIPT_DIR/menu/sshws.sh ;;
    2) bash $SCRIPT_DIR/menu/vmess.sh ;;
    3) bash $SCRIPT_DIR/menu/vless.sh ;;
    4) bash $SCRIPT_DIR/menu/nginx.sh ;;
    5) bash $SCRIPT_DIR/menu/dropbear.sh ;;
    6) bash $SCRIPT_DIR/menu/changedomain.sh ;;
    7) bash $SCRIPT_DIR/menu/update.sh ;;
    8) bash $SCRIPT_DIR/menu/uninstall.sh ;;
    9) bash $SCRIPT_DIR/menu/services.sh ;;
    10) bash $SCRIPT_DIR/menu/sysinfo.sh ;;
    0) clear; exit 0 ;;
    *) echo -e "  ${RED}[!] Pilihan tidak valid!${NC}"; sleep 1; main_menu ;;
  esac
}

main_menu
