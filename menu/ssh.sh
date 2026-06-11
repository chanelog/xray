#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - SSH MENU
#   SSH WS via ohpserver (chanelog/bin)
#   SSH SSL/TLS via stunnel
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ssh_header() {
  clear
  local domain=$(get_domain)
  local db_st sshws_st stunnel_st
  systemctl is-active --quiet dropbear  && db_st="${GREEN}● ON${NC}"     || db_st="${RED}● OFF${NC}"
  systemctl is-active --quiet ssh-ws    && sshws_st="${GREEN}● ON${NC}"  || sshws_st="${RED}● OFF${NC}"
  systemctl is-active --quiet stunnel4  && stunnel_st="${GREEN}● ON${NC}" || stunnel_st="${RED}● OFF${NC}"
  local total=$(wc -l < $SCRIPT_DIR/db/ssh.db 2>/dev/null || echo 0)

  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ⚡  SSH TUNNEL MENU  ⚡${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Domain      ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Dropbear    ${NC}: $db_st    ${YELLOW}SSH-WS${NC}: $sshws_st    ${YELLOW}Stunnel${NC}: $stunnel_st"
  echo -e "  ${YELLOW}Total Akun  ${NC}: ${WHITE}$total akun${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${PURPLE}Dropbear SSH   ${NC}: ${WHITE}443, 109${NC}"
  echo -e "  ${PURPLE}SSH WS         ${NC}: ${WHITE}80, 8080, 8081-9999${NC}  ${DIM}(via ohpserver + nginx)${NC}"
  echo -e "  ${PURPLE}SSH SSL WS     ${NC}: ${WHITE}443${NC}  ${DIM}(via nginx TLS)${NC}"
  echo -e "  ${PURPLE}SSH SSL/TLS    ${NC}: ${WHITE}400, 465, 777, 900${NC}  ${DIM}(via stunnel)${NC}"
  echo -e "${CYAN}$LINE${NC}"
}

ssh_menu() {
  ssh_header
  echo ""
  echo -e "  ${WHITE}SSH TUNNEL MANAGEMENT${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}[1]${NC}  Buat Akun SSH"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}[2]${NC}  Info Akun SSH"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}[3]${NC}  Detail Akun SSH"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${RED}[4]${NC}  Hapus Akun SSH"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}[5]${NC}  Perpanjang Akun SSH"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}[6]${NC}  Renew Akun SSH"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${CYAN}[7]${NC}  List Semua Akun SSH"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${DIM}[0]${NC}  Kembali ke Menu Utama"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${WHITE}Pilih [0-7]${NC}: "
  read -r choice

  case "$choice" in
    1) do_create_ssh ;;
    2) do_info_ssh ;;
    3) do_detail_ssh ;;
    4) do_delete_ssh ;;
    5) do_renew_ssh ;;
    6) do_renew_ssh ;;
    7) do_list_ssh ;;
    0) bash $SCRIPT_DIR/menu.sh ;;
    *) echo -e "  ${RED}[!] Pilihan tidak valid${NC}"; sleep 1; ssh_menu ;;
  esac
}

