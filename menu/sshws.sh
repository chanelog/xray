#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - SSH WEBSOCKET MANAGEMENT
#   Support: SSH WS + SSL & non-TLS NTLS
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

REPO="https://raw.githubusercontent.com/chanelog/bin/main"
BIN_DIR="/usr/local/bin"
DB_SSHWS="$SCRIPT_DIR/db/sshws.db"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ─── Initialize SSH WS DB ──────────────────────────────────
init_sshws_db() {
  [[ ! -f "$DB_SSHWS" ]] && touch "$DB_SSHWS"
}

# ─── SSH WS Account Management ─────────────────────────────
create_sshws_account() {
  local username="$1"
  local port="${2:-22}"
  local days="${3:-30}"
  local ssl_mode="${4:-tls}"  # tls, ntls
  local exp=$(get_exp_date "$days")
  local created=$(date +"%Y-%m-%d")
  local pid=$$

  # Add to database
  echo "$username|$port|$ssl_mode|$exp|$created|$pid" >> "$DB_SSHWS"
  echo "$pid"
}

list_sshws() {
  if [[ -s "$DB_SSHWS" ]]; then
    cat "$DB_SSHWS"
  else
    echo ""
  fi
}

get_sshws_info() {
  local username="$1"
  grep "^$username|" "$DB_SSHWS"
}

delete_sshws() {
  local username="$1"
  sed -i "/^$username|/d" "$DB_SSHWS"
}

count_sshws() {
  wc -l < "$DB_SSHWS" 2>/dev/null || echo 0
}

# ─── Install WS SSH Server ─────────────────────────────────
install_ws_ssh_server() {
  echo -e "\n${CYAN}[*]${NC} Menginstall WebSocket SSH Server..."
  
  # Download ws_tunnel.py
  echo -ne "  Downloading ws_tunnel.py..."
  wget -q --timeout=30 "$REPO/ws_tunnel.py" -O "$BIN_DIR/ws_tunnel.py"
  if [[ $? -eq 0 ]] && [[ -s "$BIN_DIR/ws_tunnel.py" ]]; then
    chmod +x "$BIN_DIR/ws_tunnel.py"
    echo -e " ${GREEN}OK${NC}"
  else
    echo -e " ${RED}GAGAL${NC}"
    return 1
  fi

  # Download ws-ssh-server.py
  echo -ne "  Downloading ws-ssh-server.py..."
  wget -q --timeout=30 "$REPO/ws-ssh-server.py" -O "$BIN_DIR/ws-ssh-server.py"
  if [[ $? -eq 0 ]] && [[ -s "$BIN_DIR/ws-ssh-server.py" ]]; then
    chmod +x "$BIN_DIR/ws-ssh-server.py"
    echo -e " ${GREEN}OK${NC}"
  else
    echo -e " ${RED}GAGAL${NC}"
    return 1
  fi

  # Setup systemd service template
  cat > /etc/systemd/system/ws-ssh@.service <<'SYSEOF'
[Unit]
Description=WebSocket SSH Proxy - %I
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/bin
ExecStart=/usr/bin/python3 /usr/local/bin/ws-ssh-server.py %i
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SYSEOF

  systemctl daemon-reload 2>/dev/null
  echo -e "${GREEN}[OK]${NC} WebSocket SSH Server terinstall"
}

