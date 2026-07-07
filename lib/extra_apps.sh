# Zusatz-Anwendungen: Cursor IDE und IBM Bob (AUR / AppImage)

: "${EXTRA_APPS_CONFIG:=$CONFIG_DIR/extra-apps.conf}"

CURSOR_AUR_PKG='cursor-bin'
IBM_BOB_PKG='ibm-bob-bin'
CURSOR_API_URL='https://cursor.com/api/download?platform=linux-x64&releaseTrack=stable'

extra_apps_config_ensure() {
  [[ -f "$EXTRA_APPS_CONFIG" ]] && return 0
  mkdir -p "$CONFIG_DIR"
  cat >"$EXTRA_APPS_CONFIG" <<'EOF'
# Zusatz-Anwendungen – endeavour-updater
# Cursor AppImage (leer = automatisch aus .desktop oder ~/Applications/cursor.AppImage)
CURSOR_APPIMAGE=
# Letzte bekannte Cursor-AppImage-Version (wird nach Update gesetzt)
CURSOR_APPIMAGE_VERSION=
# Bei --update / Cron mit aktualisieren (1=ja, 0=nein)
EXTRA_APPS_WITH_UPDATE=1
EOF
}

extra_apps_cursor_save_version() {
  local ver="$1"
  extra_apps_config_ensure
  if grep -q '^CURSOR_APPIMAGE_VERSION=' "$EXTRA_APPS_CONFIG" 2>/dev/null; then
    sed -i "s|^CURSOR_APPIMAGE_VERSION=.*|CURSOR_APPIMAGE_VERSION=$ver|" "$EXTRA_APPS_CONFIG"
  else
    echo "CURSOR_APPIMAGE_VERSION=$ver" >>"$EXTRA_APPS_CONFIG"
  fi
}

extra_apps_config_load() {
  extra_apps_config_ensure
  # shellcheck source=/dev/null
  source "$EXTRA_APPS_CONFIG"
}

extra_apps_json_field() {
  local json="$1" field="$2"
  printf '%s' "$json" | grep -oP "\"${field}\"\\s*:\\s*\"\\K[^\"]+" | head -1
}

extra_apps_version_lt() {
  local a="$1" b="$2"
  [[ "$a" != "$b" && "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)" == "$a" ]]
}

