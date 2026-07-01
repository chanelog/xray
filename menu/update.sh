#!/bin/bash
# ============================================================
#   CHANELOG VPN SCRIPT - UPDATE SCRIPT
#   Redownload semua file menu & fitur terbaru dari GitHub,
#   tanpa mengubah domain, database akun, atau service.
# ============================================================

SCRIPT_DIR="/etc/vpn-script"
source "$SCRIPT_DIR/lib.sh"

RAW="https://raw.githubusercontent.com/chanelog/xray/main"
BIN_DIR="/usr/local/bin"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# File-file yang diupdate. Daftar ini HARUS sinkron dengan
# install_script_files() di install.sh — kalau ada menu baru
# ditambahkan di install.sh, tambahkan juga di sini.
ROOT_FILES=(menu.sh lib.sh)
MENU_FILES=(vmess vless nginx dropbear sysinfo changedomain sshws update uninstall)

update_menu() {
  clear
  echo -e "${CYAN}$LINE${NC}"
  echo -e "${WHITE}              ⚡  UPDATE SCRIPT  ⚡${NC}"
  echo -e "${CYAN}$LINE${NC}"
  echo ""
  echo -e "  ${WHITE}Yang akan diupdate:${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}✓${NC}  menu.sh, lib.sh"
  echo -e "  ${GREEN}✓${NC}  Semua file di menu/ (vmess, vless, nginx, dropbear,"
  echo -e "     sysinfo, changedomain, sshws, update, uninstall)"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -e "  ${WHITE}Yang TIDAK berubah:${NC}"
  echo -e "  ${CYAN}$LINE${NC}"
  echo -e "  ${GREEN}✓${NC}  Domain aktif"
  echo -e "  ${GREEN}✓${NC}  Database akun VMess / VLess / SSH WS"
  echo -e "  ${GREEN}✓${NC}  Konfigurasi Nginx, SSL, service yang berjalan"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${YELLOW}Lanjutkan update? [Y/n]${NC}: "
  read -r confirm
  [[ "$confirm" =~ ^[Nn]$ ]] && { echo -e "\n  ${YELLOW}Update dibatalkan${NC}"; sleep 1; bash $SCRIPT_DIR/menu.sh; return; }

  echo ""
  echo -e "  ${CYAN}$LINE${NC}"
  local ok=true
  local tmp_dir=$(mktemp -d)

  echo -e "  ${CYAN}[*]${NC} Mendownload file terbaru ke lokasi sementara..."
  echo ""

  for f in "${ROOT_FILES[@]}"; do
    echo -ne "    Downloading $f..."
    wget -q --timeout=30 "$RAW/$f" -O "$tmp_dir/$f"
    if [[ $? -ne 0 ]] || [[ ! -s "$tmp_dir/$f" ]]; then
      echo -e " ${RED}GAGAL${NC}"
      ok=false
    else
      echo -e " ${GREEN}OK${NC}"
    fi
  done

  mkdir -p "$tmp_dir/menu"
  for f in "${MENU_FILES[@]}"; do
    echo -ne "    Downloading menu/${f}.sh..."
    wget -q --timeout=30 "$RAW/menu/${f}.sh" -O "$tmp_dir/menu/${f}.sh"
    if [[ $? -ne 0 ]] || [[ ! -s "$tmp_dir/menu/${f}.sh" ]]; then
      echo -e " ${RED}GAGAL${NC}"
      ok=false
    else
      echo -e " ${GREEN}OK${NC}"
    fi
  done

  echo ""
  if [[ "$ok" == "false" ]]; then
    echo -e "  ${RED}[ERROR]${NC} Beberapa file gagal didownload. Update dibatalkan,"
    echo -e "  ${RED}[ERROR]${NC} file lama tetap dipakai (belum ditimpa)."
    rm -rf "$tmp_dir"
    echo -e "  ${CYAN}$LINE${NC}"
    echo -ne "\n  ${DIM}Tekan Enter untuk kembali...${NC}"; read -r
    bash $SCRIPT_DIR/menu.sh
    return
  fi

  echo -e "  ${CYAN}[*]${NC} Semua file berhasil didownload, menerapkan update..."

  for f in "${ROOT_FILES[@]}"; do
    cp -f "$tmp_dir/$f" "$SCRIPT_DIR/$f"
  done
  for f in "${MENU_FILES[@]}"; do
    cp -f "$tmp_dir/menu/${f}.sh" "$SCRIPT_DIR/menu/${f}.sh"
  done

  rm -rf "$tmp_dir"

  chmod +x $SCRIPT_DIR/*.sh
  chmod +x $SCRIPT_DIR/menu/*.sh
  ln -sf $SCRIPT_DIR/menu.sh $BIN_DIR/vpn
  chmod +x $BIN_DIR/vpn

  echo -e "  ${GREEN}[OK]${NC} Script berhasil diupdate ke versi terbaru!"
  echo -e "  ${CYAN}$LINE${NC}"
  echo ""
  echo -ne "  ${DIM}Tekan Enter untuk kembali ke menu...${NC}"; read -r
  bash $SCRIPT_DIR/menu.sh
}

update_menu
