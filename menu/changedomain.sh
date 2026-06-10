#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - CHANGE DOMAIN MENU
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

changedomain_menu() {
  clear
  local current_domain=$(get_domain)
  local current_ip=$(get_server_ip)

  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${WHITE}                ◈  GANTI DOMAIN  ◈                           ${CYAN}║${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}Domain Saat Ini ${NC}: ${WHITE}$current_domain${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}IP Server       ${NC}: ${WHITE}$current_ip${NC}"
  echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
  echo -e "${CYAN}║${NC}"
  echo -e "${CYAN}║${NC}  ${YELLOW}⚠ PERHATIAN:${NC}"
  echo -e "${CYAN}║${NC}  ${WHITE}1. Pastikan domain baru sudah diarahkan ke IP server${NC}"
  echo -e "${CYAN}║${NC}  ${WHITE}2. Semua akun yang ada akan tetap berfungsi${NC}"
  echo -e "${CYAN}║${NC}  ${WHITE}3. SSL baru akan diminta dari Let's Encrypt${NC}"
  echo -e "${CYAN}║${NC}  ${WHITE}4. Nginx akan dikonfigurasi ulang otomatis${NC}"
  echo -e "${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  echo -ne "  ${YELLOW}Domain baru${NC}: "
  read -r new_domain
  new_domain=$(echo "$new_domain" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  if [[ -z "$new_domain" ]]; then
    echo -e "  ${RED}[!] Domain tidak boleh kosong!${NC}"
    sleep 2; bash $SCRIPT_DIR/menu.sh; return
  fi

  if [[ "$new_domain" == "$current_domain" ]]; then
    echo -e "  ${YELLOW}[!] Domain sama dengan yang sekarang!${NC}"
    sleep 2; bash $SCRIPT_DIR/menu.sh; return
  fi

  # Verify domain
  echo -e "  ${CYAN}[*]${NC} Memverifikasi domain ${WHITE}$new_domain${NC}..."
  local domain_ip=$(dig +short "$new_domain" A 2>/dev/null | tail -1)

  if [[ -z "$domain_ip" ]]; then
    echo -e "  ${RED}[!] Domain '$new_domain' tidak ditemukan di DNS!${NC}"
    echo -ne "  Lanjutkan meski DNS belum propagasi? [y/N]: "
    read -r force
    [[ ! "$force" =~ ^[Yy]$ ]] && { bash $SCRIPT_DIR/menu.sh; return; }
  elif [[ "$domain_ip" != "$current_ip" ]]; then
    echo -e "  ${YELLOW}[WARN]${NC} Domain mengarah ke $domain_ip, bukan $current_ip"
    echo -ne "  Lanjutkan? [y/N]: "
    read -r force
    [[ ! "$force" =~ ^[Yy]$ ]] && { bash $SCRIPT_DIR/menu.sh; return; }
  else
    echo -e "  ${GREEN}[✓] DNS terverifikasi: $new_domain → $current_ip${NC}"
  fi

  echo -ne "  ${WHITE}Konfirmasi ganti domain dari '${current_domain}' ke '${new_domain}'? [y/N]${NC}: "
  read -r confirm
  [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo -e "  ${YELLOW}Dibatalkan${NC}"; sleep 1; bash $SCRIPT_DIR/menu.sh; return; }

  echo ""
  echo -e "  ${CYAN}[*]${NC} Mengganti domain..."

  # Update nginx config
  sed -i "s/$current_domain/$new_domain/g" /etc/nginx/conf.d/xray.conf 2>/dev/null

  # Stop nginx for standalone ACME
  systemctl stop nginx 2>/dev/null

  echo -e "  ${CYAN}[*]${NC} Meminta SSL certificate baru..."
  /root/.acme.sh/acme.sh --issue --standalone -d "$new_domain" \
    --keylength ec-256 --httpport 80 2>/dev/null

  /root/.acme.sh/acme.sh --installcert -d "$new_domain" \
    --ecc \
    --key-file /etc/ssl/xray/xray.key \
    --fullchain-file /etc/ssl/xray/xray.crt \
    --reloadcmd "systemctl restart xray nginx 2>/dev/null" 2>/dev/null

  # Save new domain
  echo "$new_domain" > $SCRIPT_DIR/domain

  systemctl start nginx 2>/dev/null
  systemctl restart xray 2>/dev/null

  echo ""
  echo -e "${GREEN}  ╔══════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}  ║  ✓  Domain berhasil diganti!            ║${NC}"
  echo -e "${GREEN}  ║  Domain : $new_domain$(printf '%*s' $((27 - ${#new_domain})) '')║${NC}"
  echo -e "${GREEN}  ╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali...${NC}"
  read -r
  bash $SCRIPT_DIR/menu.sh
}

changedomain_menu
