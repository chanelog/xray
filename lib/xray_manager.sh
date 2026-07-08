#!/bin/bash
# =============================================================================
# xray_manager.sh - manages Xray-core client accounts
#   VMess WS, VLess WS               -> WS only
#   Trojan WS/gRPC, Shadowsocks WS/gRPC -> user picks transport at creation
#
# Expiry is stored in each client's "email" field as "username|YYYY-MM-DD"
# since Xray itself has no native expiry concept.
# =============================================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

declare -A XR_KEYFIELD=( [vmess]="id" [vless]="id" [trojan]="password" [ss]="password" )
declare -A XR_LABEL=( [vmess]="VMess WS" [vless]="VLess WS" [trojan]="Trojan WS/gRPC" [ss]="Shadowsocks WS/gRPC" )
declare -A XR_PATH=( [vmess-ws]="/vmess" [vless-ws]="/vless" [trojan-ws]="/trojan-ws" [ss-ws]="/ss-ws" )
SS_METHOD="aes-128-gcm"

get_uuid() { command -v uuidgen >/dev/null 2>&1 && uuidgen || cat /proc/sys/kernel/random/uuid; }

xray_reload() { systemctl restart xray 2>/dev/null; }

xr_supports_grpc() { [[ "$1" == "trojan" || "$1" == "ss" ]]; }

xr_tag_for() {
    # $1 proto $2 transport(ws|grpc) -> echoes the xray inbound tag
    local proto="$1" transport="$2"
    case "$proto" in
        vmess) echo "vmess-ws" ;;
        vless) echo "vless-ws" ;;
        trojan) [[ "$transport" == "grpc" ]] && echo "trojan-grpc" || echo "trojan-ws" ;;
        ss)     [[ "$transport" == "grpc" ]] && echo "ss-grpc"     || echo "ss-ws" ;;
    esac
}

xr_all_tags() {
    # $1 proto -> echoes space-separated list of every tag used by that proto
    case "$1" in
        vmess) echo "vmess-ws" ;;
        vless) echo "vless-ws" ;;
        trojan) echo "trojan-ws trojan-grpc" ;;
        ss) echo "ss-ws ss-grpc" ;;
    esac
}

xr_transport_of_tag() {
    [[ "$1" == *-grpc ]] && echo "gRPC" || echo "WS"
}

xray_get_field() {
    # $1 tag $2 username $3 field -> existing value or empty
    local tag="$1" user="$2" field="$3"
    jq -r --arg tag "$tag" --arg user "$user" --arg field "$field" \
        '.inbounds[] | select(.tag==$tag) | .settings.clients[]? | select((.email//"")|startswith($user+"|")) | .[$field] // empty' \
        "$XRAY_CONFIG" 2>/dev/null | head -n1
}

xray_find_tag_for_user() {
    # $1 proto $2 username -> echoes the tag the user is currently in (first match), empty if none
    local proto="$1" user="$2" field="${XR_KEYFIELD[$1]}"
    for tag in $(xr_all_tags "$proto"); do
        local v
        v=$(xray_get_field "$tag" "$user" "$field")
        if [[ -n "$v" ]]; then echo "$tag"; return; fi
    done
}

xray_remove_client() {
    local tag="$1" user="$2"
    jq --arg tag "$tag" --arg user "$user" \
        '(.inbounds[] | select(.tag==$tag) | .settings.clients) |= map(select(((.email // "") | startswith($user+"|")) | not))' \
        "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp" && mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
}

xray_insert_client() {
    # $1 proto $2 tag $3 keyval $4 email
    local proto="$1" tag="$2" keyval="$3" email="$4"
    if [[ "$proto" == "ss" ]]; then
        jq --arg tag "$tag" --arg pass "$keyval" --arg email "$email" --arg method "$SS_METHOD" \
            '(.inbounds[] | select(.tag==$tag) | .settings.clients) += [{"method":$method,"password":$pass,"email":$email}]' \
            "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp" && mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
    else
        local field="${XR_KEYFIELD[$proto]}"
        jq --arg tag "$tag" --arg val "$keyval" --arg email "$email" --arg field "$field" \
            '(.inbounds[] | select(.tag==$tag) | .settings.clients) += [{($field):$val,"email":$email}]' \
            "$XRAY_CONFIG" > "${XRAY_CONFIG}.tmp" && mv "${XRAY_CONFIG}.tmp" "$XRAY_CONFIG"
    fi
}

