#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - SSH / SSH-WS / SSH-SSL MENU (ADDON)
#   SSH-WS: connect langsung ke port ws-openssh/ws-dropbear (tanpa Nginx)
#   SSH-SSL: stunnel4 (port publik) -> ws-stunnel (loopback)
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SLINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

sshws_addon_missing() {
  [[ ! -f /usr/local/bin/ws-openssh ]] || [[ ! -f /usr/local/bin/ws-dropbear ]] || [[ ! -f /usr/local/bin/ws-stunnel ]] || ! is_service_installed stunnel4
}

wstunnel_addon_missing() {
  [[ ! -x /usr/local/bin/wstunnel ]] || [[ ! -f /usr/local/bin/proxy--ws ]]
}

haproxy_addon_missing() {
  ! is_service_installed haproxy || [[ ! -f /etc/haproxy/haproxy.cfg ]]
}

ws_payload_string() {
  local domain="$1"
  local port="${2:-80}"
  printf 'GET /ssh-ws HTTP/1.1[crlf]Host: %s[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]' "$domain"
}

sshws_offer_install() {
  clear
  echo -e "${YELLOW}$LINE${NC}"
  echo -e "${WHITE}   FITUR SSH-WS / SSH-SSL BELUM DIINSTALL${NC}"
  echo -e "${YELLOW}$LINE${NC}"
  echo ""
  echo -e "  Fitur ini butuh komponen tambahan (stunnel4 + ws-openssh/ws-dropbear/ws-stunnel"
  echo -e "  + wstunnel/proxy--ws)."
  echo -e "  Instalasi bersifat aditif dan TIDAK mengubah/menghentikan"
  echo -e "  layanan VMess/VLess/Trojan/SS/Nginx/Dropbear yang sudah berjalan."
  echo ""
  echo -ne "  ${WHITE}Install sekarang? [Y/n]${NC}: "
  read -r c
  if [[ "$c" =~ ^[Nn]$ ]]; then
    bash "$SCRIPT_DIR/menu.sh"; return 1
  fi
  bash "$SCRIPT_DIR/addon/install-sshws.sh"
  if wstunnel_addon_missing; then
    bash "$SCRIPT_DIR/addon/install-wstunnel.sh"
  fi
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk lanjut...${NC}"; read -r
  return 0
}