# ─── Configure Nginx for SSH WS ────────────────────────────
configure_nginx_sshws() {
  local domain="$1"
  local sshws_port_tls="${2:-10005}"
  local sshws_port_ntls="${3:-10006}"

  local nginx_conf="/etc/nginx/conf.d/xray.conf"
  
  if [[ ! -f "$nginx_conf" ]]; then
    echo -e "${RED}[ERROR]${NC} Nginx config tidak ditemukan!"
    return 1
  fi

  # Backup existing config
  cp "$nginx_conf" "${nginx_conf}.backup.$(date +%s)"

  # Add SSH WS TLS location (port 443)
  local tmp=$(mktemp)
  cat "$nginx_conf" | sed '/location \/ {/a\
\    location /ws-ssh-tls {\
\        proxy_redirect off;\
\        proxy_pass http://127.0.0.1:'$sshws_port_tls';\
\        proxy_http_version 1.1;\
\        proxy_set_header Upgrade $http_upgrade;\
\        proxy_set_header Connection "upgrade";\
\        proxy_set_header Host $host;\
\        proxy_set_header X-Real-IP $remote_addr;\
\        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\
\        proxy_read_timeout 3600s;\
\    }' > "$tmp"
  
  # Add SSH WS non-TLS location (port 80)
  cat "$tmp" | sed '/location \/vmess-ntls/a\
\    location /ws-ssh-ntls {\
\        proxy_redirect off;\
\        proxy_pass http://127.0.0.1:'$sshws_port_ntls';\
\        proxy_http_version 1.1;\
\        proxy_set_header Upgrade $http_upgrade;\
\        proxy_set_header Connection "upgrade";\
\        proxy_set_header Host $host;\
\        proxy_set_header X-Real-IP $remote_addr;\
\        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\
\        proxy_read_timeout 3600s;\
\    }' > "$nginx_conf"

  rm -f "$tmp"

  if nginx -t 2>&1 | grep -q "successful"; then
    systemctl reload nginx 2>/dev/null
    echo -e "${GREEN}[OK]${NC} Nginx dikonfigurasi untuk SSH WS"
    return 0
  else
    echo -e "${RED}[ERROR]${NC} Nginx config syntax error, restore backup"
    mv "${nginx_conf}.backup.$(date +%s)" "$nginx_conf"
    return 1
  fi
}

# ─── Start SSH WS Service ──────────────────────────────────
start_sshws_service() {
  local domain="$1"
  local ssl_mode="${2:-tls}"  # tls, ntls
  local listen_port="${3:-10005}"
  local proxy_port="${4:-443}"
  
  if [[ "$ssl_mode" == "ntls" ]]; then
    proxy_port=80
  fi

  echo -e "\n${CYAN}[*]${NC} Memulai SSH WS service (mode: ${WHITE}$ssl_mode${NC})..."

  # Payload untuk WebSocket SSH
  local payload='GET /ws-ssh-'$ssl_mode' HTTP/1.1[crlf]Host: [host][crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]'

  # Tentukan nama service
  local service_name="ws-ssh-${ssl_mode}"

  # Generate service config
  local service_file="/etc/systemd/system/${service_name}.service"
  if [[ "$ssl_mode" == "tls" ]]; then
    cat > "$service_file" <<SVCEOF
[Unit]
Description=WebSocket SSH Proxy TLS
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/bin
ExecStart=/usr/bin/python3 /usr/local/bin/ws-ssh-server.py --listen 127.0.0.1:${listen_port} --proxy ${domain}:${proxy_port} --target localhost:22 --tls --sni ${domain} --payload "${payload}"
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF
  else
    cat > "$service_file" <<SVCEOF
[Unit]
Description=WebSocket SSH Proxy non-TLS
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/bin
ExecStart=/usr/bin/python3 /usr/local/bin/ws-ssh-server.py --listen 127.0.0.1:${listen_port} --proxy ${domain}:${proxy_port} --target localhost:22 --payload "${payload}"
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF
  fi

  systemctl daemon-reload 2>/dev/null
  systemctl enable "$service_name" 2>/dev/null
  systemctl start "$service_name" 2>/dev/null

  if systemctl is-active --quiet "$service_name"; then
    echo -e "${GREEN}[OK]${NC} Service $service_name running"
    return 0
  else
    echo -e "${RED}[ERROR]${NC} Service $service_name gagal start"
    return 1
  fi
}

# ─── Generate SSH WS Link ──────────────────────────────────
gen_sshws_link() {
  local username="$1"
  local domain="$2"
  local ssl_mode="${3:-tls}"
  local listen_port="${4:-8880}"

  if [[ "$ssl_mode" == "tls" ]]; then
    echo "ssh -o ProxyCommand='nc -x localhost:${listen_port} %h %p' root@${domain}"
  else
    echo "ssh -o ProxyCommand='nc -x localhost:${listen_port} %h %p' root@${domain}"
  fi
}