# ─── Buat Akun SSH ─────────────────────────────────────────
do_create_ssh() {
  ssh_header
  echo ""
  echo -e "  ${WHITE}BUAT AKUN SSH BARU${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username      ${NC}: "; read -r username
  [[ -z "$username" ]] && { echo -e "  ${RED}[!] Username kosong!${NC}"; sleep 2; ssh_menu; return; }
  id "$username" &>/dev/null && { echo -e "  ${RED}[!] Username '$username' sudah ada!${NC}"; sleep 2; ssh_menu; return; }

  echo -ne "  ${YELLOW}Password      ${NC}: "; read -r -s password; echo ""
  [[ -z "$password" ]] && { echo -e "  ${RED}[!] Password kosong!${NC}"; sleep 2; ssh_menu; return; }

  echo -ne "  ${YELLOW}Masa aktif (hari)${NC}: "; read -r days; days=${days:-30}
  [[ ! "$days" =~ ^[0-9]+$ ]] && { echo -e "  ${RED}[!] Harus angka!${NC}"; sleep 2; ssh_menu; return; }

  local exp=$(date -d "+${days} days" +"%Y-%m-%d")
  local created=$(date +"%Y-%m-%d")
  local domain=$(get_domain)

  # Buat user system dengan shell /bin/false & expiry
  useradd -e "$exp" -s /bin/false -M "$username" 2>/dev/null
  echo "$username:$password" | chpasswd 2>/dev/null

  # Simpan ke database
  echo "$username|$password|$exp|$created" >> $SCRIPT_DIR/db/ssh.db

  # Generate payload
  local pl_ws="GET /ssh-ws HTTP/1.1[crlf]Host: ${domain}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
  local pl_ws2="CONNECT ${domain}:8080 HTTP/1.1[crlf]Host: ${domain}[crlf][crlf]"
  local pl_ssl="GET /ssh-ws HTTP/1.1[crlf]Host: ${domain}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
  local pl_tls="CONNECT ${domain}:22 HTTP/1.1[crlf]Host: ${domain}[crlf][crlf]"

  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}           ✓  AKUN SSH BERHASIL DIBUAT${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Username    ${NC}: ${WHITE}$username${NC}"
  echo -e "  ${YELLOW}Password    ${NC}: ${WHITE}$password${NC}"
  echo -e "  ${YELLOW}Dibuat      ${NC}: ${WHITE}$created${NC}"
  echo -e "  ${YELLOW}Expired     ${NC}: ${WHITE}$exp${NC}"
  echo -e "  ${YELLOW}Masa Aktif  ${NC}: ${WHITE}$days hari${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${PURPLE}◈ DROPBEAR SSH${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Host   ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Port   ${NC}: ${WHITE}443 / 109${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${PURPLE}◈ SSH WEBSOCKET — WS (non-TLS)${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Host    ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Port    ${NC}: ${WHITE}80 / 8080 / 8081-9999${NC}"
  echo -e "  ${YELLOW}Path    ${NC}: ${WHITE}/ssh-ws${NC}"
  echo -e "  ${YELLOW}TLS     ${NC}: ${RED}OFF${NC}"
  echo -e "  ${YELLOW}Payload ${NC}: ${GREEN}$pl_ws${NC}"
  echo -e "  ${YELLOW}Payload2${NC}: ${GREEN}$pl_ws2${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${PURPLE}◈ SSH SSL WEBSOCKET — WSS (TLS)${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Host    ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Port    ${NC}: ${WHITE}443${NC}"
  echo -e "  ${YELLOW}Path    ${NC}: ${WHITE}/ssh-ws${NC}"
  echo -e "  ${YELLOW}TLS     ${NC}: ${GREEN}ON${NC}"
  echo -e "  ${YELLOW}Payload ${NC}: ${GREEN}$pl_ssl${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${PURPLE}◈ SSH SSL/TLS — Stunnel${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Host    ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Port    ${NC}: ${WHITE}400 / 465 / 777 / 900${NC}"
  echo -e "  ${YELLOW}TLS     ${NC}: ${GREEN}ON${NC}"
  echo -e "  ${YELLOW}Payload ${NC}: ${GREEN}$pl_tls${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  ssh_menu
}

# ─── Info Akun SSH ─────────────────────────────────────────
do_info_ssh() {
  ssh_header
  echo ""
  echo -e "  ${WHITE}INFO AKUN SSH${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username

  local info=$(grep "^$username|" $SCRIPT_DIR/db/ssh.db 2>/dev/null)
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; ssh_menu; return; }

  local pass=$(echo "$info"    | cut -d'|' -f2)
  local exp=$(echo "$info"     | cut -d'|' -f3)
  local created=$(echo "$info" | cut -d'|' -f4)
  local remaining=$(days_until_exp "$exp")

  local sc="${GREEN}"; local st="AKTIF"
  [[ $remaining -lt 0 ]] && { sc="${RED}"; st="EXPIRED"; }
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
  ssh_menu
}

# ─── Detail Akun SSH ───────────────────────────────────────
do_detail_ssh() {
  ssh_header
  echo ""
  echo -e "  ${WHITE}DETAIL AKUN SSH${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username

  local info=$(grep "^$username|" $SCRIPT_DIR/db/ssh.db 2>/dev/null)
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; ssh_menu; return; }

  local pass=$(echo "$info"    | cut -d'|' -f2)
  local exp=$(echo "$info"     | cut -d'|' -f3)
  local created=$(echo "$info" | cut -d'|' -f4)
  local remaining=$(days_until_exp "$exp")
  local domain=$(get_domain)

  local pl_ws="GET /ssh-ws HTTP/1.1[crlf]Host: ${domain}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
  local pl_ws2="CONNECT ${domain}:8080 HTTP/1.1[crlf]Host: ${domain}[crlf][crlf]"
  local pl_ssl="GET /ssh-ws HTTP/1.1[crlf]Host: ${domain}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]"
  local pl_tls="CONNECT ${domain}:22 HTTP/1.1[crlf]Host: ${domain}[crlf][crlf]"

  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ◈  DETAIL AKUN SSH  ◈${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Username    ${NC}: ${WHITE}$username${NC}"
  echo -e "  ${YELLOW}Password    ${NC}: ${WHITE}$pass${NC}"
  echo -e "  ${YELLOW}Dibuat      ${NC}: ${WHITE}$created${NC}"
  echo -e "  ${YELLOW}Expired     ${NC}: ${WHITE}$exp${NC}"
  echo -e "  ${YELLOW}Sisa        ${NC}: ${WHITE}$remaining hari${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${PURPLE}◈ DROPBEAR SSH${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Host   ${NC}: ${WHITE}$domain${NC}   ${YELLOW}Port${NC}: ${WHITE}443 / 109${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${PURPLE}◈ SSH WS (non-TLS)${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Host    ${NC}: ${WHITE}$domain${NC}   ${YELLOW}Port${NC}: ${WHITE}80 / 8080 / 8081-9999${NC}"
  echo -e "  ${YELLOW}Path    ${NC}: ${WHITE}/ssh-ws${NC}   ${YELLOW}TLS${NC}: ${RED}OFF${NC}"
  echo -e "  ${YELLOW}Payload ${NC}: ${GREEN}$pl_ws${NC}"
  echo -e "  ${YELLOW}Payload2${NC}: ${GREEN}$pl_ws2${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${PURPLE}◈ SSH SSL WS (TLS)${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Host    ${NC}: ${WHITE}$domain${NC}   ${YELLOW}Port${NC}: ${WHITE}443${NC}"
  echo -e "  ${YELLOW}Path    ${NC}: ${WHITE}/ssh-ws${NC}   ${YELLOW}TLS${NC}: ${GREEN}ON${NC}"
  echo -e "  ${YELLOW}Payload ${NC}: ${GREEN}$pl_ssl${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${PURPLE}◈ SSH SSL/TLS Stunnel${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Host    ${NC}: ${WHITE}$domain${NC}   ${YELLOW}Port${NC}: ${WHITE}400 / 465 / 777 / 900${NC}"
  echo -e "  ${YELLOW}TLS     ${NC}: ${GREEN}ON${NC}"
  echo -e "  ${YELLOW}Payload ${NC}: ${GREEN}$pl_tls${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  ssh_menu
}

