#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - SSH / SSH-WS / SSH-SSL MENU (ADDON)
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SLINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

sshws_addon_missing() {
  [[ ! -f /usr/local/bin/ws-proxy.py ]] || ! is_service_installed stunnel4
}

sshws_offer_install() {
  clear
  echo -e "${YELLOW}$LINE${NC}"
  echo -e "${WHITE}   FITUR SSH-WS / SSH-SSL BELUM DIINSTALL${NC}"
  echo -e "${YELLOW}$LINE${NC}"
  echo ""
  echo -e "  Fitur ini butuh komponen tambahan (stunnel4 + ws-proxy)."
  echo -e "  Instalasi bersifat aditif dan TIDAK mengubah/menghentikan"
  echo -e "  layanan VMess/VLess/Nginx/Dropbear yang sudah berjalan."
  echo ""
  echo -ne "  ${WHITE}Install sekarang? [Y/n]${NC}: "
  read -r c
  if [[ "$c" =~ ^[Nn]$ ]]; then
    bash "$SCRIPT_DIR/menu.sh"; return 1
  fi
  bash "$SCRIPT_DIR/addon/install-sshws.sh"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk lanjut...${NC}"; read -r
  return 0
}

sshws_header() {
  clear
  local domain=$(get_domain)
  local count=$(count_ssh)
  local db_st stunnel_st wsp_st
  systemctl is-active --quiet dropbear  && db_st="${GREEN}● RUNNING${NC}"  || db_st="${RED}● STOPPED${NC}"
  systemctl is-active --quiet stunnel4  && stunnel_st="${GREEN}● RUNNING${NC}" || stunnel_st="${RED}● STOPPED${NC}"
  systemctl is-active --quiet ws-proxy  && wsp_st="${GREEN}● RUNNING${NC}"  || wsp_st="${RED}● STOPPED${NC}"

  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}      ⚡  SSH / SSH-WS / SSH-SSL MANAGEMENT  ⚡${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Domain          ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Dropbear        ${NC}: $db_st"
  echo -e "  ${YELLOW}Stunnel4 (SSL)  ${NC}: $stunnel_st"
  echo -e "  ${YELLOW}WS Proxy        ${NC}: $wsp_st"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${PURPLE}SSH Direct    ${NC}: port ${WHITE}442, 109, 143${NC}"
  echo -e "  ${PURPLE}SSH-SSL       ${NC}: port ${WHITE}$STUNNEL_SSL_PORT${NC} (stunnel4 → dropbear)"
  echo -e "  ${PURPLE}SSH-WS nTLS   ${NC}: port ${WHITE}80${NC}  path ${WHITE}/ssh-ws${NC}"
  echo -e "  ${PURPLE}SSH-WS TLS    ${NC}: port ${WHITE}443${NC} path ${WHITE}/ssh-ws${NC}"
  echo -e "  ${YELLOW}Total Akun    ${NC}: ${WHITE}$count akun${NC}"
  echo -e "${CYAN}$LINE${NC}"
}

sshws_menu() {
  if sshws_addon_missing; then
    sshws_offer_install || return
  fi
  sshws_header
  echo ""
  echo -e "  ${WHITE}SSH / SSH-WS / SSH-SSL${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}[1]${NC}  Buat Akun SSH"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}[2]${NC}  Info Akun SSH"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}[3]${NC}  Detail Koneksi (SSH/SSL/WS/WS-TLS)"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${RED}[4]${NC}  Hapus Akun SSH"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}[5]${NC}  Perpanjang Akun SSH"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${CYAN}[6]${NC}  List Semua Akun SSH"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${DIM}[0]${NC}  Kembali ke Menu Utama"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${WHITE}Pilih [0-6]${NC}: "
  read -r choice

  case "$choice" in
    1) do_create_ssh ;;
    2) do_info_ssh ;;
    3) do_detail_ssh ;;
    4) do_delete_ssh ;;
    5) do_renew_ssh ;;
    6) do_list_ssh ;;
    0) bash "$SCRIPT_DIR/menu.sh" ;;
    *) echo -e "  ${RED}[!] Pilihan tidak valid${NC}"; sleep 1; sshws_menu ;;
  esac
}

