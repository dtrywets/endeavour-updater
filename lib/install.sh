# Installation / Deinstallation

: "${UPDATER_ROOT:?UPDATER_ROOT muss gesetzt sein}"
: "${BIN_NAME:=endeavour-updater}"
: "${SHARE_DIR:=$HOME/.local/share/endeavour-updater}"
: "${BIN_DIR:=$HOME/.local/bin}"
: "${BIN_PATH:=$BIN_DIR/$BIN_NAME}"

install_is_installed() {
  [[ -f "$CONFIG_FILE" && -x "$BIN_PATH" ]]
}

install_load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
  fi
}

install_write_config() {
  mkdir -p "$CONFIG_DIR"
  maintain_orphan_protect_ensure_template
  cat >"$CONFIG_FILE" <<EOF
# endeavour-updater – generiert $(date -Iseconds)
INSTALL_ROOT='$SHARE_DIR'
BIN_PATH='$BIN_PATH'
SOURCE_REPO='$UPDATER_ROOT'
INSTALLED_AT='$(date -Iseconds)'
VERSION=1
CRON_ENABLED=1
EOF
}

install_copy_tree() {
  mkdir -p "$SHARE_DIR"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude='.git' \
      "$UPDATER_ROOT/" "$SHARE_DIR/"
  else
    rm -rf "${SHARE_DIR:?}"/*
    cp -a "$UPDATER_ROOT/." "$SHARE_DIR/"
  fi
  chmod +x "$SHARE_DIR/endeavour-updater"
}

install_link_bin() {
  mkdir -p "$BIN_DIR"
  ln -sf "$SHARE_DIR/endeavour-updater" "$BIN_PATH"
}

install_deps_hint() {
  local missing=()
  have_cmd reflector || missing+=(reflector)
  have_cmd paccache || missing+=(pacman-contrib)
  if [[ "${#missing[@]}" -gt 0 ]]; then
    warn "Empfohlene Pakete für Wartung: ${missing[*]}"
    warn "Installieren: sudo pacman -S --needed ${missing[*]}"
  fi
}

install_try_cron() {
  if [[ "${WITH_CRON:-1}" -ne 1 ]]; then
    log "Cronjobs übersprungen (--no-cron)."
    return 0
  fi
  if cron_install_all; then
    return 0
  fi
  cron_set_config_enabled 0
  warn "Cronjobs nicht eingerichtet – ggf. --cron-install nachholen."
  return 1
}

install_do() {
  log "Installation nach $SHARE_DIR …"
  [[ "$DRY_RUN" -eq 1 ]] && { log "[dry-run] install"; return 0; }
  install_copy_tree
  UPDATER_ROOT="$SHARE_DIR"
  install_link_bin
  install_write_config
  install_deps_hint
  log "Installiert: $BIN_PATH"
  if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    warn "$BIN_DIR ist nicht in PATH. In ~/.bashrc: export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
}

install_uninstall() {
  log "Deinstallation …"
  [[ "$DRY_RUN" -eq 1 ]] && { log "[dry-run] uninstall"; return 0; }
  cron_remove_all 2>/dev/null || true
  rm -f "$BIN_PATH"
  rm -rf "$SHARE_DIR"
  rm -f "$CONFIG_FILE"
  rmdir "$CONFIG_DIR" 2>/dev/null || true
  log "endeavour-updater entfernt."
}

install_status() {
  if install_is_installed; then
    install_load_config
    log "Status: installiert"
    log "  Binär:  $BIN_PATH"
    log "  Daten:  $INSTALL_ROOT"
    log "  Seit:   ${INSTALLED_AT:-unbekannt}"
    cron_show_status
  else
    log "Status: nicht installiert (Ausführung aus: $UPDATER_ROOT)"
  fi
}

install_ensure() {
  if install_is_installed; then
    install_load_config
    UPDATER_ROOT="$INSTALL_ROOT"
    return 0
  fi
  if [[ "$NONINTERACTIVE" -eq 1 ]]; then
    warn "Nicht installiert – Cron/Automatik übersprungen oder mit --install ausführen."
    return 1
  fi
  if ! is_tty; then
    die "Nicht installiert. Bitte: endeavour-updater --install"
  fi
  echo
  echo "endeavour-updater ist noch nicht installiert."
  echo "  Ziel: $BIN_PATH"
  echo "  Daten: $SHARE_DIR"
  echo
  if confirm "Jetzt installieren (inkl. empfohlener Cronjobs)?"; then
    install_do
    install_try_cron || true
    return 0
  fi
  if confirm "Nur installieren, ohne Cronjobs?"; then
    install_do
    return 0
  fi
  log "Weiter ohne Installation (aus dem Projektordner)."
  return 0
}

install_upgrade() {
  if ! install_is_installed; then
    install_do
    return
  fi
  install_load_config
  log "Aktualisiere Installation aus $UPDATER_ROOT …"
  local saved_root="$UPDATER_ROOT"
  UPDATER_ROOT="$saved_root"
  install_copy_tree
  install_link_bin
  install_write_config
  UPDATER_ROOT="$SHARE_DIR"
  log "Installation aktualisiert."
}
