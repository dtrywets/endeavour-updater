# Cronjob-Verwaltung (empfohlene Zyklen laut EOS-Wartungsguide)
# Benötigt: Paket cronie + Dienst cronie.service

CRON_MARKER_BEGIN='# endeavour-updater BEGIN'
CRON_MARKER_END='# endeavour-updater END'
CRON_USER="${CRON_USER:-$USER}"
CRON_PKG_HINT='cronie'
CRON_SERVICE='cronie.service'
: "${WITH_CRONIE:=1}"

cron_have_crontab() {
  have_cmd crontab
}

cron_missing_hint() {
  warn "crontab nicht gefunden – Paket $CRON_PKG_HINT fehlt oder ist nicht im PATH."
  if [[ "${WITH_CRONIE:-1}" -eq 1 ]]; then
    warn "Automatische Installation fehlgeschlagen oder unterdrückt (--no-cronie)."
  else
    warn "Installieren: sudo pacman -S --needed $CRON_PKG_HINT"
    warn "  sudo systemctl enable --now $CRON_SERVICE"
  fi
  warn "Danach: endeavour-updater --cron-install"
}

# Paket cronie + Dienst (Standard bei --install / --cron-install)
cron_install_cronie() {
  if [[ "${WITH_CRONIE:-1}" -ne 1 ]]; then
    log "Installation von $CRON_PKG_HINT übersprungen (--no-cronie)."
    return 0
  fi
  if cron_have_crontab; then
    log "$CRON_PKG_HINT/crontab ist bereits vorhanden."
    cron_enable_service
    return 0
  fi
  if ! have_cmd pacman; then
    warn "pacman nicht verfügbar – $CRON_PKG_HINT kann nicht installiert werden."
    return 1
  fi
  log "Installiere $CRON_PKG_HINT (liefert crontab) …"
  [[ "$DRY_RUN" -eq 1 ]] && { log "[dry-run] pacman -S $CRON_PKG_HINT"; return 0; }
  local pac=(pacman -S --needed)
  [[ "$NONINTERACTIVE" -eq 1 || "$YES" -eq 1 ]] && pac+=(--noconfirm)
  if ! run_root "${pac[@]}" "$CRON_PKG_HINT"; then
    warn "Installation von $CRON_PKG_HINT fehlgeschlagen."
    return 1
  fi
  if ! cron_have_crontab; then
    warn "Paket installiert, aber crontab noch nicht im PATH – neue Shell oder Reboot."
    hash -r 2>/dev/null || true
  fi
  cron_enable_service
  log "$CRON_PKG_HINT installiert."
}

cron_enable_service() {
  have_cmd systemctl || return 0
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  if systemctl list-unit-files "$CRON_SERVICE" &>/dev/null; then
    run_root systemctl enable --now "$CRON_SERVICE" 2>/dev/null || \
      warn "Dienst $CRON_SERVICE: sudo systemctl enable --now $CRON_SERVICE"
  fi
}

cron_ensure_cronie() {
  cron_have_crontab && return 0
  cron_install_cronie
}

cron_require_crontab() {
  if cron_have_crontab; then
    return 0
  fi
  cron_missing_hint
  return 1
}

cron_block_content() {
  local bin="$UPDATER_ROOT/endeavour-updater"
  if install_is_installed; then
    install_load_config
    bin="${BIN_PATH:-$bin}"
  fi
  [[ -x "$bin" ]] || bin="$UPDATER_ROOT/endeavour-updater"
  cat <<EOF
$CRON_MARKER_BEGIN
# Wöchentliches Paket-Update (Guide: regelmäßig, mind. alle 1–2 Wochen)
0 6 * * 0 $CRON_USER $bin --cron update >> $LOG_DIR/cron-update.log 2>&1
# Monatliche Wartung: Spiegel, vollständiger Sync, Journal/Cache (Guide: 1–2 Monate)
0 7 1 * * $CRON_USER $bin --cron monthly >> $LOG_DIR/cron-monthly.log 2>&1
$CRON_MARKER_END
EOF
}

cron_get_user_crontab() {
  cron_have_crontab || return 0
  crontab -l -u "$CRON_USER" 2>/dev/null || true
}