# ─── Hapus Akun SSH ────────────────────────────────────────
do_delete_ssh() {
  ssh_header
  echo ""
  echo -e "  ${RED}HAPUS AKUN SSH${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  do_list_ssh_simple
  echo ""
  echo -ne "  ${YELLOW}Username yang dihapus${NC}: "; read -r username
  [[ -z "$(grep "^$username|" $SCRIPT_DIR/db/ssh.db 2>/dev/null)" ]] && \
    { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; ssh_menu; return; }

  echo -ne "  ${RED}Konfirmasi hapus '$username'? [y/N]${NC}: "; read -r c
  [[ ! "$c" =~ ^[Yy]$ ]] && { echo -e "  ${YELLOW}Dibatalkan${NC}"; sleep 1; ssh_menu; return; }

  userdel -f "$username" 2>/dev/null
  sed -i "/^$username|/d" $SCRIPT_DIR/db/ssh.db
  echo -e "  ${GREEN}[✓] Akun '$username' berhasil dihapus!${NC}"
  sleep 2; ssh_menu
}

# ─── Perpanjang Akun SSH ───────────────────────────────────
do_renew_ssh() {
  ssh_header
  echo ""
  echo -e "  ${YELLOW}PERPANJANG AKUN SSH${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  do_list_ssh_simple
  echo ""
  echo -ne "  ${YELLOW}Username${NC}: "; read -r username
  local info=$(grep "^$username|" $SCRIPT_DIR/db/ssh.db 2>/dev/null)
  [[ -z "$info" ]] && { echo -e "  ${RED}[!] Akun tidak ditemukan!${NC}"; sleep 2; ssh_menu; return; }

  local old_exp=$(echo "$info" | cut -d'|' -f3)
  echo -e "  ${YELLOW}Expired saat ini${NC}: ${WHITE}$old_exp${NC}"
  echo -ne "  ${YELLOW}Perpanjang (hari)${NC}: "; read -r days; days=${days:-30}

  local new_exp=$(date -d "+${days} days" +"%Y-%m-%d")
  sed -i "s/^$username|\([^|]*\)|\([^|]*\)|\(.*\)$/$username|\1|$new_exp|\3/" \
    $SCRIPT_DIR/db/ssh.db
  chage -E "$new_exp" "$username" 2>/dev/null

  echo -e "  ${GREEN}[✓] Diperpanjang hingga ${WHITE}$new_exp${NC}"
  sleep 2; ssh_menu
}

# ─── List SSH ──────────────────────────────────────────────
do_list_ssh_simple() {
  local count=0
  printf "  ${CYAN}%-18s %-18s %-12s %-10s${NC}\n" "USERNAME" "PASSWORD" "EXPIRED" "SISA"
  echo -e "  ${CYAN}$LINE${NC}"
  while IFS='|' read -r user pass exp created; do
    local r=$(days_until_exp "$exp")
    local c="${WHITE}"
    [[ $r -lt 0 ]] && c="${RED}"
    [[ $r -le 3 && $r -ge 0 ]] && c="${YELLOW}"
    printf "  ${c}%-18s %-18s %-12s %-10s${NC}\n" "$user" "$pass" "$exp" "${r}hr"
    ((count++))
  done < <(cat $SCRIPT_DIR/db/ssh.db 2>/dev/null)
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
  ssh_menu
}

ssh_menu