build_link() {
    # $1 proto $2 tag $3 keyval $4 username $5 domain
    local proto="$1" tag="$2" keyval="$3" username="$4" domain="$5"
    local transport; transport=$(xr_transport_of_tag "$tag")

    case "$proto" in
        vmess)
            local json
            json=$(jq -n --arg v "2" --arg ps "$username" --arg add "$domain" --arg port "443" \
                --arg id "$keyval" --arg aid "0" --arg net "ws" --arg type "none" \
                --arg host "$domain" --arg path "${XR_PATH[$tag]}" --arg tls "tls" --arg sni "$domain" \
                '{v:$v,ps:$ps,add:$add,port:($port|tonumber),id:$id,aid:$aid,net:$net,type:$type,host:$host,path:$path,tls:$tls,sni:$sni}')
            echo "vmess://$(echo -n "$json" | base64 -w0)"
            ;;
        vless)
            local path_enc; path_enc=$(printf '%s' "${XR_PATH[$tag]}" | sed 's#/#%2F#')
            echo "vless://${keyval}@${domain}:443?encryption=none&security=tls&type=ws&host=${domain}&path=${path_enc}&sni=${domain}#${username}"
            ;;
        trojan)
            if [[ "$transport" == "gRPC" ]]; then
                echo "trojan://${keyval}@${domain}:443?security=tls&type=grpc&serviceName=${tag}&sni=${domain}#${username}"
            else
                local path_enc; path_enc=$(printf '%s' "${XR_PATH[$tag]}" | sed 's#/#%2F#')
                echo "trojan://${keyval}@${domain}:443?security=tls&type=ws&host=${domain}&path=${path_enc}&sni=${domain}#${username}"
            fi
            ;;
        ss)
            local userinfo; userinfo=$(echo -n "${SS_METHOD}:${keyval}" | base64 -w0)
            if [[ "$transport" == "gRPC" ]]; then
                echo "ss://${userinfo}@${domain}:443?type=grpc&serviceName=${tag}#${username}  (note: butuh client kompatibel Xray, mis. NekoBox/v2rayNG)"
            else
                local path_enc; path_enc=$(printf '%s' "${XR_PATH[$tag]}" | sed 's#/#%2F#')
                echo "ss://${userinfo}@${domain}:443?type=ws&host=${domain}&path=${path_enc}#${username}  (note: butuh client kompatibel Xray, mis. NekoBox/v2rayNG)"
            fi
            ;;
    esac
}

xray_ask_transport() {
    # $1 proto -> echoes "ws" or "grpc" (prompts only if the proto supports both)
    local proto="$1"
    if ! xr_supports_grpc "$proto"; then echo "ws"; return; fi
    echo "Pilih transport:" >&2
    echo "  [1] WebSocket (WS)   - default" >&2
    echo "  [2] gRPC" >&2
    read -rp "Transport [1]: " t
    [[ "$t" == "2" ]] && echo "grpc" || echo "ws"
}

xray_add() {
    local proto="$1"
    header
    echo -e "${C_BOLD}== Buat Akun ${XR_LABEL[$proto]} ==${C_RESET}"
    hr
    read -rp "Username/remark : " username

    local existing_tag
    existing_tag=$(xray_find_tag_for_user "$proto" "$username")
    if [[ -n "$existing_tag" ]]; then
        echo -e "${C_RED}Username sudah dipakai untuk protokol ini (transport: $(xr_transport_of_tag "$existing_tag")).${C_RESET}"
        pause; return
    fi

    read -rp "Masa aktif (hari) [30]: " days
    days=${days:-30}
    exp=$(date -d "+${days} days" +%F)
    email="${username}|${exp}"

    local transport tag
    transport=$(xray_ask_transport "$proto")
    tag=$(xr_tag_for "$proto" "$transport")

    if [[ "$proto" == "vmess" || "$proto" == "vless" ]]; then
        keyval=$(get_uuid)
    else
        keyval=$(random_password)
    fi

    xray_insert_client "$proto" "$tag" "$keyval" "$email"
    xray_reload
    sleep 1

    domain=$(get_domain)
    link=$(build_link "$proto" "$tag" "$keyval" "$username" "$domain")

    hr
    echo -e "${C_GREEN}Akun ${XR_LABEL[$proto]} berhasil dibuat!${C_RESET}"
    echo "Domain     : $domain"
    echo "Username   : $username"
    echo "Transport  : $(xr_transport_of_tag "$tag")"
    echo "${XR_KEYFIELD[$proto]^^}       : $keyval"
    [[ "$proto" == "ss" ]] && echo "Method     : $SS_METHOD"
    echo "Expired    : $exp ($days hari)"
    hr
    echo "Link (import ke client):"
    echo "$link"
    hr
    pause
}

