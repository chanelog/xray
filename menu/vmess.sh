#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - VMESS MENU
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SLINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

vmess_header() {
  clear
  local domain=$(get_domain)
  local count=$(count_vmess)
  local xray_st
  systemctl is-active --quiet xray \
    && xray_st="${GREEN}● RUNNING${NC}" || xray_st="${RED}● STOPPED${NC}"

  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ⚡  VMESS WEBSOCKET MENU  ⚡${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Domain       ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Status Xray  ${NC}: $xray_st"
  echo -e "  ${YELLOW}Port TLS     ${NC}: ${WHITE}443${NC}   Path: ${WHITE}/vmess-ws${NC}"
  echo -e "  ${YELLOW}Port nTLS    ${NC}: ${WHITE}80${NC}    Path: ${WHITE}/vmess-ntls${NC}"
  echo -e "  ${YELLOW}Total Akun   ${NC}: ${WHITE}$count akun${NC}"
  echo -e "${CYAN}$LINE${NC}"
}

vmess_menu() {
  vmess_header
  echo ""
  echo -e "  ${WHITE}VMESS WS — TLS & non-TLS${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}[1]${NC}  Buat Akun VMess"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}[2]${NC}  Info Akun VMess"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}[3]${NC}  Detail Akun VMess"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${RED}[4]${NC}  Hapus Akun VMess"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}[5]${NC}  Perpanjang Akun VMess"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}[6]${NC}  Renew Akun VMess"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${CYAN}[7]${NC}  List Semua Akun VMess"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${DIM}[0]${NC}  Kembali ke Menu Utama"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${WHITE}Pilih [0-7]${NC}: "
  read -r choice

  case "$choice" in
    1) do_create_vmess ;;
    2) do_info_vmess ;;
    3) do_detail_vmess ;;
    4) do_delete_vmess ;;
    5) do_renew_vmess ;;
    6) do_renew_vmess ;;
    7) do_list_vmess ;;
    0) bash $SCRIPT_DIR/menu.sh ;;
    *) echo -e "  ${RED}[!] Pilihan tidak valid${NC}"; sleep 1; vmess_menu ;;
  esac
}

do_create_vmess() {
  vmess_header
  echo ""
  echo -e "  ${WHITE}BUAT AKUN VMESS BARU${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username     ${NC}: "
  read -r username
  [[ -z "$username" ]] && { echo -e "  ${RED}[!] Username kosong!${NC}"; sleep 2; vmess_menu; return; }
  grep -q "^$username|" "$DB_VMESS" 2>/dev/null && { echo -e "  ${RED}[!] Username sudah ada!${NC}"; sleep 2; vmess_menu; return; }

  echo -ne "  ${YELLOW}Masa aktif (hari)${NC}: "
  read -r days; days=${days:-30}
  [[ ! "$days" =~ ^[0-9]+$ ]] && { echo -e "  ${RED}[!] Harus angka!${NC}"; sleep 2; vmess_menu; return; }

  local uuid=$(create_vmess "$username" "$days")
  local domain=$(get_domain)
  local exp=$(get_exp_date "$days")
  local link_tls=$(gen_vmess_link "$username" "$uuid" "$domain" "tls")
  local link_ntls=$(gen_vmess_link "$username" "$uuid" "$domain" "ntls")

  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}           ✓  AKUN VMESS BERHASIL DIBUAT${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Username   ${NC}: ${WHITE}$username${NC}"
  echo -e "  ${YELLOW}UUID       ${NC}: ${WHITE}$uuid${NC}"
  echo -e "  ${YELLOW}Domain     ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Dibuat     ${NC}: ${WHITE}$(date +"%Y-%m-%d")${NC}"
  echo -e "  ${YELLOW}Expired    ${NC}: ${WHITE}$exp${NC}"
  echo -e "  ${YELLOW}Masa Aktif ${NC}: ${WHITE}$days hari${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}WS TLS — Host: $domain  Port: 443  Path: /vmess-ws${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}WS nTLS — Host: $domain  Port: 80  Path: /vmess-ntls${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link TLS:${NC}"
  echo -e "  ${GREEN}$link_tls${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link nTLS:${NC}"
  echo -e "  ${YELLOW}$link_ntls${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  vmess_menu
}