cron_apply_crontab() {
  local file="$1"
  if ! cron_have_crontab; then
    cron_missing_hint
    return 1
  fi
  crontab -u "$CRON_USER" "$file"
}

cron_remove_crontab() {
  cron_have_crontab || return 0
  crontab -u "$CRON_USER" -r 2>/dev/null || true
}

cron_has_block() {
  cron_get_user_crontab | grep -Fq "$CRON_MARKER_BEGIN"
}

cron_set_config_enabled() {
  local val="$1"
  [[ -f "$CONFIG_FILE" ]] || return 0
  if grep -q '^CRON_ENABLED=' "$CONFIG_FILE" 2>/dev/null; then
    sed -i "s/^CRON_ENABLED=.*/CRON_ENABLED=$val/" "$CONFIG_FILE"
  fi
}

cron_install_all() {
  mkdir -p "$LOG_DIR"
  cron_ensure_cronie || return 1
  cron_require_crontab || return 1

  if cron_has_block; then
    log "Cronjobs bereits vorhanden – neu schreiben."
    cron_remove_all || true
  fi
  [[ "$DRY_RUN" -eq 1 ]] && { cron_block_content; return 0; }

  local tmp
  tmp="$(mktemp)"
  cron_get_user_crontab | grep -Fv "$CRON_MARKER_BEGIN" | grep -Fv "$CRON_MARKER_END" \
    | grep -Fv 'endeavour-updater' >"$tmp" || true
  {
    cat "$tmp"
    echo
    cron_block_content
  } >"${tmp}.new"
  cron_apply_crontab "${tmp}.new" || { rm -f "$tmp" "${tmp}.new"; return 1; }
  rm -f "$tmp" "${tmp}.new"

  cron_set_config_enabled 1
  log "Cronjobs für Benutzer $CRON_USER installiert."
  cron_show_status
}

cron_remove_all() {
  if ! cron_have_crontab; then
    log "crontab nicht installiert – nichts zu entfernen."
    cron_set_config_enabled 0
    return 0
  fi
  if ! cron_has_block; then
    log "Keine endeavour-updater Cronjobs gefunden."
    cron_set_config_enabled 0
    return 0
  fi
  [[ "$DRY_RUN" -eq 1 ]] && { log "[dry-run] cron entfernen"; return 0; }

  local tmp
  tmp="$(mktemp)"
  cron_get_user_crontab | awk -v b="$CRON_MARKER_BEGIN" -v e="$CRON_MARKER_END" '
    $0 == b { skip=1; next }
    $0 == e { skip=0; next }
    !skip && $0 !~ /endeavour-updater/ { print }
  ' >"$tmp"
  if [[ -s "$tmp" ]]; then
    cron_apply_crontab "$tmp" || { rm -f "$tmp"; return 1; }
  else
    cron_remove_crontab
  fi
  rm -f "$tmp"
  cron_set_config_enabled 0
  log "Cronjobs entfernt."
}

cron_show_status() {
  echo
  echo "── Cronjobs ($CRON_USER) ──"
  if ! cron_have_crontab; then
    echo "  crontab fehlt – Paket: $CRON_PKG_HINT (siehe --cron-install)"
    return 0
  fi
  if cron_has_block; then
    cron_get_user_crontab | awk -v b="$CRON_MARKER_BEGIN" -v e="$CRON_MARKER_END" '
      $0 == b { show=1 }
      show { print }
      $0 == e { show=0 }
    '
    echo "  Logs: $LOG_DIR"
  else
    echo "  (keine endeavour-updater Einträge)"
  fi
}

cron_run_task() {
  local task="$1"
  mkdir -p "$LOG_DIR"
  NONINTERACTIVE=1
  YES=1
  case "$task" in
    update)   maintain_cron_update ;;
    monthly)  maintain_cron_monthly ;;
    mirrors)  maintain_cron_mirrors ;;
    clean)    maintain_cron_clean ;;
    *)
      die "Unbekannte Cron-Aufgabe: $task (update|monthly|mirrors|clean)"
      ;;
  esac
}
