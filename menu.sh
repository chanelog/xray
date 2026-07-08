#!/bin/bash
# =============================================================================
# menu.sh - main entry point ("menu" command once installed)
# =============================================================================
set -o pipefail

TS_LIB="/usr/local/lib/tunnel-suite"
source "$TS_LIB/common.sh"
source "$TS_LIB/ssh_manager.sh"
source "$TS_LIB/xray_manager.sh"

need_root

count_ssh() { [[ -s "$SSH_DB" ]] && wc -l < "$SSH_DB" || echo 0; }

dashboard() {
    local domain ip os kernel cores load mem_used mem_total mem_pct disk_used disk_total disk_pct uptime_h

    domain=$(get_domain)
    ip=$(get_ip)
    os=$(source /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}")
    kernel=$(uname -r)
    cores=$(nproc)
    load=$(cut -d' ' -f1-3 /proc/loadavg)
    read -r mem_total mem_used <<< "$(free -m | awk '/Mem:/ {print $2, $3}')"
    mem_pct=$(( mem_total > 0 ? mem_used * 100 / mem_total : 0 ))
    read -r disk_total disk_used disk_pct <<< "$(df -h / | awk 'NR==2 {print $2, $3, $5}')"
    uptime_h=$(uptime -p 2>/dev/null | sed 's/^up //')

    header
    hr
    printf "Domain   : %s\n" "$domain"
    printf "IP VPS   : %s\n" "$ip"
    printf "OS       : %s\n" "$os"
    printf "Kernel   : %s\n" "$kernel"
    printf "CPU Core : %s Core   Load Avg: %s\n" "$cores" "$load"
    printf "Memory   : %sMB / %sMB (%s%%)\n" "$mem_used" "$mem_total" "$mem_pct"
    printf "Disk     : %s / %s (%s)\n" "$disk_used" "$disk_total" "$disk_pct"
    printf "Uptime   : %s\n" "$uptime_h"
    hr
    printf "Xray: %s   Nginx: %s   Dropbear: %s   SSH-WS: %s   Stunnel4: %s   HAProxy: %s\n" \
        "$(svc_status_dot xray)" "$(svc_status_dot nginx)" "$(svc_status_dot dropbear)" \
        "$(svc_status_dot ws-openssh)" "$(svc_status_dot stunnel4)" "$(svc_status_dot haproxy)"
    hr
    printf "VMess: %s   VLess: %s   Trojan: %s   SS: %s   SSHWS: %s\n" \
        "$(xray_count vmess)" "$(xray_count vless)" "$(xray_count trojan)" \
        "$(xray_count ss)" "$(count_ssh)"
    hr
}

nginx_menu() {
    while true; do
        header
        echo -e "${C_BOLD}== NGINX & HAPROXY MANAGEMENT ==${C_RESET}"
        hr
        echo "[1] Restart Nginx"
        echo "[2] Reload Nginx (tanpa putus koneksi)"
        echo "[3] Test konfigurasi Nginx (nginx -t)"
        echo "[4] Lihat error log Nginx (tail -n 40)"
        echo "[5] Restart HAProxy"
        echo "[6] Status HAProxy"
        echo "[7] Lihat HAProxy stats (ringkas)"
        echo "[0] Kembali"
        hr
        read -rp "Pilih menu: " opt
        case "$opt" in
            1) systemctl restart nginx && echo -e "${C_GREEN}Nginx direstart.${C_RESET}"; pause ;;
            2) systemctl reload nginx && echo -e "${C_GREEN}Nginx direload.${C_RESET}"; pause ;;
            3) nginx -t; pause ;;
            4) tail -n 40 /var/log/nginx/error.log; pause ;;
            5) systemctl restart haproxy && echo -e "${C_GREEN}HAProxy direstart.${C_RESET}"; pause ;;
            6) systemctl status haproxy --no-pager; pause ;;
            7)
                if [[ -f /etc/tunnel-suite/haproxy-stats.pass ]]; then
                    curl -s -u "admin:$(cat /etc/tunnel-suite/haproxy-stats.pass)" \
                        "http://127.0.0.1:9000/;csv" | cut -d',' -f1,2,18 | column -t -s,
                else
                    echo "Password stats belum ditemukan."
                fi
                pause
                ;;
            0) break ;;
            *) echo "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