do_info_vmess() {
  vmess_header
  echo ""
  echo -e "  ${WHITE}INFO AKUN VMESS${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username

  local info=$(get_vmess_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; vmess_menu; return; }

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
  vmess_menu
}

do_detail_vmess() {
  vmess_header
  echo ""
  echo -e "  ${WHITE}DETAIL AKUN VMESS${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username

  local info=$(get_vmess_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; vmess_menu; return; }

  local uuid=$(echo "$info" | cut -d'|' -f2)
  local exp=$(echo "$info"  | cut -d'|' -f3)
  local created=$(echo "$info" | cut -d'|' -f4)
  local domain=$(get_domain)
  local remaining=$(days_until_exp "$exp")
  local link_tls=$(gen_vmess_link "$username" "$uuid" "$domain" "tls")
  local link_ntls=$(gen_vmess_link "$username" "$uuid" "$domain" "ntls")

  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ◈  DETAIL AKUN VMESS  ◈${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Username   ${NC}: ${WHITE}$username${NC}"
  echo -e "  ${YELLOW}UUID       ${NC}: ${WHITE}$uuid${NC}"
  echo -e "  ${YELLOW}AlterID    ${NC}: ${WHITE}0${NC}"
  echo -e "  ${YELLOW}Network    ${NC}: ${WHITE}WebSocket${NC}"
  echo -e "  ${YELLOW}Dibuat     ${NC}: ${WHITE}$created${NC}"
  echo -e "  ${YELLOW}Expired    ${NC}: ${WHITE}$exp${NC}"
  echo -e "  ${YELLOW}Sisa       ${NC}: ${WHITE}$remaining hari${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}WS TLS     ${NC}: Host ${WHITE}$domain${NC}  Port ${WHITE}443${NC}  Path ${WHITE}/vmess-ws${NC}  TLS ${GREEN}ON${NC}"
  echo -e "  ${WHITE}WS nTLS    ${NC}: Host ${WHITE}$domain${NC}  Port ${WHITE}80${NC}   Path ${WHITE}/vmess-ntls${NC}  TLS ${RED}OFF${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link TLS:${NC}"
  echo -e "  ${GREEN}$link_tls${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}Link nTLS:${NC}"
  echo -e "  ${YELLOW}$link_ntls${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  vmess_menu
}

do_delete_vmess() {
  vmess_header
  echo ""
  echo -e "  ${RED}HAPUS AKUN VMESS${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  do_list_vmess_simple
  echo ""
  echo -ne "  ${YELLOW}Username yang dihapus${NC}: "; read -r username
  [[ -z "$(get_vmess_info "$username")" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; vmess_menu; return; }
  echo -ne "  ${RED}Konfirmasi hapus '$username'? [y/N]${NC}: "; read -r c
  [[ ! "$c" =~ ^[Yy]$ ]] && { echo -e "  ${YELLOW}Dibatalkan${NC}"; sleep 1; vmess_menu; return; }
  delete_vmess "$username"
  echo -e "  ${GREEN}[✓] Akun '$username' dihapus!${NC}"; sleep 2; vmess_menu
}

do_renew_vmess() {
  vmess_header
  echo ""
  echo -e "  ${YELLOW}PERPANJANG AKUN VMESS${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  do_list_vmess_simple
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username
  local info=$(get_vmess_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; vmess_menu; return; }
  local old_exp=$(echo "$info" | cut -d'|' -f3)
  echo -e "  ${YELLOW}Expired saat ini${NC}: ${WHITE}$old_exp${NC}"
  echo -ne "  ${YELLOW}Perpanjang (hari)${NC}: "; read -r days; days=${days:-30}
  renew_vmess "$username" "$days"
  echo -e "  ${GREEN}[✓] Diperpanjang hingga ${WHITE}$(get_exp_date "$days")${NC}"; sleep 2; vmess_menu
}

do_list_vmess_simple() {
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
  done < <(list_vmess)
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Total${NC}: ${WHITE}$count akun${NC}"
}

do_list_vmess() {
  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ◈  DAFTAR AKUN VMESS  ◈${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  do_list_vmess_simple
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  vmess_menu
}

vmess_menu