extra_apps_run_yay() {
  if [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    run sudo -u "$SUDO_USER" -H -- yay "$@"
  else
    run yay "$@"
  fi
}

extra_apps_yay_update_pkg() {
  local pkg="$1" label="$2"
  local install="${3:-0}"
  local flags=(-S --needed)
  [[ "$NONINTERACTIVE" -eq 1 || "$YES" -eq 1 ]] && flags+=(--noconfirm)

  have_cmd yay || { warn "yay fehlt – $label übersprungen."; return 1; }

  if ! pacman -Qi "$pkg" &>/dev/null; then
    if [[ "$install" -eq 1 ]] && confirm "$label ($pkg) installieren?"; then
      extra_apps_run_yay "${flags[@]}" "$pkg"
    else
      log "$label nicht installiert ($pkg) – übersprungen."
    fi
    return 0
  fi

  if yay -Qu "$pkg" 2>/dev/null | awk '{print $1}' | grep -Fxq "$pkg"; then
    log "$label: AUR-Update verfügbar …"
    extra_apps_run_yay "${flags[@]}" "$pkg"
  else
    log "$label ($pkg): bereits aktuell."
  fi
}

extra_apps_cursor_appimage_from_desktop() {
  local f line path
  for f in "$HOME/.local/share/applications"/cursor*.desktop \
           "$HOME/.local/share/applications"/Cursor*.desktop; do
    [[ -f "$f" ]] || continue
    line="$(grep -m1 '^Exec=' "$f" 2>/dev/null || true)"
    [[ -n "$line" ]] || continue
    path="${line#Exec=}"
    path="${path%% *}"
    path="${path//\"/}"
    [[ -f "$path" && "$path" == *.AppImage ]] && { echo "$path"; return 0; }
  done
  return 1
}

extra_apps_cursor_appimage_path() {
  local from_desktop
  extra_apps_config_load
  if [[ -n "${CURSOR_APPIMAGE:-}" && -f "$CURSOR_APPIMAGE" ]]; then
    echo "$CURSOR_APPIMAGE"
    return 0
  fi
  if from_desktop="$(extra_apps_cursor_appimage_from_desktop)"; then
    echo "$from_desktop"
    return 0
  fi
  if [[ -f "$HOME/Applications/cursor.AppImage" ]]; then
    echo "$HOME/Applications/cursor.AppImage"
    return 0
  fi
  return 1
}

extra_apps_cursor_detect() {
  if pacman -Qi "$CURSOR_AUR_PKG" &>/dev/null; then
    echo pacman
  elif extra_apps_cursor_appimage_path >/dev/null; then
    echo appimage
  else
    echo none
  fi
}

extra_apps_bob_detect() {
  if pacman -Qi "$IBM_BOB_PKG" &>/dev/null; then
    echo pacman
  else
    echo none
  fi
}

extra_apps_cursor_local_version() {
  local method="$1" app ver
  case "$method" in
    pacman)
      pacman -Qi "$CURSOR_AUR_PKG" 2>/dev/null | awk -F': ' '/^Version/{print $2; exit}' | cut -d- -f1
      ;;
    appimage)
      extra_apps_config_load
      [[ -n "${CURSOR_APPIMAGE_VERSION:-}" ]] && echo "$CURSOR_APPIMAGE_VERSION"
      ;;
  esac
}

extra_apps_cursor_is_current() {
  local remote_ver="$1" local_ver
  local_ver="$(extra_apps_cursor_local_version appimage || true)"
  [[ -n "$local_ver" && -n "$remote_ver" ]] && ! extra_apps_version_lt "$local_ver" "$remote_ver"
}

extra_apps_cursor_fetch_release() {
  have_cmd curl || { warn "curl fehlt – Cursor-API nicht erreichbar."; return 1; }
  curl -fsSL -A 'Mozilla/5.0 (X11; Linux x86_64)' "$CURSOR_API_URL"
}

extra_apps_cursor_update_appimage() {
  local app remote_json remote_ver remote_url local_ver tmp backup
  app="$(extra_apps_cursor_appimage_path)" || {
    log "Kein Cursor-AppImage gefunden – übersprungen."
    return 0
  }

  remote_json="$(extra_apps_cursor_fetch_release)" || {
    warn "Cursor-Release-Info konnte nicht geladen werden."
    return 1
  }
  remote_ver="$(extra_apps_json_field "$remote_json" version)"
  remote_url="$(extra_apps_json_field "$remote_json" downloadUrl)"
  [[ -n "$remote_ver" && -n "$remote_url" ]] || {
    warn "Cursor-API-Antwort unvollständig."
    return 1
  }

  local_ver="$(extra_apps_cursor_local_version appimage || true)"
  log "Cursor AppImage: installiert ${local_ver:-unbekannt}, verfügbar $remote_ver"

  if extra_apps_cursor_is_current "$remote_ver"; then
    log "Cursor AppImage ist bereits aktuell."
    return 0
  fi
  if [[ -z "$local_ver" && "$NONINTERACTIVE" -eq 1 ]]; then
    warn "Cursor-Version lokal unbekannt – automatisches Update übersprungen (interaktiv: --cursor)."
    return 0
  fi

  if ! confirm "Cursor AppImage auf $remote_ver aktualisieren?"; then
    log "Cursor-Update abgebrochen."
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] curl → $app ($remote_url)"
    return 0
  fi

  tmp="$(mktemp "${app}.XXXXXX")"
  backup="${app}.bak.$(date +%Y%m%d-%H%M%S)"
  log "Lade Cursor $remote_ver …"
  if ! curl -fL -A 'Mozilla/5.0 (X11; Linux x86_64)' -o "$tmp" "$remote_url"; then
    rm -f "$tmp"
    warn "Cursor-Download fehlgeschlagen."
    return 1
  fi
  chmod +x "$tmp"
  cp -a "$app" "$backup"
  mv -f "$tmp" "$app"
  extra_apps_cursor_save_version "$remote_ver"
  log "Cursor aktualisiert: $app (Backup: $backup)"
}