xray_list() {
    local proto="$1"
    header
    echo -e "${C_BOLD}== Daftar Akun ${XR_LABEL[$proto]} ==${C_RESET}"
    hr
    printf "%-18s %-6s %-12s %-8s\n" "USERNAME" "TRANS" "EXPIRED" "SISA HARI"
    hr
    local any=0
    for tag in $(xr_all_tags "$proto"); do
        rows=$(jq -r --arg tag "$tag" \
            '.inbounds[] | select(.tag==$tag) | .settings.clients[]? | (.email // "-")' \
            "$XRAY_CONFIG" 2>/dev/null)
        [[ -z "$rows" ]] && continue
        while IFS= read -r email; do
            [[ -z "$email" || "$email" == "-" ]] && continue
            any=1
            user="${email%%|*}"
            exp="${email##*|}"
            left=$(days_left "$exp")
            printf "%-18s %-6s %-12s %-8s\n" "$user" "$(xr_transport_of_tag "$tag")" "$exp" "$left"
        done <<< "$rows"
    done
    [[ "$any" == "0" ]] && echo "(belum ada akun)"
    hr
    pause
}

xray_renew() {
    local proto="$1"
    header
    echo -e "${C_BOLD}== Perpanjang Akun ${XR_LABEL[$proto]} ==${C_RESET}"
    hr
    read -rp "Username: " username
    local field="${XR_KEYFIELD[$proto]}"
    local tag keyval cur_exp
    tag=$(xray_find_tag_for_user "$proto" "$username")
    if [[ -z "$tag" ]]; then
        echo -e "${C_RED}User tidak ditemukan.${C_RESET}"
        pause; return
    fi
    keyval=$(xray_get_field "$tag" "$username" "$field")
    cur_exp=$(xray_get_field "$tag" "$username" "email" | awk -F'|' '{print $2}')

    read -rp "Tambah berapa hari? [30]: " days
    days=${days:-30}
    base_date=$(today)
    [[ -n "$cur_exp" && $(days_left "$cur_exp") -ge 0 ]] && base_date="$cur_exp"
    new_exp=$(date -d "${base_date} +${days} days" +%F)

    xray_remove_client "$tag" "$username"
    xray_insert_client "$proto" "$tag" "$keyval" "${username}|${new_exp}"
    xray_reload
    echo -e "${C_GREEN}Diperpanjang sampai $new_exp (kredensial & transport tidak berubah).${C_RESET}"
    pause
}

xray_delete() {
    local proto="$1"
    header
    echo -e "${C_BOLD}== Hapus Akun ${XR_LABEL[$proto]} ==${C_RESET}"
    hr
    read -rp "Username: " username
    local tag
    tag=$(xray_find_tag_for_user "$proto" "$username")
    if [[ -z "$tag" ]]; then
        echo -e "${C_RED}User tidak ditemukan.${C_RESET}"
        pause; return
    fi
    if confirm "Yakin hapus '$username' dari ${XR_LABEL[$proto]} ($(xr_transport_of_tag "$tag"))?"; then
        xray_remove_client "$tag" "$username"
        xray_reload
        echo -e "${C_GREEN}Akun dihapus.${C_RESET}"
    fi
    pause
}

xray_count() {
    # $1 proto -> total accounts across all its tags (for dashboard)
    local proto="$1" total=0
    for tag in $(xr_all_tags "$proto"); do
        n=$(jq -r --arg tag "$tag" '[.inbounds[] | select(.tag==$tag) | .settings.clients[]?] | length' \
            "$XRAY_CONFIG" 2>/dev/null)
        total=$(( total + ${n:-0} ))
    done
    echo "$total"
}

xray_expiry_cleanup() {
    for proto in vmess vless trojan ss; do
        for tag in $(xr_all_tags "$proto"); do
            rows=$(jq -r --arg tag "$tag" '.inbounds[] | select(.tag==$tag) | .settings.clients[]? | (.email // "-")' "$XRAY_CONFIG" 2>/dev/null)
            while IFS= read -r email; do
                [[ -z "$email" || "$email" == "-" ]] && continue
                user="${email%%|*}"
                exp="${email##*|}"
                if [[ $(days_left "$exp") -lt 0 ]]; then
                    xray_remove_client "$tag" "$user"
                fi
            done <<< "$rows"
        done
    done
    xray_reload
}

xray_protocol_menu() {
    local proto="$1"
    while true; do
        header
        echo -e "${C_BOLD}== ${XR_LABEL[$proto]^^} MANAGEMENT ==${C_RESET}"
        hr
        echo "[1] Buat Akun"
        echo "[2] List Akun"
        echo "[3] Perpanjang Akun"
        echo "[4] Hapus Akun"
        echo "[0] Kembali"
        hr
        read -rp "Pilih menu: " opt
        case "$opt" in
            1) xray_add "$proto" ;;
            2) xray_list "$proto" ;;
            3) xray_renew "$proto" ;;
            4) xray_delete "$proto" ;;
            0) break ;;
            *) echo "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

if [[ "${1:-}" == "cleanup" ]]; then
    xray_expiry_cleanup
fi
