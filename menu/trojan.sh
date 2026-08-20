#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - TROJAN MENU
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SLINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

trojan_header() {
  clear
  local domain=$(get_domain)
  local count=$(count_trojan)
  local xray_st
  systemctl is-active --quiet xray \
    && xray_st="${GREEN}● RUNNING${NC}" || xray_st="${RED}● STOPPED${NC}"

  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ⚡  TROJAN WEBSOCKET MENU  ⚡${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Domain       ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Status Xray  ${NC}: $xray_st"
  echo -e "  ${YELLOW}WS TLS       ${NC}: ${WHITE}443${NC}   Path: ${WHITE}/trojan-ws${NC}"
  echo -e "  ${YELLOW}gRPC TLS     ${NC}: ${WHITE}443${NC}   Service: ${WHITE}trojan-grpc${NC}"
  echo -e "  ${YELLOW}Total Akun   ${NC}: ${WHITE}$count akun${NC}"
  echo -e "${CYAN}$LINE${NC}"
}

trojan_menu() {
  trojan_header
  echo ""
  echo -e "  ${WHITE}TROJAN WS & gRPC — TLS${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}[1]${NC}  Buat Akun Trojan"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}[2]${NC}  Info Akun Trojan"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}[3]${NC}  Detail Akun Trojan"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${RED}[4]${NC}  Hapus Akun Trojan"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}[5]${NC}  Perpanjang Akun Trojan"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${CYAN}[6]${NC}  List Semua Akun Trojan"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${DIM}[0]${NC}  Kembali ke Menu Utama"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${WHITE}Pilih [0-6]${NC}: "
  read -r choice

  case "$choice" in
    1) do_create_trojan ;;
    2) do_info_trojan ;;
    3) do_detail_trojan ;;
    4) do_delete_trojan ;;
    5) do_renew_trojan ;;
    6) do_list_trojan ;;
    0) bash $SCRIPT_DIR/menu.sh ;;
    *) echo -e "  ${RED}[!] Pilihan tidak valid${NC}"; sleep 1; trojan_menu ;;
  esac
}

do_create_trojan() {
  trojan_header
  echo ""
  echo -e "  ${WHITE}BUAT AKUN TROJAN BARU${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username     ${NC}: "; read -r username
  [[ -z "$username" ]] && { echo -e "  ${RED}[!] Username kosong!${NC}"; sleep 2; trojan_menu; return; }
  grep -q "^$username|" "$DB_TROJAN" 2>/dev/null && { echo -e "  ${RED}[!] Username sudah ada!${NC}"; sleep 2; trojan_menu; return; }
  echo -ne "  ${YELLOW}Masa aktif (hari)${NC}: "; read -r days; days=${days:-30}
  [[ ! "$days" =~ ^[0-9]+$ ]] && { echo -e "  ${RED}[!] Harus angka!${NC}"; sleep 2; trojan_menu; return; }

  local pass=$(create_trojan "$username" "$days")
  local domain=$(get_domain)
  local exp=$(get_exp_date "$days")
  local link_ws=$(gen_trojan_link "$username" "$pass" "$domain" "ws")
  local link_grpc=$(gen_trojan_link "$username" "$pass" "$domain" "grpc")

  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}           ✓  AKUN TROJAN BERHASIL DIBUAT${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Username   ${NC}: ${WHITE}$username${NC}"
  echo -e "  ${YELLOW}Password   ${NC}: ${WHITE}$pass${NC}"
  echo -e "  ${YELLOW}Domain     ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Dibuat     ${NC}: ${WHITE}$(date +"%Y-%m-%d")${NC}"
  echo -e "  ${YELLOW}Expired    ${NC}: ${WHITE}$exp${NC}"
  echo -e "  ${YELLOW}Masa Aktif ${NC}: ${WHITE}$days hari${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}WS TLS     ${NC}: Host ${WHITE}$domain${NC}  Port ${WHITE}443${NC}  Path ${WHITE}/trojan-ws${NC}  TLS ${GREEN}ON${NC}"
  echo -e "  ${WHITE}gRPC TLS   ${NC}: Host ${WHITE}$domain${NC}  Port ${WHITE}443${NC}  Service ${WHITE}trojan-grpc${NC}  TLS ${GREEN}ON${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link WS:${NC}"
  echo -e "  ${GREEN}$link_ws${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link gRPC:${NC}"
  echo -e "  ${GREEN}$link_grpc${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  trojan_menu
}