sshws_header() {
  clear
  local domain=$(get_domain)
  local count=$(count_ssh)
  local db_st stunnel_st wso_st wsd_st wss_st wst_st hap_st
  systemctl is-active --quiet dropbear    && db_st="${GREEN}● RUNNING${NC}"     || db_st="${RED}● STOPPED${NC}"
  systemctl is-active --quiet stunnel4    && stunnel_st="${GREEN}● RUNNING${NC}" || stunnel_st="${RED}● STOPPED${NC}"
  systemctl is-active --quiet ws-openssh  && wso_st="${GREEN}● RUNNING${NC}"    || wso_st="${RED}● STOPPED${NC}"
  systemctl is-active --quiet ws-dropbear && wsd_st="${GREEN}● RUNNING${NC}"    || wsd_st="${RED}● STOPPED${NC}"
  systemctl is-active --quiet ws-stunnel  && wss_st="${GREEN}● RUNNING${NC}"    || wss_st="${RED}● STOPPED${NC}"
  systemctl is-active --quiet proxy--ws   && wst_st="${GREEN}● RUNNING${NC}"    || wst_st="${RED}● STOPPED${NC}"
  systemctl is-active --quiet haproxy     && hap_st="${GREEN}● RUNNING${NC}"    || hap_st="${RED}● STOPPED${NC}"

  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}      ⚡  SSH / SSH-WS / SSH-SSL MANAGEMENT  ⚡${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Domain          ${NC}: ${WHITE}$domain${NC}"
  echo -e "  ${YELLOW}Dropbear        ${NC}: $db_st"
  echo -e "  ${YELLOW}Stunnel4 (SSL)  ${NC}: $stunnel_st"
  echo -e "  ${YELLOW}SSH-WS OpenSSH  ${NC}: $wso_st"
  echo -e "  ${YELLOW}SSH-WS Dropbear ${NC}: $wsd_st"
  echo -e "  ${YELLOW}ws-stunnel      ${NC}: $wss_st"
  echo -e "  ${YELLOW}wstunnel(Rust)  ${NC}: $wst_st"
  echo -e "  ${YELLOW}HAProxy (SNI)   ${NC}: $hap_st"
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${PURPLE}SSH Direct       ${NC}: port ${WHITE}442, 109, 143${NC}"
  echo -e "  ${PURPLE}SSH-SSL          ${NC}: port ${WHITE}$STUNNEL_SSL_PORT${NC} (stunnel4 → ws-stunnel)"
  echo -e "  ${PURPLE}SSH-WS (OpenSSH) ${NC}: port ${WHITE}$WS_OPENSSH_PORT${NC}  (connect langsung, tanpa Nginx)"
  echo -e "  ${PURPLE}SSH-WS (Dropbear)${NC}: port ${WHITE}$WS_DROPBEAR_PORT${NC}  (connect langsung, tanpa Nginx)"
  echo -e "  ${PURPLE}SSH-WS (wstunnel)${NC}: port ${WHITE}$WSTUNNEL_PORT${NC}  (binary Rust, backend OpenSSH)"
  if systemctl is-active --quiet haproxy; then
    echo -e "  ${PURPLE}SSH-SSL via 443  ${NC}: port ${WHITE}443${NC}  (SNI ≠ $domain → HAProxy → stunnel4)"
  fi
  echo -e "  ${YELLOW}Total Akun       ${NC}: ${WHITE}$count akun${NC}"
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
  if haproxy_addon_missing; then
    echo -e "  ${PURPLE}[7]${NC}  Aktifkan SSH-SSL via Port 443 (install HAProxy, opsional)"
  else
    echo -e "  ${PURPLE}[7]${NC}  Kelola HAProxy (SSH-SSL via port 443)"
  fi
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${DIM}[0]${NC}  Kembali ke Menu Utama"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${WHITE}Pilih [0-7]${NC}: "
  read -r choice

  case "$choice" in
    1) do_create_ssh ;;
    2) do_info_ssh ;;
    3) do_detail_ssh ;;
    4) do_delete_ssh ;;
    5) do_renew_ssh ;;
    6) do_list_ssh ;;
    7) do_haproxy_menu ;;
    0) bash "$SCRIPT_DIR/menu.sh" ;;
    *) echo -e "  ${RED}[!] Pilihan tidak valid${NC}"; sleep 1; sshws_menu ;;
  esac
}

