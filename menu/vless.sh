#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - VLESS MENU
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

# ─── VLess Menu Header ─────────────────────────────────────
vless_header() {
  clear
  local domain=$(get_domain)
  local count=$(count_vless)
  local xray_st=$(service_status_text xray)

  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${WHITE}                 ◈  VLESS WEBSOCKET MENU  ◈                   ${CYAN}║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Domain${NC}         : ${WHITE}$domain${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Status Xray${NC}    : $([ "$xray_st" = "ON" ] && echo "${GREEN}● RUNNING${NC}" || echo "${RED}● STOPPED${NC}")"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Port TLS${NC}       : ${WHITE}443 (via Nginx)${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Port non-TLS${NC}   : ${WHITE}80 (via Nginx)${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Path TLS${NC}       : ${WHITE}/vless-ws${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Path non-TLS${NC}   : ${WHITE}/vless-ntls${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}▸ Total Akun${NC}     : ${WHITE}$count akun${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
}

vless_menu() {
  vless_header
  echo ""
  echo -e "  ${CYAN}┌─────────────────────────────────────────┐${NC}"
  echo -e "  ${CYAN}│${WHITE}       VLESS WS - TLS & non-TLS        ${CYAN}│${NC}"
  echo -e "  ${CYAN}├─────────────────────────────────────────┤${NC}"
  echo -e "  ${CYAN}│${NC}  ${GREEN}[1]${NC} ${WHITE}Buat Akun VLess${NC}                  ${CYAN}│${NC}"
  echo -e "  ${CYAN}├─────────────────────────────────────────┤${NC}"
  echo -e "  ${CYAN}│${NC}  ${GREEN}[2]${NC} ${WHITE}Info Akun VLess${NC}                  ${CYAN}│${NC}"
  echo -e "  ${CYAN}├─────────────────────────────────────────┤${NC}"
  echo -e "  ${CYAN}│${NC}  ${GREEN}[3]${NC} ${WHITE}Detail Akun VLess${NC}                ${CYAN}│${NC}"
  echo -e "  ${CYAN}├─────────────────────────────────────────┤${NC}"
  echo -e "  ${CYAN}│${NC}  ${RED}[4]${NC} ${WHITE}Hapus Akun VLess${NC}                 ${CYAN}│${NC}"
  echo -e "  ${CYAN}├─────────────────────────────────────────┤${NC}"
  echo -e "  ${CYAN}│${NC}  ${YELLOW}[5]${NC} ${WHITE}Perpanjang Akun VLess${NC}            ${CYAN}│${NC}"
  echo -e "  ${CYAN}├─────────────────────────────────────────┤${NC}"
  echo -e "  ${CYAN}│${NC}  ${YELLOW}[6]${NC} ${WHITE}Renew Akun VLess${NC}                 ${CYAN}│${NC}"
  echo -e "  ${CYAN}├─────────────────────────────────────────┤${NC}"
  echo -e "  ${CYAN}│${NC}  ${CYAN}[7]${NC} ${WHITE}List Semua Akun VLess${NC}            ${CYAN}│${NC}"
  echo -e "  ${CYAN}├─────────────────────────────────────────┤${NC}"
  echo -e "  ${CYAN}│${NC}  ${DIM}[0]${NC} ${WHITE}Kembali ke Menu Utama${NC}            ${CYAN}│${NC}"
  echo -e "  ${CYAN}└─────────────────────────────────────────┘${NC}"
  echo ""
  echo -ne "  ${WHITE}Pilih${NC} ${CYAN}[0-7]${NC}: "
  read -r choice

  case "$choice" in
    1) do_create_vless ;;
    2) do_info_vless ;;
    3) do_detail_vless ;;
    4) do_delete_vless ;;
    5) do_renew_vless ;;
    6) do_renew_vless ;;
    7) do_list_vless ;;
    0) bash $SCRIPT_DIR/menu.sh ;;
    *) echo -e "${RED}[!] Pilihan tidak valid${NC}"; sleep 1; vless_menu ;;
  esac
}

