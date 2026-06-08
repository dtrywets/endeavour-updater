# Wartungsaktionen (Guide: EndeavourOS Forum #25184)

maintain_update_packages() {
  local full_sync="${1:-0}"
  local sync=(-Syu)
  [[ "$full_sync" -eq 1 ]] && sync=(-Syyu)

  if have_cmd yay; then
    aur_sources_prepare_package_updates
    local yay_flags=("${sync[@]}")
    [[ "$NONINTERACTIVE" -eq 1 || "$YES" -eq 1 ]] && yay_flags+=(--noconfirm)
    yay_flags+=("${AUR_SOURCES_EXTRA_IGNORE[@]}")
    if [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" ]]; then
      run sudo -u "$SUDO_USER" -H -- yay "${yay_flags[@]}"
      aur_sources_run_post_update
      return
    fi
    [[ "$EUID" -eq 0 ]] && warn "yay als root – normaler Benutzer bevorzugt."
    run yay "${yay_flags[@]}"
    aur_sources_run_post_update
    return
  fi

  local pac_flags=("${sync[@]}")
  [[ "$NONINTERACTIVE" -eq 1 || "$YES" -eq 1 ]] && pac_flags+=(--noconfirm)
  run_root pacman "${pac_flags[@]}"
}

maintain_update_mirrors_arch() {
  have_cmd reflector || { warn "reflector fehlt (pacman -S reflector) – überspringe."; return 0; }
  local extra=()
  if [[ -r /etc/pacman.d/mirrorlist ]] && grep -q '^Country' /etc/pacman.d/mirrorlist 2>/dev/null; then
    extra+=(--country "$(grep '^Country' /etc/pacman.d/mirrorlist | head -1 | awk '{print $2}')")
  fi
  run_root reflector --protocol https --verbose --latest 25 --sort rate \
    "${extra[@]}" --save /etc/pacman.d/mirrorlist
}

maintain_update_mirrors_eos() {
  if have_cmd eos-rankmirrors; then
    run_root eos-rankmirrors --verbose
  else
    log "eos-rankmirrors nicht vorhanden – überspringe."
  fi
}

maintain_mirrors_all() {
  maintain_update_mirrors_arch
  maintain_update_mirrors_eos
}

maintain_clean_journal() {
  run_root journalctl --vacuum-time=4weeks
}

maintain_clean_pacman_cache() {
  have_cmd paccache || die "paccache fehlt (Paket: pacman-contrib)"
  run_root paccache -r
  run_root paccache -ruk0
}

maintain_clean_all() {
  maintain_clean_journal
  maintain_clean_pacman_cache
}

maintain_list_pacnew_pacsave() {
  find /etc -maxdepth 3 \( -name '*.pacnew' -o -name '*.pacsave' \) 2>/dev/null | sort -u
}

maintain_check_pacnew_reminder() {
  local files
  files="$(maintain_list_pacnew_pacsave || true)"
  [[ -z "$files" ]] && return 0
  warn ".pacnew/.pacsave vorhanden – Konfiguration prüfen:"
  echo "$files" | sed 's/^/  /'
  warn "Menüpunkt pacdiff oder: endeavour-updater --pacdiff"
}

maintain_run_pacdiff() {
  have_cmd pacdiff || die "pacdiff fehlt (pacman-contrib)"
  local diffprog="${DIFFPROG:-meld}"
  if ! have_cmd "$diffprog" && [[ "$diffprog" == meld ]]; then
    die "meld fehlt (pacman -S meld) oder DIFFPROG setzen"
  fi
  export DIFFPROG
  log "pacdiff (interaktiv), DIFFPROG=$DIFFPROG"
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  as_root pacdiff -s
}

maintain_list_orphans() {
  pacman -Qdtq 2>/dev/null || true
}

maintain_remove_orphans() {
  local auto="${1:-0}"
  mapfile -t orphans < <(maintain_list_orphans)
  if [[ "${#orphans[@]}" -eq 0 ]]; then
    log "Keine Waisen-Pakete."
    return 0
  fi
  log "Waisen (${#orphans[@]}):"
  printf '  %s\n' "${orphans[@]}"
  if [[ "$auto" -eq 1 && "$NONINTERACTIVE" -eq 1 ]]; then
    warn "Cron: Waisen werden nicht automatisch entfernt (Sicherheit). Nur Protokoll."
    return 0
  fi
  if ! confirm "Waisen mit pacman -Rns entfernen?"; then
    log "Abgebrochen."
    return 0
  fi
  local rm_flags=(-Rns)
  [[ "$YES" -eq 1 ]] && rm_flags+=(--noconfirm)
  run_root pacman "${rm_flags[@]}" "${orphans[@]}"
}

# Cron-/CLI-Profile
maintain_cron_update() {
  log "Cron: Paket-Update"
  maintain_update_packages 0
  maintain_check_pacnew_reminder
}

maintain_cron_monthly() {
  log "Cron: monatliche Wartung (Spiegel + Sync/Update + Aufräumen)"
  maintain_mirrors_all
  maintain_update_packages 1
  maintain_check_pacnew_reminder
  maintain_clean_all
  maintain_remove_orphans 1
}

maintain_cron_mirrors() {
  log "Cron: Spiegel"
  maintain_mirrors_all
  maintain_update_packages 1
  maintain_check_pacnew_reminder
}

maintain_cron_clean() {
  log "Cron: Bereinigung"
  maintain_clean_all
}

maintain_interactive_full() {
  log "Volle Wartung (interaktiv)"
  if confirm "Arch- und EOS-Spiegel neu sortieren?"; then
    maintain_mirrors_all
  fi
  maintain_update_packages 1
  maintain_check_pacnew_reminder
  if confirm "Journal (4 Wochen) und Pacman-Cache bereinigen?"; then
    maintain_clean_all
  fi
  maintain_remove_orphans 0
}