dropbear_menu() {
    while true; do
        header
        echo -e "${C_BOLD}== DROPBEAR MANAGEMENT ==${C_RESET}"
        hr
        echo "[1] Restart Dropbear"
        echo "[2] Ubah port Dropbear (lokal, port 143 default)"
        echo "[3] Status Dropbear"
        echo "[0] Kembali"
        hr
        read -rp "Pilih menu: " opt
        case "$opt" in
            1) systemctl restart dropbear && echo -e "${C_GREEN}Dropbear direstart.${C_RESET}"; pause ;;
            2)
                read -rp "Port baru [143]: " newport
                newport=${newport:-143}
                sed -i "s/^DROPBEAR_PORT=.*/DROPBEAR_PORT=${newport}/" /etc/default/dropbear 2>/dev/null
                sed -i "s/127.0.0.1:[0-9]*/127.0.0.1:${newport}/" /etc/systemd/system/ws-dropbear.service
                systemctl daemon-reload
                systemctl restart dropbear ws-dropbear
                echo -e "${C_GREEN}Port dropbear diubah ke ${newport}.${C_RESET}"
                pause
                ;;
            3) systemctl status dropbear --no-pager; pause ;;
            0) break ;;
            *) echo "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

change_domain() {
    header
    echo -e "${C_BOLD}== Ganti Domain ==${C_RESET}"
    hr
    echo "Domain saat ini: $(get_domain)"
    read -rp "Domain baru (harus sudah mengarah ke IP VPS ini): " newdomain
    [[ -z "$newdomain" ]] && { echo "Dibatalkan."; pause; return; }

    echo "$newdomain" > "$TS_DOMAIN_FILE"
    sed -i "s/server_name .*/server_name ${newdomain};/" /etc/nginx/conf.d/tunnel.conf
    nginx -t && systemctl reload nginx

    if [[ -f /etc/haproxy/haproxy.cfg ]]; then
        sed -i "s/req.ssl_sni -i ssh\.[^[:space:]]*/req.ssl_sni -i ssh.${newdomain}/" /etc/haproxy/haproxy.cfg
        haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl restart haproxy
    fi

    if confirm "Terbitkan ulang sertifikat TLS untuk domain ini sekarang (lewat acme.sh)?"; then
        systemctl stop nginx
        ACME_BIN="/root/.acme.sh/acme.sh"
        if [[ -x "$ACME_BIN" ]]; then
            "$ACME_BIN" --issue -d "$newdomain" --standalone --server letsencrypt \
                && "$ACME_BIN" --install-cert -d "$newdomain" \
                    --key-file       /etc/tunnel-suite/ssl/privkey.pem \
                    --fullchain-file /etc/tunnel-suite/ssl/fullchain.pem \
                    --reloadcmd      "systemctl reload nginx; systemctl restart stunnel4 2>/dev/null"
        else
            echo -e "${C_RED}acme.sh belum terpasang (harusnya sudah dari install.sh).${C_RESET}"
        fi
        systemctl start nginx
    fi
    echo -e "${C_GREEN}Domain diperbarui ke ${newdomain}.${C_RESET}"
    echo -e "${C_YELLOW}Jangan lupa tambahkan DNS A record: ssh.${newdomain} -> IP VPS ini juga.${C_RESET}"
    pause
}