do_info_trojan() {
  trojan_header
  echo ""
  echo -e "  ${WHITE}INFO AKUN TROJAN${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username
  local info=$(get_trojan_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; trojan_menu; return; }

  local pass=$(echo "$info" | cut -d'|' -f2)
  local exp=$(echo "$info"  | cut -d'|' -f3)
  local created=$(echo "$info" | cut -d'|' -f4)
  local remaining=$(days_until_exp "$exp")
  local sc="${GREEN}"; local st="AKTIF"
  [[ $remaining -lt 0 ]] && { sc="${RED}";     st="EXPIRED"; }
  [[ $remaining -le 3 && $remaining -ge 0 ]] && { sc="${YELLOW}"; st="SEGERA EXPIRED"; }

  echo ""
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Username  ${NC}: ${WHITE}$username${NC}"
  echo -e "  ${YELLOW}Password  ${NC}: ${WHITE}$pass${NC}"
  echo -e "  ${YELLOW}Dibuat    ${NC}: ${WHITE}$created${NC}"
  echo -e "  ${YELLOW}Expired   ${NC}: ${WHITE}$exp${NC}"
  echo -e "  ${YELLOW}Sisa      ${NC}: ${WHITE}$remaining hari${NC}"
  echo -e "  ${YELLOW}Status    ${NC}: ${sc}● $st${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  trojan_menu
}

do_detail_trojan() {
  trojan_header
  echo ""
  echo -e "  ${WHITE}DETAIL AKUN TROJAN${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username
  local info=$(get_trojan_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; trojan_menu; return; }

  local pass=$(echo "$info" | cut -d'|' -f2)
  local exp=$(echo "$info"  | cut -d'|' -f3)
  local created=$(echo "$info" | cut -d'|' -f4)
  local domain=$(get_domain)
  local remaining=$(days_until_exp "$exp")
  local link_ws=$(gen_trojan_link "$username" "$pass" "$domain" "ws")
  local link_grpc=$(gen_trojan_link "$username" "$pass" "$domain" "grpc")

  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ◈  DETAIL AKUN TROJAN  ◈${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Username   ${NC}: ${WHITE}$username${NC}"
  echo -e "  ${YELLOW}Password   ${NC}: ${WHITE}$pass${NC}"
  echo -e "  ${YELLOW}Dibuat     ${NC}: ${WHITE}$created${NC}"
  echo -e "  ${YELLOW}Expired    ${NC}: ${WHITE}$exp${NC}"
  echo -e "  ${YELLOW}Sisa       ${NC}: ${WHITE}$remaining hari${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}WS TLS     ${NC}: Host ${WHITE}$domain${NC}  Port ${WHITE}443${NC}  Path ${WHITE}/trojan-ws${NC}  TLS ${GREEN}ON${NC}"
  echo -e "  ${WHITE}gRPC TLS   ${NC}: Host ${WHITE}$domain${NC}  Port ${WHITE}443${NC}  Service ${WHITE}trojan-grpc${NC}  TLS ${GREEN}ON${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link WS:${NC}"
  echo -e "  ${GREEN}$link_ws${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link gRPC:${NC}"
  echo -e "  ${GREEN}$link_grpc${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  trojan_menu
}

do_delete_trojan() {
  trojan_header
  echo ""
  echo -e "  ${RED}HAPUS AKUN TROJAN${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  do_list_trojan_simple
  echo ""
  echo -ne "  ${YELLOW}Username yang dihapus${NC}: "; read -r username
  [[ -z "$(get_trojan_info "$username")" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; trojan_menu; return; }
  echo -ne "  ${RED}Konfirmasi hapus '$username'? [y/N]${NC}: "; read -r c
  [[ ! "$c" =~ ^[Yy]$ ]] && { echo -e "  ${YELLOW}Dibatalkan${NC}"; sleep 1; trojan_menu; return; }
  delete_trojan "$username"
  echo -e "  ${GREEN}[✓] Akun '$username' dihapus!${NC}"; sleep 2; trojan_menu
}

do_renew_trojan() {
  trojan_header
  echo ""
  echo -e "  ${YELLOW}PERPANJANG AKUN TROJAN${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  do_list_trojan_simple
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username
  local info=$(get_trojan_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; trojan_menu; return; }
  local old_exp=$(echo "$info" | cut -d'|' -f3)
  echo -e "  ${YELLOW}Expired saat ini${NC}: ${WHITE}$old_exp${NC}"
  echo -ne "  ${YELLOW}Perpanjang (hari)${NC}: "; read -r days; days=${days:-30}
  renew_trojan "$username" "$days"
  echo -e "  ${GREEN}[✓] Diperpanjang hingga ${WHITE}$(get_exp_date "$days")${NC}"; sleep 2; trojan_menu
}

do_list_trojan_simple() {
  local count=0
  printf "  ${CYAN}%-20s %-20s %-12s${NC}\n" "USERNAME" "PASSWORD" "EXPIRED"
  echo -e "  ${CYAN}$LINE${NC}"
  while IFS='|' read -r user pass exp created; do
    [[ -z "$user" ]] && continue
    local r=$(days_until_exp "$exp")
    local c="${WHITE}"
    [[ $r -lt 0 ]] && c="${RED}"
    [[ $r -le 3 && $r -ge 0 ]] && c="${YELLOW}"
    printf "  ${c}%-20s %-20s %-12s${NC}\n" "$user" "$pass" "$exp"
    ((count++))
  done < <(list_trojan)
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Total${NC}: ${WHITE}$count akun${NC}"
}

do_list_trojan() {
  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ◈  DAFTAR AKUN TROJAN  ◈${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  do_list_trojan_simple
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  trojan_menu
}

trojan_menu
