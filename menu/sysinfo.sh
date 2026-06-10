#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - SYSTEM INFO
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

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

  local xray_st=$(service_status xray)
  local nginx_st=$(service_status nginx)
  local db_st=$(service_status dropbear)

  # SSL info
  local ssl_exp="N/A"
  if [[ -f /etc/ssl/xray/xray.crt ]]; then
    ssl_exp=$(openssl x509 -enddate -noout -in /etc/ssl/xray/xray.crt 2>/dev/null | cut -d= -f2)
  fi

  local vmess_count=$(count_vmess)
  local vless_count=$(count_vless)

  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${WHITE}               ◈  INFORMASI SISTEM VPS  ◈                    ${CYAN}║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${PURPLE}[ SERVER INFORMATION ]${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}OS         ${NC}: ${WHITE}$os${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Kernel     ${NC}: ${WHITE}$kernel${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}IP Server  ${NC}: ${WHITE}$ip${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Domain     ${NC}: ${WHITE}$domain${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Uptime     ${NC}: ${WHITE}$uptime${NC}"
  echo -e "${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${PURPLE}[ CPU & MEMORY ]${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}CPU Model  ${NC}: ${WHITE}$cpu_info${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}CPU Cores  ${NC}: ${WHITE}$cpu_cores Core${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}CPU Usage  ${NC}: ${WHITE}$cpu_usage %${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Load Avg   ${NC}: ${WHITE}$load${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Memory     ${NC}: ${WHITE}$mem${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Disk       ${NC}: ${WHITE}$disk${NC}"
  echo -e "${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${PURPLE}[ NETWORK ]${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Traffic    ${NC}: ${WHITE}$net${NC}"
  echo -e "${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${PURPLE}[ SERVICES ]${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Xray       ${NC}: $xray_st"
  echo -e "${CYAN}║${NC}  ${YELLOW}Nginx      ${NC}: $nginx_st"
  echo -e "${CYAN}║${NC}  ${YELLOW}Dropbear   ${NC}: $db_st"
  echo -e "${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${PURPLE}[ SSL CERTIFICATE ]${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Domain     ${NC}: ${WHITE}$domain${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Expires    ${NC}: ${WHITE}$ssl_exp${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Cert File  ${NC}: ${WHITE}/etc/ssl/xray/xray.crt${NC}"
  echo -e "${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${PURPLE}[ TUNNEL ACCOUNTS ]${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}VMess WS   ${NC}: ${WHITE}$vmess_count akun${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}VLess WS   ${NC}: ${WHITE}$vless_count akun${NC}"
  echo -e "${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${PURPLE}[ PORTS ]${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}HTTP       ${NC}: ${WHITE}80${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}HTTPS/TLS  ${NC}: ${WHITE}443${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}nTLS WS    ${NC}: ${WHITE}80${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Dropbear   ${NC}: ${WHITE}442, 109, 143${NC}"
  echo -e "${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali ke menu utama...${NC}"
  read -r
  bash $SCRIPT_DIR/menu.sh
}

sysinfo_menu