update_script() {
    header
    echo -e "${C_BOLD}== Update Script ==${C_RESET}"
    hr
    echo "Tunnel-suite tidak auto-update dari server pihak ketiga manapun -"
    echo "ini supaya kamu selalu tahu persis kode apa yang berjalan di VPS-mu."
    echo
    echo "Untuk update:"
    echo "  1. Simpan file baru (install.sh, lib/*.sh, dst) ke server ini."
    echo "  2. Jalankan ulang: sudo bash install.sh"
    echo "     (installer aman dijalankan berkali-kali / idempotent untuk config,"
    echo "      akun yang sudah ada tidak akan terhapus)."
    echo
    echo "Jika kamu meng-host sendiri script ini di GitHub repo pribadi, kamu"
    echo "bisa isi URL repo itu di variabel UPDATE_URL pada bagian atas menu.sh"
    echo "supaya opsi ini bisa melakukan 'git pull' otomatis."
    pause
}

uninstall_all() {
    header
    echo -e "${C_RED}${C_BOLD}== UNINSTALL TUNNEL SUITE ==${C_RESET}"
    hr
    echo "Ini akan menghentikan & menghapus: Xray, Nginx site config, ws-openssh,"
    echo "ws-dropbear, stunnel SSH-SSL, HAProxy, serta seluruh akun SSHWS yang dibuat"
    echo "lewat menu ini. Dropbear/Nginx/SSH itu sendiri TIDAK di-uninstall (paket sistem)."
    hr
    if ! confirm "Yakin lanjutkan uninstall?"; then pause; return; fi
    if ! confirm "Sungguh yakin? Tindakan ini TIDAK bisa dibatalkan"; then pause; return; fi

    systemctl disable --now ws-openssh ws-dropbear stunnel4 haproxy 2>/dev/null
    rm -f /etc/systemd/system/ws-openssh.service /etc/systemd/system/ws-dropbear.service
    rm -f /etc/stunnel/ssh-ssl.conf
    rm -f /etc/haproxy/haproxy.cfg
    rm -f /etc/nginx/conf.d/tunnel.conf
    systemctl reload nginx 2>/dev/null

    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge 2>/dev/null

    while IFS='|' read -r user _; do
        [[ -n "$user" ]] && userdel "$user" 2>/dev/null
    done < "$SSH_DB" 2>/dev/null

    rm -rf "$TS_ROOT"
    rm -f /usr/local/bin/menu /usr/local/bin/ws-openssh.py /usr/local/bin/ws-dropbear.py
    rm -rf /usr/local/lib/tunnel-suite

    systemctl daemon-reload
    echo -e "${C_GREEN}Uninstall selesai.${C_RESET}"
    exit 0
}

status_layanan() {
    header
    echo -e "${C_BOLD}== STATUS LAYANAN ==${C_RESET}"
    hr
    for svc in xray nginx dropbear ssh ws-openssh ws-dropbear stunnel4 haproxy; do
        printf "%-14s : %s\n" "$svc" "$(svc_status_dot "$svc")"
    done
    hr
    pause
}

system_info() {
    dashboard
    pause
}

main_menu() {
    while true; do
        dashboard
        echo "MAIN MENU"
        hr
        echo "[1]  SSHWS"
        echo "[2]  VMess WS"
        echo "[3]  VLess WS"
        echo "[4]  Trojan WS/gRPC"
        echo "[5]  Shadowsocks WS/gRPC"
        echo "[6]  Nginx Management"
        echo "[7]  Dropbear Management"
        echo "[8]  Change Domain"
        echo "[9]  Update Script"
        echo -e "${C_RED}[10] Uninstall${C_RESET}"
        echo "[11] Status Layanan"
        echo "[12] System Info"
        echo "[0]  Exit"
        hr
        read -rp "Pilih menu [0-12]: " opt
        case "$opt" in
            1) ssh_menu ;;
            2) xray_protocol_menu vmess ;;
            3) xray_protocol_menu vless ;;
            4) xray_protocol_menu trojan ;;
            5) xray_protocol_menu ss ;;
            6) nginx_menu ;;
            7) dropbear_menu ;;
            8) change_domain ;;
            9) update_script ;;
            10) uninstall_all ;;
            11) status_layanan ;;
            12) system_info ;;
            0) echo "Sampai jumpa!"; exit 0 ;;
            *) echo "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

main_menu