extra_apps_cursor_update() {
  local method install="${1:-0}"
  method="$(extra_apps_cursor_detect)"
  case "$method" in
    pacman)
      extra_apps_yay_update_pkg "$CURSOR_AUR_PKG" 'Cursor IDE' "$install"
      ;;
    appimage)
      extra_apps_cursor_update_appimage
      ;;
    none)
      if [[ "$install" -eq 1 ]] && confirm "Cursor IDE ($CURSOR_AUR_PKG) aus dem AUR installieren?"; then
        extra_apps_yay_update_pkg "$CURSOR_AUR_PKG" 'Cursor IDE' 1
      elif [[ "$install" -eq 1 ]] && confirm "Stattdessen Cursor AppImage nach ~/Applications/cursor.AppImage laden?"; then
        mkdir -p "$HOME/Applications"
        CURSOR_APPIMAGE="$HOME/Applications/cursor.AppImage"
        extra_apps_config_ensure
        if grep -q '^CURSOR_APPIMAGE=' "$EXTRA_APPS_CONFIG" 2>/dev/null; then
          sed -i "s|^CURSOR_APPIMAGE=.*|CURSOR_APPIMAGE=$CURSOR_APPIMAGE|" "$EXTRA_APPS_CONFIG"
        else
          echo "CURSOR_APPIMAGE=$CURSOR_APPIMAGE" >>"$EXTRA_APPS_CONFIG"
        fi
        extra_apps_cursor_update_appimage
      else
        log "Cursor IDE nicht gefunden – weder $CURSOR_AUR_PKG noch AppImage."
      fi
      ;;
  esac
}

extra_apps_bob_update() {
  local install="${1:-0}"
  extra_apps_yay_update_pkg "$IBM_BOB_PKG" 'IBM Bob' "$install"
}

extra_apps_update_all() {
  local install="${1:-0}"
  log "Zusatz-Anwendungen: Cursor IDE und IBM Bob"
  extra_apps_cursor_update "$install"
  extra_apps_bob_update "$install"
}

extra_apps_status() {
  local method ver
  echo
  echo "── Zusatz-Anwendungen ──"
  method="$(extra_apps_cursor_detect)"
  case "$method" in
    pacman)
      ver="$(extra_apps_cursor_local_version pacman || echo '?')"
      echo "  Cursor IDE: $CURSOR_AUR_PKG ($ver)"
      ;;
    appimage)
      ver="$(extra_apps_cursor_local_version appimage || echo '?')"
      echo "  Cursor IDE: AppImage $(extra_apps_cursor_appimage_path) ($ver)"
      ;;
    none)
      echo "  Cursor IDE: nicht installiert"
      ;;
  esac
  if pacman -Qi "$IBM_BOB_PKG" &>/dev/null; then
    ver="$(pacman -Qi "$IBM_BOB_PKG" | awk -F': ' '/^Version/{print $2; exit}')"
    echo "  IBM Bob: $IBM_BOB_PKG ($ver)"
  else
    echo "  IBM Bob: nicht installiert ($IBM_BOB_PKG)"
  fi
  echo "  Konfiguration: $EXTRA_APPS_CONFIG"
}

extra_apps_update_after_packages() {
  extra_apps_config_load
  [[ "${EXTRA_APPS_WITH_UPDATE:-1}" -eq 1 ]] || return 0
  extra_apps_update_all 0
}