# ─── Setup SSH WS Menu ──────────────────────────────────────
show_sshws_menu() {
  init_sshws_db
  
  while true; do
    clear
    local domain=$(get_domain)
    local count=$(count_sshws)
    local ws_tls_status ws_ntls_status
    
    systemctl is-active --quiet ws-ssh-tls && ws_tls_status="${GREEN}● ON${NC}" || ws_tls_status="${RED}● OFF${NC}"
    systemctl is-active --quiet ws-ssh-ntls && ws_ntls_status="${GREEN}● ON${NC}" || ws_ntls_status="${RED}● OFF${NC}"

    echo -e "${CYAN}$LINE${NC}"
    echo -e "${WHITE}         SSH WEBSOCKET MANAGEMENT${NC}"
    echo -e "${CYAN}$LINE${NC}"
    echo -e "  Domain: ${WHITE}$domain${NC}"
    echo -e "  Akun aktif: ${WHITE}$count${NC}"
    echo -e "${CYAN}$LINE${NC}"
    echo -e "  WS SSH TLS (port 443)   : $ws_tls_status"
    echo -e "  WS SSH non-TLS (port 80): $ws_ntls_status"
    echo -e "${CYAN}$LINE${NC}"
    echo ""
    echo -e "  ${WHITE}MENU${NC}"
    echo -e "${CYAN}$LINE${NC}"
    echo -e "  ${YELLOW}[1]${NC}  Tambah Akun SSH WS"
    echo -e "  ${YELLOW}[2]${NC}  Lihat Semua Akun SSH WS"
    echo -e "  ${YELLOW}[3]${NC}  Hapus Akun SSH WS"
    echo -e "  ${YELLOW}[4]${NC}  Setup WS SSH TLS (443)"
    echo -e "  ${YELLOW}[5]${NC}  Setup WS SSH non-TLS (80)"
    echo -e "  ${YELLOW}[6]${NC}  Start SSH WS Services"
    echo -e "  ${YELLOW}[7]${NC}  Stop SSH WS Services"
    echo -e "  ${YELLOW}[8]${NC}  Restart SSH WS Services"
    echo -e "${CYAN}$LINE${NC}"
    echo -e "  ${DIM}[0]${NC}  Back to Main Menu"
    echo -e "${CYAN}$LINE${NC}"
    echo ""
    echo -ne "  ${WHITE}Pilih [0-8]${NC}: "
    read -r choice

    case "$choice" in
      1)
        echo ""
        echo -ne "  ${CYAN}Username${NC}: "
        read -r username
        
        if [[ -z "$username" ]]; then
          echo -e "  ${RED}[ERROR]${NC} Username tidak boleh kosong"
          sleep 2
          continue
        fi

        if grep -q "^$username|" "$DB_SSHWS"; then
          echo -e "  ${RED}[ERROR]${NC} Username sudah ada!"
          sleep 2
          continue
        fi

        echo -ne "  ${CYAN}Durasi (hari, default 30)${NC}: "
        read -r days
        days=${days:-30}

        echo -ne "  ${CYAN}Mode [1=TLS, 2=non-TLS] (default 1)${NC}: "
        read -r mode_choice
        mode_choice=${mode_choice:-1}
        
        if [[ "$mode_choice" == "2" ]]; then
          ssl_mode="ntls"
        else
          ssl_mode="tls"
        fi

        create_sshws_account "$username" "22" "$days" "$ssl_mode"
        echo -e "  ${GREEN}[OK]${NC} Akun SSH WS dibuat: ${WHITE}$username${NC} (${WHITE}$ssl_mode${NC})"
        echo -e "  ${YELLOW}[INFO]${NC} Gunakan IP lokal + port proxy untuk connect"
        sleep 3
        ;;

      2)
        echo ""
        if [[ -s "$DB_SSHWS" ]]; then
          echo -e "  ${CYAN}Daftar Akun SSH WS${NC}"
          echo -e "${CYAN}$LINE${NC}"
          echo -e "  ${YELLOW}Username${NC} | ${YELLOW}Port${NC} | ${YELLOW}Mode${NC} | ${YELLOW}Expired${NC}"
          echo -e "${CYAN}$LINE${NC}"
          while IFS='|' read -r user port mode exp created pid; do
            local days_left=$(days_until_exp "$exp")
            if is_expired "$exp"; then
              echo -e "  ${RED}$user${NC} | $port | $mode | ${RED}EXPIRED${NC} (${days_left} hari lalu)"
            else
              echo -e "  ${GREEN}$user${NC} | $port | $mode | ${WHITE}$exp${NC} (+${days_left} hari)"
            fi
          done < "$DB_SSHWS"
          echo -e "${CYAN}$LINE${NC}"
        else
          echo -e "  ${RED}[!]${NC} Tidak ada akun SSH WS"
        fi
        echo ""
        read -p "  Press ENTER to continue..."
        ;;

      3)
        echo ""
        echo -ne "  ${CYAN}Username yang akan dihapus${NC}: "
        read -r del_user

        if ! grep -q "^$del_user|" "$DB_SSHWS"; then
          echo -e "  ${RED}[ERROR]${NC} Username tidak ditemukan!"
          sleep 2
          continue
        fi

        echo -ne "  Yakin hapus? [y/N]: "
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          delete_sshws "$del_user"
          echo -e "  ${GREEN}[OK]${NC} Akun ${WHITE}$del_user${NC} dihapus"
        fi
        sleep 2
        ;;

      4)
        echo ""
        if ! command -v python3 &>/dev/null; then
          echo -e "  ${RED}[ERROR]${NC} Python3 tidak terinstall"
          sleep 2
          continue
        fi

        if [[ ! -f "$BIN_DIR/ws-ssh-server.py" ]]; then
          install_ws_ssh_server
        fi

        configure_nginx_sshws "$domain" "10005" "10006"
        start_sshws_service "$domain" "tls" "10005" "443"
        
        echo ""
        read -p "  Press ENTER to continue..."
        ;;

      5)
        echo ""
        if ! command -v python3 &>/dev/null; then
          echo -e "  ${RED}[ERROR]${NC} Python3 tidak terinstall"
          sleep 2
          continue
        fi

        if [[ ! -f "$BIN_DIR/ws-ssh-server.py" ]]; then
          install_ws_ssh_server
        fi

        configure_nginx_sshws "$domain" "10005" "10006"
        start_sshws_service "$domain" "ntls" "10006" "80"
        
        echo ""
        read -p "  Press ENTER to continue..."
        ;;

      6)
        echo ""
        echo -e "  ${CYAN}[*]${NC} Starting SSH WS services..."
        systemctl start ws-ssh-tls 2>/dev/null
        systemctl start ws-ssh-ntls 2>/dev/null
        echo -e "  ${GREEN}[OK]${NC} Services started"
        sleep 2
        ;;

      7)
        echo ""
        echo -e "  ${CYAN}[*]${NC} Stopping SSH WS services..."
        systemctl stop ws-ssh-tls 2>/dev/null
        systemctl stop ws-ssh-ntls 2>/dev/null
        echo -e "  ${GREEN}[OK]${NC} Services stopped"
        sleep 2
        ;;

      8)
        echo ""
        echo -e "  ${CYAN}[*]${NC} Restarting SSH WS services..."
        systemctl restart ws-ssh-tls 2>/dev/null
        systemctl restart ws-ssh-ntls 2>/dev/null
        echo -e "  ${GREEN}[OK]${NC} Services restarted"
        sleep 2
        ;;

      0)
        break
        ;;

      *)
        echo -e "  ${RED}[!]${NC} Pilihan tidak valid!"
        sleep 1
        ;;
    esac
  done
}

show_sshws_menu
