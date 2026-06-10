#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - MAIN MENU
#   Run: vpn
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh" 2>/dev/null || source "$(dirname "$0")/lib.sh"

# ─── Header / VPS Info ─────────────────────────────────────
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

  local xray_st=$(service_status xray)
  local nginx_st=$(service_status nginx)
  local dropbear_st=$(service_status dropbear)

  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${WHITE}              ⚡ CHANELOG VPN TUNNEL MANAGER ⚡               ${CYAN}║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Domain   ${NC}: ${WHITE}$domain${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ IP VPS   ${NC}: ${WHITE}$ip${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ OS       ${NC}: ${WHITE}$os${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Kernel   ${NC}: ${WHITE}$kernel${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ CPU Core ${NC}: ${WHITE}$cpu_cores Core${NC}  │  ${YELLOW}Load Avg${NC}: ${WHITE}$load${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Memory   ${NC}: ${WHITE}$mem${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Disk     ${NC}: ${WHITE}$disk${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Uptime   ${NC}: ${WHITE}$uptime${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Network  ${NC}: ${WHITE}$net${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"

  # Service status row
  printf "${CYAN}║${NC}  %-15s %-20s %-15s %-12s ${CYAN}║${NC}\n" \
    "Xray: $xray_st" "Nginx: $nginx_st" "Dropbear: $dropbear_st" ""
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"

  # Protocol status
  local vmess_tls="--"
  local vmess_ntls="--"
  local vless_tls="--"
  local vless_ntls="--"

  if systemctl is-active --quiet xray 2>/dev/null; then
    vmess_tls="${GREEN}ON${NC}"
    vmess_ntls="${GREEN}ON${NC}"
    vless_tls="${GREEN}ON${NC}"
    vless_ntls="${GREEN}ON${NC}"
  else
    vmess_tls="${RED}OFF${NC}"; vmess_ntls="${RED}OFF${NC}"
    vless_tls="${RED}OFF${NC}"; vless_ntls="${RED}OFF${NC}"
  fi

  local vmess_count=$(count_vmess)
  local vless_count=$(count_vless)

  echo -e "${CYAN}║${NC}  ${PURPLE}VMess WS TLS ${NC}(443) : $vmess_tls    ${PURPLE}VMess WS nTLS ${NC}(80): $vmess_ntls"
  echo -e "${CYAN}║${NC}  ${PURPLE}VLess WS TLS ${NC}(443) : $vless_tls    ${PURPLE}VLess WS nTLS ${NC}(80): $vless_ntls"
  echo -e "${CYAN}║${NC}  ${YELLOW}Akun VMess${NC}: ${WHITE}$vmess_count${NC}   │   ${YELLOW}Akun VLess${NC}: ${WHITE}$vless_count${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
}

# ─── Underline Helper ──────────────────────────────────────
uline() {
  local text="$1"
  local len=${#text}
  echo -e "${WHITE}${BOLD}$text${NC}"
  printf "${CYAN}"; printf '─%.0s' $(seq 1 $len); echo -e "${NC}"
}

# ─── Draw Menu Box ─────────────────────────────────────────
draw_menu() {
  local title="$1"
  shift
  local items=("$@")

  echo ""
  echo -e "${CYAN}┌─────────────────────────────────────────────────┐${NC}"
  echo -e "${CYAN}│${WHITE}  $title$(printf '%*s' $((47 - ${#title})) '')${CYAN}│${NC}"
  echo -e "${CYAN}├─────────────────────────────────────────────────┤${NC}"
  for item in "${items[@]}"; do
    echo -e "${CYAN}│${NC}  $item$(printf '%*s' $((46 - ${#item} + 10)) '')${CYAN}│${NC}"
  done
  echo -e "${CYAN}└─────────────────────────────────────────────────┘${NC}"
}

# ─── Main Menu ─────────────────────────────────────────────
main_menu() {
  show_header
  echo ""
  echo -e "  ${CYAN}╔═══════════════════════════════════════════╗${NC}"
  echo -e "  ${CYAN}║${WHITE}            ◈  MAIN MENU  ◈              ${CYAN}║${NC}"
  echo -e "  ${CYAN}╠═══════════════════════════════════════════╣${NC}"
  echo -e "  ${CYAN}║${NC}  ${YELLOW}[1]${NC} ${WHITE}VMess WebSocket${NC}                       ${CYAN}║${NC}"
  echo -e "  ${CYAN}║${NC}      ${DIM}▸ WS TLS & non-TLS Management${NC}        ${CYAN}║${NC}"
  echo -e "  ${CYAN}╠═══════════════════════════════════════════╣${NC}"
  echo -e "  ${CYAN}║${NC}  ${YELLOW}[2]${NC} ${WHITE}VLess WebSocket${NC}                       ${CYAN}║${NC}"
  echo -e "  ${CYAN}║${NC}      ${DIM}▸ WS TLS & non-TLS Management${NC}        ${CYAN}║${NC}"
  echo -e "  ${CYAN}╠═══════════════════════════════════════════╣${NC}"
  echo -e "  ${CYAN}║${NC}  ${YELLOW}[3]${NC} ${WHITE}Nginx Management${NC}                      ${CYAN}║${NC}"
  echo -e "  ${CYAN}╠═══════════════════════════════════════════╣${NC}"
  echo -e "  ${CYAN}║${NC}  ${YELLOW}[4]${NC} ${WHITE}Dropbear SSH Management${NC}               ${CYAN}║${NC}"
  echo -e "  ${CYAN}╠═══════════════════════════════════════════╣${NC}"
  echo -e "  ${CYAN}║${NC}  ${YELLOW}[5]${NC} ${WHITE}System Information${NC}                    ${CYAN}║${NC}"
  echo -e "  ${CYAN}╠═══════════════════════════════════════════╣${NC}"
  echo -e "  ${CYAN}║${NC}  ${YELLOW}[6]${NC} ${WHITE}Change Domain${NC}                         ${CYAN}║${NC}"
  echo -e "  ${CYAN}╠═══════════════════════════════════════════╣${NC}"
  echo -e "  ${CYAN}║${NC}  ${RED}[7]${NC} ${WHITE}Uninstall Script${NC}                      ${CYAN}║${NC}"
  echo -e "  ${CYAN}╠═══════════════════════════════════════════╣${NC}"
  echo -e "  ${CYAN}║${NC}  ${DIM}[0]${NC} ${WHITE}Exit${NC}                                  ${CYAN}║${NC}"
  echo -e "  ${CYAN}╚═══════════════════════════════════════════╝${NC}"
  echo ""
  echo -ne "  ${WHITE}Pilih menu${NC} ${CYAN}[0-7]${NC}: "
  read -r choice

  case "$choice" in
    1) bash $SCRIPT_DIR/menu/vmess.sh ;;
    2) bash $SCRIPT_DIR/menu/vless.sh ;;
    3) bash $SCRIPT_DIR/menu/nginx.sh ;;
    4) bash $SCRIPT_DIR/menu/dropbear.sh ;;
    5) bash $SCRIPT_DIR/menu/sysinfo.sh ;;
    6) bash $SCRIPT_DIR/menu/changedomain.sh ;;
    7) bash $SCRIPT_DIR/menu/uninstall.sh ;;
    0) clear; exit 0 ;;
    *) echo -e "${RED}[!]${NC} Pilihan tidak valid!"; sleep 1; main_menu ;;
  esac
}

main_menu
