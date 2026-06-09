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

# Waisen, die nie automatisch entfernt werden (kritische Infrastruktur).
# Zusätzliche Pakete: eine Zeile pro Name in ~/.config/endeavour-updater/orphan-protect
maintain_orphan_protect_file() {
  echo "${CONFIG_DIR}/orphan-protect"
}

maintain_orphan_protect_ensure_template() {
  local f
  f="$(maintain_orphan_protect_file)"
  [[ -f "$f" ]] && return 0
  mkdir -p "$CONFIG_DIR"
  cat >"$f" <<'EOF'
# Zusätzliche Pakete, die bei Waisen-Bereinigung nie entfernt werden.
# Eine Zeile pro Paketname. Kommentare mit #.
# Standard-Schutz (immer aktiv): xrdp-git, xorgxrdp-git
EOF
}

maintain_orphan_protect_load() {
  maintain_orphan_protect_ensure_template
  [[ -n "${MAINTAIN_ORPHAN_PROTECT+x}" ]] && return 0
  MAINTAIN_ORPHAN_PROTECT=()
  local -A seen=()
  local pkg line f

  _maintain_orphan_protect_add() {
    pkg="$1"
    [[ -z "$pkg" || -n "${seen[$pkg]+x}" ]] && return 0
    seen["$pkg"]=1
    MAINTAIN_ORPHAN_PROTECT+=("$pkg")
  }

  # RDP aus AUR: oft als Waise gelistet, aber essenziell für Remote-Zugriff
  _maintain_orphan_protect_add xrdp-git
  _maintain_orphan_protect_add xorgxrdp-git

  f="$(maintain_orphan_protect_file)"
  if [[ -r "$f" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"
      line="${line// /}"
      [[ -n "$line" ]] && _maintain_orphan_protect_add "$line"
    done <"$f"
  fi
}

maintain_orphan_is_protected() {
  local pkg="$1" p
  maintain_orphan_protect_load
  for p in "${MAINTAIN_ORPHAN_PROTECT[@]}"; do
    [[ "$p" == "$pkg" ]] && return 0
  done
  return 1
}

maintain_partition_orphans() {
  local all_orphans=("$@")
  MAINTAIN_ORPHANS_PROTECTED=()
  MAINTAIN_ORPHANS_REMOVABLE=()
  local pkg
  for pkg in "${all_orphans[@]}"; do
    if maintain_orphan_is_protected "$pkg"; then
      MAINTAIN_ORPHANS_PROTECTED+=("$pkg")
    else
      MAINTAIN_ORPHANS_REMOVABLE+=("$pkg")
    fi
  done
}

maintain_remove_orphans() {
  local auto="${1:-0}"
  local all_orphans protected removable
  mapfile -t all_orphans < <(maintain_list_orphans)
  maintain_partition_orphans "${all_orphans[@]}"
  protected=("${MAINTAIN_ORPHANS_PROTECTED[@]}")
  removable=("${MAINTAIN_ORPHANS_REMOVABLE[@]}")

  if [[ "${#protected[@]}" -gt 0 ]]; then
    log "Geschützte Waisen (werden nicht entfernt):"
    printf '  %s\n' "${protected[@]}"
    log "Weitere Schutzliste: $(maintain_orphan_protect_file)"
  fi

  if [[ "${#removable[@]}" -eq 0 ]]; then
    if [[ "${#all_orphans[@]}" -eq 0 ]]; then
      log "Keine Waisen-Pakete."
    else
      log "Keine entfernbaren Waisen – alle Einträge sind geschützt."
    fi
    return 0
  fi

  log "Entfernbare Waisen (${#removable[@]}):"
  printf '  %s\n' "${removable[@]}"
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
  run_root pacman "${rm_flags[@]}" "${removable[@]}"
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
