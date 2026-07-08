#!/bin/bash
# =============================================================================
# ssh_manager.sh - manages the linux system accounts used by SSH-WS / SSH-SSL
#
# One account is shared across all three connection modes (TLS, ntls, SSL)
# because the underlying credential is just a normal system user + password.
# What changes between modes is only which host/port the client app connects
# to (see the README that ships with this suite).
# =============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ssh_create() {
    header
    echo -e "${C_BOLD}== Buat Akun SSH-WS ==${C_RESET}"
    hr
    read -rp "Username       : " username
    if id "$username" &>/dev/null; then
        echo -e "${C_RED}User '$username' sudah ada.${C_RESET}"
        pause; return
    fi
    read -rp "Password (kosongkan utk random): " password
    [[ -z "$password" ]] && password=$(random_password)
    read -rp "Masa aktif (hari) [default 30]: " days
    days=${days:-30}
    exp_date=$(date -d "+${days} days" +%F)

    useradd -e "$exp_date" -s /bin/false -M "$username"
    echo "$username:$password" | chpasswd

    echo "$username|$exp_date" >> "$SSH_DB"

    domain=$(get_domain)
    hr
    echo -e "${C_GREEN}Akun SSH-WS berhasil dibuat!${C_RESET}"
    echo "Domain     : $domain"
    echo "Username   : $username"
    echo "Password   : $password"
    echo "Expired    : $exp_date ($days hari)"
    hr
    echo "Cara sambung (isi di app HTTP Injector / NPV Tunnel / dsb):"
    echo "  Mode TLS   -> host: $domain       port: 443   path: /ssh-ws   (wss)"
    echo "  Mode ntls  -> host: $domain       port: 80    path: /ssh-ws   (ws)"
    echo "  Mode SSL   -> host: $domain       port: 777   (stunnel, langsung ke SSH)"
    echo "  Mode SSL (lewat HAProxy, kalau cuma port 443 yg kebuka di jaringanmu):"
    echo "               host/SNI: ssh.$domain   port: 443"
    echo "  SSH port asli (lokal) : 22"
    hr
    pause
}

ssh_list() {
    header
    echo -e "${C_BOLD}== Daftar Akun SSH-WS ==${C_RESET}"
    hr
    printf "%-20s %-12s %-8s\n" "USERNAME" "EXPIRED" "SISA HARI"
    hr
    if [[ ! -s "$SSH_DB" ]]; then
        echo "(belum ada akun)"
    else
        while IFS='|' read -r user exp; do
            [[ -z "$user" ]] && continue
            left=$(days_left "$exp")
            printf "%-20s %-12s %-8s\n" "$user" "$exp" "$left"
        done < "$SSH_DB"
    fi
    hr
    pause
}

ssh_renew() {
    header
    echo -e "${C_BOLD}== Perpanjang Akun SSH-WS ==${C_RESET}"
    hr
    read -rp "Username: " username
    if ! id "$username" &>/dev/null; then
        echo -e "${C_RED}User tidak ditemukan.${C_RESET}"
        pause; return
    fi
    read -rp "Tambah berapa hari? [30]: " days
    days=${days:-30}
    cur_exp=$(chage -l "$username" | awk -F': ' '/Account expires/{print $2}')
    base_date=$(today)
    if [[ "$cur_exp" != "never" && -n "$cur_exp" ]]; then
        cur_exp_iso=$(date -d "$cur_exp" +%F 2>/dev/null || echo "$(today)")
        [[ $(days_left "$cur_exp_iso") -ge 0 ]] && base_date="$cur_exp_iso"
    fi
    new_exp=$(date -d "${base_date} +${days} days" +%F)
    chage -E "$new_exp" "$username"
    # update db
    grep -v "^${username}|" "$SSH_DB" > "${SSH_DB}.tmp" 2>/dev/null || true
    echo "${username}|${new_exp}" >> "${SSH_DB}.tmp"
    mv "${SSH_DB}.tmp" "$SSH_DB"
    echo -e "${C_GREEN}Diperpanjang sampai $new_exp${C_RESET}"
    pause
}

ssh_delete() {
    header
    echo -e "${C_BOLD}== Hapus Akun SSH-WS ==${C_RESET}"
    hr
    read -rp "Username: " username
    if ! id "$username" &>/dev/null; then
        echo -e "${C_RED}User tidak ditemukan.${C_RESET}"
        pause; return
    fi
    if confirm "Yakin hapus user '$username'?"; then
        pkill -u "$username" 2>/dev/null || true
        userdel "$username" 2>/dev/null
        grep -v "^${username}|" "$SSH_DB" > "${SSH_DB}.tmp" 2>/dev/null || true
        mv "${SSH_DB}.tmp" "$SSH_DB" 2>/dev/null || true
        echo -e "${C_GREEN}User dihapus.${C_RESET}"
    fi
    pause
}

ssh_expiry_cleanup() {
    # Called from cron/timer: remove any user whose expiry has passed
    [[ -f "$SSH_DB" ]] || return
    while IFS='|' read -r user exp; do
        [[ -z "$user" ]] && continue
        if [[ $(days_left "$exp") -lt 0 ]]; then
            userdel "$user" 2>/dev/null
        fi
    done < "$SSH_DB"
    # rebuild db without expired entries
    tmp=$(mktemp)
    while IFS='|' read -r user exp; do
        [[ -z "$user" ]] && continue
        [[ $(days_left "$exp") -ge 0 ]] && echo "${user}|${exp}" >> "$tmp"
    done < "$SSH_DB"
    mv "$tmp" "$SSH_DB"
}

ssh_menu() {
    while true; do
        header
        echo -e "${C_BOLD}== SSHWS MANAGEMENT ==${C_RESET}"
        hr
        echo "[1] Buat Akun"
        echo "[2] List Akun"
        echo "[3] Perpanjang Akun"
        echo "[4] Hapus Akun"
        echo "[0] Kembali"
        hr
        read -rp "Pilih menu: " opt
        case "$opt" in
            1) ssh_create ;;
            2) ssh_list ;;
            3) ssh_renew ;;
            4) ssh_delete ;;
            0) break ;;
            *) echo "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

# allow calling this file directly, e.g. `ssh_manager.sh cleanup`
if [[ "${1:-}" == "cleanup" ]]; then
    ssh_expiry_cleanup
fi