do_create_ssh() {
  sshws_header
  echo ""
  echo -e "  ${WHITE}BUAT AKUN SSH BARU${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username     ${NC}: "
  read -r username
  [[ -z "$username" ]] && { echo -e "  ${RED}[!] Username kosong!${NC}"; sleep 2; sshws_menu; return; }
  grep -q "^$username|" "$DB_SSH" 2>/dev/null && { echo -e "  ${RED}[!] Username sudah ada!${NC}"; sleep 2; sshws_menu; return; }

  echo -ne "  ${YELLOW}Password (kosongkan = random)${NC}: "
  read -r password

  echo -ne "  ${YELLOW}Masa aktif (hari)${NC}: "
  read -r days; days=${days:-30}
  [[ ! "$days" =~ ^[0-9]+$ ]] && { echo -e "  ${RED}[!] Harus angka!${NC}"; sleep 2; sshws_menu; return; }

  local pass
  pass=$(create_ssh "$username" "$days" "$password")
  local domain=$(get_domain)
  local exp=$(get_exp_date "$days")

  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}           ✓  AKUN SSH BERHASIL DIBUAT${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Username   ${NC}: ${WHITE}$username${NC}"
  echo -e "  ${YELLOW}Password   ${NC}: ${WHITE}$pass${NC}"
  echo -e "  ${YELLOW}Domain/IP  ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Expired    ${NC}: ${WHITE}$exp${NC} (${days} hari)"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}SSH Direct  ${NC}: $domain  port 442 / 109 / 143"
  echo -e "  ${WHITE}SSH-SSL     ${NC}: $domain  port $STUNNEL_SSL_PORT  (stunnel)"
  echo -e "  ${WHITE}SSH-WS nTLS ${NC}: $domain  port 80   path /ssh-ws"
  echo -e "  ${WHITE}SSH-WS TLS  ${NC}: $domain  port 443  path /ssh-ws"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  sshws_menu
}

do_info_ssh() {
  sshws_header
  echo ""
  echo -e "  ${WHITE}INFO AKUN SSH${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username

  local info=$(get_ssh_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; sshws_menu; return; }

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
  sshws_menu
}

do_detail_ssh() {
  sshws_header
  echo ""
  echo -e "  ${WHITE}DETAIL KONEKSI SSH${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username

  local info=$(get_ssh_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; sshws_menu; return; }

  local pass=$(echo "$info" | cut -d'|' -f2)
  local exp=$(echo "$info"  | cut -d'|' -f3)
  local domain=$(get_domain)
  local ip=$(get_server_ip)

  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ◈  DETAIL KONEKSI SSH  ◈${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Username${NC}: ${WHITE}$username${NC}   ${YELLOW}Password${NC}: ${WHITE}$pass${NC}   ${YELLOW}Expired${NC}: ${WHITE}$exp${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${WHITE}[1] SSH Direct${NC}"
  echo -e "      Host: $domain ($ip)   Port: 442 / 109 / 143"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[2] SSH-SSL (Stunnel)${NC}"
  echo -e "      Host: $domain   Port: $STUNNEL_SSL_PORT   TLS: ON"
  echo -e "      Connect: stunnel → 127.0.0.1:$SSH_BACKEND_PORT (SSH client via stunnel config)"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[3] SSH-WS (non-TLS)${NC}"
  echo -e "      Host: $domain   Port: 80   Path: /ssh-ws   TLS: OFF"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[4] SSH-WS (TLS)${NC}"
  echo -e "      Host: $domain   Port: 443   Path: /ssh-ws   TLS: ON"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  sshws_menu
}

do_delete_ssh() {
  sshws_header
  echo ""
  echo -e "  ${RED}HAPUS AKUN SSH${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  do_list_ssh_simple
  echo ""
  echo -ne "  ${YELLOW}Username yang dihapus${NC}: "; read -r username
  [[ -z "$(get_ssh_info "$username")" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; sshws_menu; return; }
  echo -ne "  ${RED}Konfirmasi hapus '$username'? [y/N]${NC}: "; read -r c
  [[ ! "$c" =~ ^[Yy]$ ]] && { echo -e "  ${YELLOW}Dibatalkan${NC}"; sleep 1; sshws_menu; return; }
  delete_ssh "$username"
  echo -e "  ${GREEN}[✓] Akun '$username' dihapus!${NC}"; sleep 2; sshws_menu
}

do_renew_ssh() {
  sshws_header
  echo ""
  echo -e "  ${YELLOW}PERPANJANG AKUN SSH${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  do_list_ssh_simple
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username
  local info=$(get_ssh_info "$username")
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; sshws_menu; return; }
  local old_exp=$(echo "$info" | cut -d'|' -f3)
  echo -e "  ${YELLOW}Expired saat ini${NC}: ${WHITE}$old_exp${NC}"
  echo -ne "  ${YELLOW}Perpanjang (hari)${NC}: "; read -r days; days=${days:-30}
  renew_ssh "$username" "$days"
  echo -e "  ${GREEN}[✓] Diperpanjang hingga ${WHITE}$(get_exp_date "$days")${NC}"; sleep 2; sshws_menu
}

do_list_ssh_simple() {
  local count=0
  printf "  ${CYAN}%-20s %-14s %-12s${NC}\n" "USERNAME" "PASSWORD" "EXPIRED"
  echo -e "  ${CYAN}$LINE${NC}"
  while IFS='|' read -r user pass exp created; do
    [[ -z "$user" ]] && continue
    local r=$(days_until_exp "$exp")
    local c="${WHITE}"
    [[ $r -lt 0 ]] && c="${RED}"
    [[ $r -le 3 && $r -ge 0 ]] && c="${YELLOW}"
    printf "  ${c}%-20s %-14s %-12s${NC}\n" "$user" "$pass" "$exp"
    ((count++))
  done < <(list_ssh)
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Total${NC}: ${WHITE}$count akun${NC}"
}

do_list_ssh() {
  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ◈  DAFTAR AKUN SSH  ◈${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  do_list_ssh_simple
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  sshws_menu
}

sshws_menu
