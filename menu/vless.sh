#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - VLESS MENU (ALL-IN-ONE)
#   Supports: WS (TLS + nTLS) + gRPC (TLS)
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SLINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

vless_header() {
  clear
  local domain=$(get_domain)
  local count=$(count_vless)
  local xray_st
  systemctl is-active --quiet xray \
    && xray_st="${GREEN}● RUNNING${NC}" || xray_st="${RED}● STOPPED${NC}"

  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ⚡  VLESS WEBSOCKET MENU  ⚡${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Domain       ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Status Xray  ${NC}: $xray_st"
  echo -e "  ${YELLOW}WS TLS       ${NC}: ${WHITE}443${NC}   Path: ${WHITE}/vless-ws${NC}"
  echo -e "  ${YELLOW}WS nTLS      ${NC}: ${WHITE}80${NC}    Path: ${WHITE}/vless-ntls${NC}"
  echo -e "  ${YELLOW}gRPC TLS     ${NC}: ${WHITE}443${NC}   Service: ${WHITE}vless-grpc${NC}"
  echo -e "  ${YELLOW}Total Akun   ${NC}: ${WHITE}$count akun${NC}"
  echo -e "${CYAN}$LINE${NC}"
}

vless_menu() {
  vless_header
  echo ""
  echo -e "  ${WHITE}VLESS WS & gRPC — TLS & non-TLS${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}[1]${NC}  Buat Akun VLess"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}[2]${NC}  Info Akun VLess"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}[3]${NC}  Detail Akun VLess"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${RED}[4]${NC}  Hapus Akun VLess"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}[5]${NC}  Perpanjang Akun VLess"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${CYAN}[6]${NC}  List Semua Akun VLess"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${DIM}[0]${NC}  Kembali ke Menu Utama"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${WHITE}Pilih [0-6]${NC}: "
  read -r choice

  case "$choice" in
    1) do_create_vless ;;
    2) do_info_vless ;;
    3) do_detail_vless ;;
    4) do_delete_vless ;;
    5) do_renew_vless ;;
    6) do_list_vless ;;
    0) bash $SCRIPT_DIR/menu.sh ;;
    *) echo -e "  ${RED}[!] Pilihan tidak valid${NC}"; sleep 1; vless_menu ;;
  esac
}

do_create_vless() {
  vless_header
  echo ""
  echo -e "  ${WHITE}BUAT AKUN VLESS BARU${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username     ${NC}: "; read -r username
  [[ -z "$username" ]] && { echo -e "  ${RED}[!] Username kosong!${NC}"; sleep 2; vless_menu; return; }
  grep -q "^$username|" "$DB_VLESS" 2>/dev/null && { echo -e "  ${RED}[!] Username sudah ada!${NC}"; sleep 2; vless_menu; return; }
  echo -ne "  ${YELLOW}Masa aktif (hari)${NC}: "; read -r days; days=${days:-30}
  [[ ! "$days" =~ ^[0-9]+$ ]] && { echo -e "  ${RED}[!] Harus angka!${NC}"; sleep 2; vless_menu; return; }

  local uuid=$(create_vless "$username" "$days")
  local domain=$(get_domain)
  local exp=$(get_exp_date "$days")
  local link_tls=$(gen_vless_link "$username" "$uuid" "$domain" "tls")
  local link_ntls=$(gen_vless_link "$username" "$uuid" "$domain" "ntls")
  local link_grpc=$(gen_vless_grpc_link "$username" "$uuid" "$domain")

  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}           ✓  AKUN VLESS BERHASIL DIBUAT${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Username   ${NC}: ${WHITE}$username${NC}"
  echo -e "  ${YELLOW}UUID       ${NC}: ${WHITE}$uuid${NC}"
  echo -e "  ${YELLOW}Domain     ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Dibuat     ${NC}: ${WHITE}$(date +"%Y-%m-%d")${NC}"
  echo -e "  ${YELLOW}Expired    ${NC}: ${WHITE}$exp${NC}"
  echo -e "  ${YELLOW}Masa Aktif ${NC}: ${WHITE}$days hari${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}WS TLS     ${NC}: Host ${WHITE}$domain${NC}  Port ${WHITE}443${NC}  Path ${WHITE}/vless-ws${NC}  TLS ${GREEN}ON${NC}"
  echo -e "  ${WHITE}WS nTLS    ${NC}: Host ${WHITE}$domain${NC}  Port ${WHITE}80${NC}   Path ${WHITE}/vless-ntls${NC}  TLS ${RED}OFF${NC}"
  echo -e "  ${WHITE}gRPC TLS   ${NC}: Host ${WHITE}$domain${NC}  Port ${WHITE}443${NC}  Service ${WHITE}vless-grpc${NC}  TLS ${GREEN}ON${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link WS TLS:${NC}"
  echo -e "  ${GREEN}$link_tls${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link WS nTLS:${NC}"
  echo -e "  ${YELLOW}$link_ntls${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link gRPC TLS:${NC}"
  echo -e "  ${GREEN}$link_grpc${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  vless_menu
}