do_haproxy_menu() {
  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}   HAProxy — SSH-SSL numpang di port 443 (SNI Router)${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  if haproxy_addon_missing; then
    echo -e "  Fitur ini bikin SSH-SSL BISA JUGA diakses lewat port 443,"
    echo -e "  numpang bareng Xray, dibedain otomatis pakai SNI:"
    echo -e "    - SNI = domain kamu  -> tetap ke Xray/Nginx seperti biasa"
    echo -e "    - SNI lain/kosong    -> diarahkan ke SSH-SSL (stunnel4)"
    echo ""
    echo -e "  ${YELLOW}CATATAN:${NC} Nginx akan digeser dari port 443 publik ke"
    echo -e "  127.0.0.1:$NGINX_TLS_INTERNAL_PORT (loopback). Proses ini di-backup"
    echo -e "  otomatis dan divalidasi sebelum diterapkan — kalau gagal, otomatis"
    echo -e "  di-rollback supaya server tetap bisa diakses."
    echo ""
    echo -ne "  ${WHITE}Install sekarang? [y/N]${NC}: "
    read -r c
    if [[ "$c" =~ ^[Yy]$ ]]; then
      bash "$SCRIPT_DIR/addon/install-haproxy.sh"
    fi
  else
    local hap_st
    systemctl is-active --quiet haproxy && hap_st="${GREEN}● RUNNING${NC}" || hap_st="${RED}● STOPPED${NC}"
    echo -e "  Status HAProxy : $hap_st"
    echo -e "  Config         : /etc/haproxy/haproxy.cfg"
    echo ""
    echo -e "  ${GREEN}[1]${NC}  Restart HAProxy"
    echo -e "  ${YELLOW}[2]${NC}  Install ulang / render ulang config"
    echo -e "  ${RED}[3]${NC}  Copot HAProxy (kembalikan Nginx ke port 443 publik)"
    echo -e "  ${DIM}[0]${NC}  Kembali"
    echo ""
    echo -ne "  ${WHITE}Pilih [0-3]${NC}: "
    read -r hc
    case "$hc" in
      1) systemctl restart haproxy; echo -e "  ${GREEN}[OK]${NC} HAProxy di-restart."; sleep 1 ;;
      2) bash "$SCRIPT_DIR/addon/install-haproxy.sh" ;;
      3)
        echo -ne "  ${RED}Yakin copot HAProxy? Nginx akan dikembalikan ke port 443 publik [y/N]${NC}: "
        read -r rc
        if [[ "$rc" =~ ^[Yy]$ ]]; then
          systemctl stop haproxy 2>/dev/null
          systemctl disable haproxy 2>/dev/null
          NGINX_XRAY_CONF="/etc/nginx/conf.d/xray.conf"
          if [[ -f "$NGINX_XRAY_CONF" ]] && grep -q "listen 127.0.0.1:$NGINX_TLS_INTERNAL_PORT ssl http2;" "$NGINX_XRAY_CONF"; then
            cp "$NGINX_XRAY_CONF" "${NGINX_XRAY_CONF}.bak.$(date +%s)"
            sed -i "s/listen 127.0.0.1:${NGINX_TLS_INTERNAL_PORT} ssl http2;/listen 443 ssl http2;\n    listen [::]:443 ssl http2;/" "$NGINX_XRAY_CONF"
            if nginx -t 2>/dev/null; then
              systemctl reload nginx 2>/dev/null
              echo -e "  ${GREEN}[OK]${NC} HAProxy dicopot, Nginx kembali ke port 443 publik."
            else
              echo -e "  ${RED}[ERROR]${NC} nginx -t gagal, cek manual: $NGINX_XRAY_CONF"
            fi
          fi
        fi
        sleep 1
        ;;
    esac
  fi
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
  sshws_menu
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
  echo -e "  ${WHITE}SSH-WS (OpenSSH) ${NC}: $domain  port $WS_OPENSSH_PORT   (langsung, tanpa Nginx)"
  echo -e "  ${WHITE}SSH-WS (Dropbear)${NC}: $domain  port $WS_DROPBEAR_PORT  (langsung, tanpa Nginx)"
  echo -e "  ${WHITE}SSH-WS (wstunnel)${NC}: $domain  port $WSTUNNEL_PORT  (binary Rust, backend OpenSSH)"
  if systemctl is-active --quiet haproxy; then
    echo -e "  ${WHITE}SSH-SSL via 443  ${NC}: $domain  port 443  (SNI ≠ $domain, lewat HAProxy)"
  fi
  echo -e "${CYAN}$LINE${NC}"
  echo -e "  ${YELLOW}Payload WS (contoh, path bebas - script cuma cek header)${NC}:"
  echo -e "  ${WHITE}$(ws_payload_string "$domain")${NC}"
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
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[3] SSH-WS — backend OpenSSH${NC}"
  echo -e "      Host: $domain   Port: $WS_OPENSSH_PORT   (connect langsung, TIDAK lewat Nginx)"
  echo -e "      Payload: ${YELLOW}$(ws_payload_string "$domain" "$WS_OPENSSH_PORT")${NC}"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[4] SSH-WS — backend Dropbear${NC}"
  echo -e "      Host: $domain   Port: $WS_DROPBEAR_PORT   (connect langsung, TIDAK lewat Nginx)"
  echo -e "      Payload: ${YELLOW}$(ws_payload_string "$domain" "$WS_DROPBEAR_PORT")${NC}"
  echo -e "${SLINE}"
  echo -e "  ${WHITE}[5] SSH-WS — wstunnel (Rust binary)${NC}"
  echo -e "      Host: $domain   Port: $WSTUNNEL_PORT   Backend: 127.0.0.1:22 (OpenSSH)"
  if systemctl is-active --quiet haproxy; then
    echo -e "${SLINE}"
    echo -e "  ${WHITE}[6] SSH-SSL — numpang port 443 (HAProxy SNI)${NC}"
    echo -e "      Host: $domain   Port: 443   SNI: apa saja SELAIN '$domain' (mis. google.com)"
    echo -e "      (Kalau SNI = '$domain', trafik dikira Xray & diteruskan ke Nginx, bukan SSH)"
  fi
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
