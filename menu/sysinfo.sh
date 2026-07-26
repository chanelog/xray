#!/bin/bash
SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

sysinfo_menu() {
  clear
  local domain=$(get_domain)
  local ip=$(get_server_ip)
  local os=$(get_os_info)
  local kernel=$(get_kernel)
  local cpu_info=$(get_cpu_info)
  local cpu_cores=$(get_cpu_cores)
  local cpu_usage=$(get_cpu_usage)
  local mem=$(get_mem_usage)
  local disk=$(get_disk_usage)
  local uptime=$(get_uptime)
  local load=$(get_load_avg)
  local net=$(get_network_usage)
  local vmess_count=$(count_vmess)
  local vless_count=$(count_vless)

  local xray_st nginx_st db_st
  systemctl is-active --quiet xray     && xray_st="${GREEN}● RUNNING${NC}"  || xray_st="${RED}● STOPPED${NC}"
  systemctl is-active --quiet nginx    && nginx_st="${GREEN}● RUNNING${NC}" || nginx_st="${RED}● STOPPED${NC}"
  systemctl is-active --quiet dropbear && db_st="${GREEN}● RUNNING${NC}"    || db_st="${RED}● STOPPED${NC}"

  local ssl_exp="N/A"
  [[ -f /etc/ssl/xray/xray.crt ]] && \
    ssl_exp=$(openssl x509 -enddate -noout -in /etc/ssl/xray/xray.crt 2>/dev/null \
      | sed 's/notAfter=//')

  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}            ⚡  INFORMASI SISTEM VPS  ⚡${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -e "  ${PURPLE}SERVER${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}OS         ${NC}: ${WHITE}$os${NC}"
  echo -e "  ${YELLOW}Kernel     ${NC}: ${WHITE}$kernel${NC}"
  echo -e "  ${YELLOW}IP Server  ${NC}: ${WHITE}$ip${NC}"
  echo -e "  ${YELLOW}Domain     ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Uptime     ${NC}: ${WHITE}$uptime${NC}"
  echo ""
  echo -e "  ${PURPLE}CPU & MEMORY${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}CPU Model  ${NC}: ${WHITE}$cpu_info${NC}"
  echo -e "  ${YELLOW}CPU Cores  ${NC}: ${WHITE}$cpu_cores Core${NC}"
  echo -e "  ${YELLOW}CPU Usage  ${NC}: ${WHITE}$cpu_usage %${NC}"
  echo -e "  ${YELLOW}Load Avg   ${NC}: ${WHITE}$load${NC}"
  echo -e "  ${YELLOW}Memory     ${NC}: ${WHITE}$mem${NC}"
  echo -e "  ${YELLOW}Disk       ${NC}: ${WHITE}$disk${NC}"
  echo ""
  echo -e "  ${PURPLE}NETWORK${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Traffic    ${NC}: ${WHITE}$net${NC}"
  echo ""
  echo -e "  ${PURPLE}SERVICES${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Xray       ${NC}: $xray_st"
  echo -e "  ${YELLOW}Nginx      ${NC}: $nginx_st"
  echo -e "  ${YELLOW}Dropbear   ${NC}: $db_st"
  echo ""
  echo -e "  ${PURPLE}SSL CERTIFICATE${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Domain     ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Expired    ${NC}: ${WHITE}$ssl_exp${NC}"
  echo -e "  ${YELLOW}Cert       ${NC}: ${WHITE}/etc/ssl/xray/xray.crt${NC}"
  echo ""
  echo -e "  ${PURPLE}TUNNEL ACCOUNTS${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}VMess WS   ${NC}: ${WHITE}$vmess_count akun${NC}"
  echo -e "  ${YELLOW}VLess WS   ${NC}: ${WHITE}$vless_count akun${NC}"
  echo ""
  echo -e "  ${PURPLE}PORTS${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}HTTP/nTLS  ${NC}: ${WHITE}80${NC}"
  echo -e "  ${YELLOW}HTTPS/TLS  ${NC}: ${WHITE}443${NC}"
  echo -e "  ${YELLOW}Dropbear   ${NC}: ${WHITE}442, 109, 143${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"
  read -r
  bash $SCRIPT_DIR/menu.sh
}

sysinfo_menu