do_info_vless() {
  vless_header
  echo ""
  echo -e "  ${WHITE}INFO AKUN VLESS${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username
  local info=$(get_vless_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; vless_menu; return; }

  local uuid=$(echo "$info" | cut -d'|' -f2)
  local exp=$(echo "$info"  | cut -d'|' -f3)
  local created=$(echo "$info" | cut -d'|' -f4)
  local remaining=$(days_until_exp "$exp")
  local sc="${GREEN}"; local st="AKTIF"
  [[ $remaining -lt 0 ]] && { sc="${RED}";     st="EXPIRED"; }
  [[ $remaining -le 3 && $remaining -ge 0 ]] && { sc="${YELLOW}"; st="SEGERA EXPIRED"; }

  echo ""
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Username  ${NC}: ${WHITE}$username${NC}"
  echo -e "  ${YELLOW}UUID      ${NC}: ${WHITE}$uuid${NC}"
  echo -e "  ${YELLOW}Dibuat    ${NC}: ${WHITE}$created${NC}"
  echo -e "  ${YELLOW}Expired   ${NC}: ${WHITE}$exp${NC}"
  echo -e "  ${YELLOW}Sisa      ${NC}: ${WHITE}$remaining hari${NC}"
  echo -e "  ${YELLOW}Status    ${NC}: ${sc}● $st${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  vless_menu
}

do_detail_vless() {
  vless_header
  echo ""
  echo -e "  ${WHITE}DETAIL AKUN VLESS${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username
  local info=$(get_vless_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; vless_menu; return; }

  local uuid=$(echo "$info" | cut -d'|' -f2)
  local exp=$(echo "$info"  | cut -d'|' -f3)
  local created=$(echo "$info" | cut -d'|' -f4)
  local domain=$(get_domain)
  local remaining=$(days_until_exp "$exp")
  local link_tls=$(gen_vless_link "$username" "$uuid" "$domain" "tls")
  local link_ntls=$(gen_vless_link "$username" "$uuid" "$domain" "ntls")
  local link_grpc=$(gen_vless_grpc_link "$username" "$uuid" "$domain")

  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ◈  DETAIL AKUN VLESS  ◈${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Username   ${NC}: ${WHITE}$username${NC}"
  echo -e "  ${YELLOW}UUID       ${NC}: ${WHITE}$uuid${NC}"
  echo -e "  ${YELLOW}Encryption ${NC}: ${WHITE}none${NC}"
  echo -e "  ${YELLOW}Network    ${NC}: ${WHITE}WebSocket / gRPC${NC}"
  echo -e "  ${YELLOW}Dibuat     ${NC}: ${WHITE}$created${NC}"
  echo -e "  ${YELLOW}Expired    ${NC}: ${WHITE}$exp${NC}"
  echo -e "  ${YELLOW}Sisa       ${NC}: ${WHITE}$remaining hari${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}WS TLS     ${NC}: Host ${WHITE}$domain${NC}  Port ${WHITE}443${NC}  Path ${WHITE}/vless-ws${NC}  TLS ${GREEN}ON${NC}"
  echo -e "  ${WHITE}WS nTLS    ${NC}: Host ${WHITE}$domain${NC}  Port ${WHITE}80${NC}   Path ${WHITE}/vless-ntls${NC}  TLS ${RED}OFF${NC}"
  echo -e "  ${WHITE}gRPC TLS   ${NC}: Host ${WHITE}$domain${NC}  Port ${WHITE}443${NC}  Service ${WHITE}vless-grpc${NC}  TLS ${GREEN}ON${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link WS TLS:${NC}"
  echo -e "  ${GREEN}$link_tls${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link WS nTLS:${NC}"
  echo -e "  ${YELLOW}$link_ntls${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link gRPC TLS:${NC}"
  echo -e "  ${GREEN}$link_grpc${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  vless_menu
}

do_delete_vless() {
  vless_header
  echo ""
  echo -e "  ${RED}HAPUS AKUN VLESS${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  do_list_vless_simple
  echo ""
  echo -ne "  ${YELLOW}Username yang dihapus${NC}: "; read -r username
  [[ -z "$(get_vless_info "$username")" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; vless_menu; return; }
  echo -ne "  ${RED}Konfirmasi hapus '$username'? [y/N]${NC}: "; read -r c
  [[ ! "$c" =~ ^[Yy]$ ]] && { echo -e "  ${YELLOW}Dibatalkan${NC}"; sleep 1; vless_menu; return; }
  delete_vless "$username"
  echo -e "  ${GREEN}[✓] Akun '$username' dihapus!${NC}"; sleep 2; vless_menu
}

do_renew_vless() {
  vless_header
  echo ""
  echo -e "  ${YELLOW}PERPANJANG AKUN VLESS${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  do_list_vless_simple
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username
  local info=$(get_vless_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; vless_menu; return; }
  local old_exp=$(echo "$info" | cut -d'|' -f3)
  echo -e "  ${YELLOW}Expired saat ini${NC}: ${WHITE}$old_exp${NC}"
  echo -ne "  ${YELLOW}Perpanjang (hari)${NC}: "; read -r days; days=${days:-30}
  renew_vless "$username" "$days"
  echo -e "  ${GREEN}[✓] Diperpanjang hingga ${WHITE}$(get_exp_date "$days")${NC}"; sleep 2; vless_menu
}

do_list_vless_simple() {
  local count=0
  printf "  ${CYAN}%-20s %-36s %-12s${NC}\n" "USERNAME" "UUID" "EXPIRED"
  echo -e "  ${CYAN}$LINE${NC}"
  while IFS='|' read -r user uuid exp created; do
    local r=$(days_until_exp "$exp")
    local c="${WHITE}"
    [[ $r -lt 0 ]] && c="${RED}"
    [[ $r -le 3 && $r -ge 0 ]] && c="${YELLOW}"
    printf "  ${c}%-20s %-36s %-12s${NC}\n" "$user" "$uuid" "$exp"
    ((count++))
  done < <(list_vless)
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Total${NC}: ${WHITE}$count akun${NC}"
}

do_list_vless() {
  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ◈  DAFTAR AKUN VLESS  ◈${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  do_list_vless_simple
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  vless_menu
}

vless_menu