# ─── Create VLess ──────────────────────────────────────────
do_create_vless() {
  vless_header
  echo ""
  echo -e "  ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${CYAN}  BUAT AKUN VLESS BARU${NC}"
  echo -e "  ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "
  read -r username

  if [[ -z "$username" ]]; then
    echo -e "  ${RED}[!] Username tidak boleh kosong!${NC}"
    sleep 2; vless_menu; return
  fi

  if grep -q "^$username|" "$DB_VLESS" 2>/dev/null; then
    echo -e "  ${RED}[!] Username '$username' sudah ada!${NC}"
    sleep 2; vless_menu; return
  fi

  echo -ne "  ${YELLOW}Masa aktif (hari)${NC}: "
  read -r days
  days=${days:-30}

  echo ""
  echo -e "  ${CYAN}[*]${NC} Membuat akun..."
  local uuid=$(create_vless "$username" "$days")
  local domain=$(get_domain)
  local exp=$(get_exp_date "$days")
  local link_tls=$(gen_vless_link "$username" "$uuid" "$domain" "tls")
  local link_ntls=$(gen_vless_link "$username" "$uuid" "$domain" "ntls")

  clear
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${WHITE}              ✓  AKUN VLESS BERHASIL DIBUAT                   ${CYAN}║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Username  ${NC}: ${WHITE}$username${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}UUID      ${NC}: ${WHITE}$uuid${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Domain    ${NC}: ${WHITE}$domain${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Dibuat    ${NC}: ${WHITE}$(date +"%Y-%m-%d")${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Exp Date  ${NC}: ${WHITE}$exp${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Masa aktif${NC}: ${WHITE}$days hari${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${WHITE}  ── WS TLS (Port 443) ──${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Host${NC}: ${WHITE}$domain${NC}  ${YELLOW}Port${NC}: ${WHITE}443${NC}  ${YELLOW}Path${NC}: ${WHITE}/vless-ws${NC}  ${YELLOW}TLS${NC}: ${WHITE}ON${NC}"
  echo -e "${CYAN}║${WHITE}  ── WS non-TLS (Port 80) ──${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Host${NC}: ${WHITE}$domain${NC}  ${YELLOW}Port${NC}: ${WHITE}80${NC}  ${YELLOW}Path${NC}: ${WHITE}/vless-ntls${NC}  ${YELLOW}TLS${NC}: ${WHITE}OFF${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${WHITE}  VLess Link TLS:${NC}"
  echo -e "${CYAN}║${NC}  ${GREEN}$link_tls${NC}"
  echo -e "${CYAN}║${NC}"
  echo -e "${CYAN}║${WHITE}  VLess Link nTLS:${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}$link_ntls${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"

  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"
  read -r
  vless_menu
}

# ─── Info VLess ────────────────────────────────────────────
do_info_vless() {
  vless_header
  echo ""
  echo -e "  ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${CYAN}  INFO AKUN VLESS${NC}"
  echo -e "  ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "
  read -r username

  local info=$(get_vless_info "$username")
  if [[ -z "$info" ]]; then
    echo -e "  ${RED}[!] Akun '$username' tidak ditemukan!${NC}"
    sleep 2; vless_menu; return
  fi

  local uuid=$(echo "$info" | cut -d'|' -f2)
  local exp=$(echo "$info" | cut -d'|' -f3)
  local created=$(echo "$info" | cut -d'|' -f4)
  local domain=$(get_domain)
  local remaining=$(days_until_exp "$exp")

  local status_color="${GREEN}"
  local status_text="AKTIF"
  [[ $remaining -lt 0 ]] && { status_color="${RED}"; status_text="EXPIRED"; }
  [[ $remaining -le 3 && $remaining -ge 0 ]] && { status_color="${YELLOW}"; status_text="SEGERA EXPIRED"; }

  echo ""
  echo -e "  ${CYAN}┌─────────────────────────────────────────────┐${NC}"
  echo -e "  ${CYAN}│${WHITE}         INFO AKUN VLESS                   ${CYAN}│${NC}"
  echo -e "  ${CYAN}├─────────────────────────────────────────────┤${NC}"
  echo -e "  ${CYAN}│${NC}  ${YELLOW}Username  ${NC}: ${WHITE}$username${NC}"
  echo -e "  ${CYAN}│${NC}  ${YELLOW}UUID      ${NC}: ${WHITE}$uuid${NC}"
  echo -e "  ${CYAN}│${NC}  ${YELLOW}Domain    ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${CYAN}│${NC}  ${YELLOW}Dibuat    ${NC}: ${WHITE}$created${NC}"
  echo -e "  ${CYAN}│${NC}  ${YELLOW}Exp Date  ${NC}: ${WHITE}$exp${NC}"
  echo -e "  ${CYAN}│${NC}  ${YELLOW}Sisa      ${NC}: ${WHITE}${remaining} hari${NC}"
  echo -e "  ${CYAN}│${NC}  ${YELLOW}Status    ${NC}: ${status_color}● $status_text${NC}"
  echo -e "  ${CYAN}└─────────────────────────────────────────────┘${NC}"

  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"
  read -r
  vless_menu
}

# ─── Detail VLess ──────────────────────────────────────────
do_detail_vless() {
  vless_header
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "
  read -r username

  local info=$(get_vless_info "$username")
  if [[ -z "$info" ]]; then
    echo -e "  ${RED}[!] Akun '$username' tidak ditemukan!${NC}"
    sleep 2; vless_menu; return
  fi

  local uuid=$(echo "$info" | cut -d'|' -f2)
  local exp=$(echo "$info" | cut -d'|' -f3)
  local created=$(echo "$info" | cut -d'|' -f4)
  local domain=$(get_domain)
  local remaining=$(days_until_exp "$exp")
  local link_tls=$(gen_vless_link "$username" "$uuid" "$domain" "tls")
  local link_ntls=$(gen_vless_link "$username" "$uuid" "$domain" "ntls")

  clear
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${WHITE}               ◈  DETAIL AKUN VLESS  ◈                       ${CYAN}║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Username   ${NC}: ${WHITE}$username${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}UUID       ${NC}: ${WHITE}$uuid${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Encryption ${NC}: ${WHITE}none${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Network    ${NC}: ${WHITE}WebSocket (ws)${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Dibuat     ${NC}: ${WHITE}$created${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Expired    ${NC}: ${WHITE}$exp${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Sisa       ${NC}: ${WHITE}$remaining hari${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${WHITE}  ── Konfigurasi WS TLS ──${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Host${NC}: ${WHITE}$domain${NC}  ${YELLOW}Port${NC}: ${WHITE}443${NC}  ${YELLOW}Path${NC}: ${WHITE}/vless-ws${NC}  ${YELLOW}TLS${NC}: ${WHITE}ON${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${WHITE}  ── Konfigurasi WS non-TLS ──${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Host${NC}: ${WHITE}$domain${NC}  ${YELLOW}Port${NC}: ${WHITE}80${NC}  ${YELLOW}Path${NC}: ${WHITE}/vless-ntls${NC}  ${YELLOW}TLS${NC}: ${WHITE}OFF${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${WHITE}  VLess Link TLS:${NC}"
  echo -e "${CYAN}║${NC}  ${GREEN}$link_tls${NC}"
  echo -e "${CYAN}║${NC}"
  echo -e "${CYAN}║${WHITE}  VLess Link nTLS:${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}$link_ntls${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"

  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"
  read -r
  vless_menu
}

# ─── Delete VLess ──────────────────────────────────────────
do_delete_vless() {
  vless_header
  echo ""
  echo -e "  ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${RED}  HAPUS AKUN VLESS${NC}"
  echo -e "  ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  do_list_vless_simple
  echo ""
  echo -ne "  ${YELLOW}Username yang akan dihapus${NC}: "
  read -r username

  if [[ -z "$(get_vless_info "$username")" ]]; then
    echo -e "  ${RED}[!] Akun '$username' tidak ditemukan!${NC}"
    sleep 2; vless_menu; return
  fi

  echo -ne "  ${RED}Konfirmasi hapus '$username'? [y/N]${NC}: "
  read -r confirm
  [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo -e "  ${YELLOW}[!] Dibatalkan${NC}"; sleep 1; vless_menu; return; }

  delete_vless "$username"
  echo -e "  ${GREEN}[✓] Akun '$username' berhasil dihapus!${NC}"
  sleep 2
  vless_menu
}

# ─── Renew VLess ───────────────────────────────────────────
do_renew_vless() {
  vless_header
  echo ""
  echo -e "  ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${YELLOW}  PERPANJANG / RENEW AKUN VLESS${NC}"
  echo -e "  ${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  do_list_vless_simple
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "
  read -r username

  local info=$(get_vless_info "$username")
  if [[ -z "$info" ]]; then
    echo -e "  ${RED}[!] Akun '$username' tidak ditemukan!${NC}"
    sleep 2; vless_menu; return
  fi

  local old_exp=$(echo "$info" | cut -d'|' -f3)
  echo -e "  ${YELLOW}Expired saat ini${NC}: ${WHITE}$old_exp${NC}"
  echo -ne "  ${YELLOW}Perpanjang berapa hari${NC}: "
  read -r days
  days=${days:-30}

  renew_vless "$username" "$days"
  echo -e "  ${GREEN}[✓] Akun '$username' diperpanjang hingga ${WHITE}$(get_exp_date "$days")${NC}"
  sleep 2
  vless_menu
}

do_list_vless_simple() {
  local count=0
  printf "  ${CYAN}%-20s %-38s %-12s${NC}\n" "USERNAME" "UUID" "EXPIRED"
  printf "  ${DIM}%-20s %-38s %-12s${NC}\n" "────────────────────" "──────────────────────────────────────" "────────────"
  while IFS='|' read -r user uuid exp created; do
    local remaining=$(days_until_exp "$exp")
    local color="$WHITE"
    [[ $remaining -lt 0 ]] && color="$RED"
    [[ $remaining -le 3 && $remaining -ge 0 ]] && color="$YELLOW"
    printf "  ${color}%-20s %-38s %-12s${NC}\n" "$user" "$uuid" "$exp"
    ((count++))
  done < <(list_vless)
  echo ""; echo -e "  ${YELLOW}Total${NC}: ${WHITE}$count akun${NC}"
}

do_list_vless() {
  clear
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${WHITE}               ◈  DAFTAR AKUN VLESS  ◈                       ${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  do_list_vless_simple
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"
  read -r
  vless_menu
}

vless_menu
