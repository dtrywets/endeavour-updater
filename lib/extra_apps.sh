# Zusatz-Anwendungen: Cursor IDE/CLI und IBM Bob IDE/CLI

: "${EXTRA_APPS_CONFIG:=$CONFIG_DIR/extra-apps.conf}"

CURSOR_AUR_PKG='cursor-bin'
IBM_BOB_PKG='ibm-bob-bin'
CURSOR_API_URL='https://cursor.com/api/download?platform=linux-x64&releaseTrack=stable'
CURSOR_CLI_INSTALL_URL='https://cursor.com/install'
BOB_CLI_INSTALL_URL='https://bob.ibm.com/download/bobshell.sh'
BOB_CLI_VERSION_URL='https://s3.us-south.cloud-object-storage.appdomain.cloud/bob-shell/bobshell-version.txt'
BOB_CLI_BASE_URL='https://s3.us-south.cloud-object-storage.appdomain.cloud/bob-shell'

extra_apps_config_ensure() {
  [[ -f "$EXTRA_APPS_CONFIG" ]] && return 0
  mkdir -p "$CONFIG_DIR"
  cat >"$EXTRA_APPS_CONFIG" <<'EOF'
# Zusatz-Anwendungen – endeavour-updater
# Cursor AppImage (leer = automatisch aus .desktop oder ~/Applications/cursor.AppImage)
CURSOR_APPIMAGE=
# Letzte bekannte Cursor-AppImage-Version (wird nach Update gesetzt)
CURSOR_APPIMAGE_VERSION=
# Bob CLI: npm, pnpm oder yarn (leer = automatisch erkennen)
BOB_CLI_PM=
# Bob IDE Binary (leer = automatisch /usr/share/bobide/bobide, /usr/bin/bobide)
BOB_IDE_BINARY=
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

extra_apps_config_set() {
  local key="$1" val="$2"
  extra_apps_config_ensure
  if grep -q "^${key}=" "$EXTRA_APPS_CONFIG" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$EXTRA_APPS_CONFIG"
  else
    echo "${key}=${val}" >>"$EXTRA_APPS_CONFIG"
  fi
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

extra_apps_run_user() {
  if [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    run sudo -u "$SUDO_USER" -H -- "$@"
  else
    run "$@"
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

# ── Erkennung ────────────────────────────────────────────────────────────────

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

extra_apps_cursor_ide_detect() {
  if pacman -Qi "$CURSOR_AUR_PKG" &>/dev/null; then
    echo pacman
  elif have_cmd cursor && pacman -Qo "$(command -v cursor)" &>/dev/null; then
    echo pacman
  elif extra_apps_cursor_appimage_path >/dev/null; then
    echo appimage
  else
    echo none
  fi
}

extra_apps_cursor_cli_bin() {
  local c d
  for c in "$HOME/.local/bin/cursor-agent" "$HOME/.local/bin/agent"; do
    if [[ -x "$c" ]] && readlink -f "$c" 2>/dev/null | grep -q cursor-agent; then
      echo "$c"
      return 0
    fi
  done
  if [[ -d "$HOME/.local/share/cursor-agent/versions" ]]; then
    for d in $(find "$HOME/.local/share/cursor-agent/versions" -mindepth 1 -maxdepth 1 -type d -name '20*' 2>/dev/null | sort -r); do
      if [[ -x "$d/cursor-agent" ]]; then
        echo "$d/cursor-agent"
        return 0
      fi
    done
  fi
  return 1
}

extra_apps_cursor_cli_detect() {
  extra_apps_cursor_cli_bin >/dev/null && echo cursor-agent || echo none
}

extra_apps_bob_ide_bin() {
  local p f line
  extra_apps_config_load
  if [[ -n "${BOB_IDE_BINARY:-}" && -x "$BOB_IDE_BINARY" ]]; then
    echo "$BOB_IDE_BINARY"
    return 0
  fi
  for p in /usr/share/bobide/bobide /usr/bin/bobide; do
    [[ -x "$p" ]] && { echo "$p"; return 0; }
  done
  if have_cmd bobide; then
    command -v bobide
    return 0
  fi
  for f in /usr/share/applications/bobide*.desktop "$HOME/.local/share/applications"/bobide*.desktop; do
    [[ -f "$f" ]] || continue
    line="$(grep -m1 '^Exec=' "$f" 2>/dev/null || true)"
    [[ -n "$line" ]] || continue
    p="${line#Exec=}"
    p="${p%% *}"
    p="${p//\"/}"
    [[ -x "$p" ]] && { echo "$p"; return 0; }
  done
  return 1
}

extra_apps_bob_ide_detect() {
  local bin owner
  if pacman -Qi "$IBM_BOB_PKG" &>/dev/null; then
    echo pacman
    return 0
  fi
  bin="$(extra_apps_bob_ide_bin || true)"
  [[ -n "$bin" ]] || { echo none; return 0; }
  owner="$(pacman -Qo "$bin" 2>/dev/null | awk '{print $NF}' || true)"
  if [[ "$owner" == "$IBM_BOB_PKG" || "$owner" == bobide ]]; then
    echo pacman
  else
    echo upstream
  fi
}

extra_apps_bob_ide_version() {
  local method="$1" bin pkgjson ver
  case "$method" in
    pacman)
      pacman -Qi "$IBM_BOB_PKG" 2>/dev/null | awk -F': ' '/^Version/{print $2; exit}' | cut -d- -f1
      ;;
    upstream)
      for pkgjson in /usr/share/bobide/resources/app/package.json \
                     /usr/share/bobide/vscode/resources/app/package.json \
                     /usr/share/bobide/package.json; do
        if [[ -f "$pkgjson" ]]; then
          ver="$(grep -m1 '"version"' "$pkgjson" 2>/dev/null | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"
          [[ -n "$ver" ]] && echo "$ver" && return 0
        fi
      done
      bin="$(extra_apps_bob_ide_bin || true)"
      [[ -n "$bin" ]] && "$bin" --version 2>/dev/null | head -1
      ;;
  esac
}

extra_apps_bob_cli_pm_detect() {
  local pm
  extra_apps_config_load
  if [[ -n "${BOB_CLI_PM:-}" ]]; then
    echo "$BOB_CLI_PM"
    return 0
  fi
  for pm in npm pnpm yarn; do
    have_cmd "$pm" || continue
    if "$pm" list -g --depth=0 2>/dev/null | grep -qi bobshell; then
      echo "$pm"
      return 0
    fi
  done
  return 1
}

extra_apps_bob_cli_detect() {
  [[ -x "$HOME/.local/bin/bob" ]] && { echo bob; return 0; }
  have_cmd bob && echo bob || echo none
}

extra_apps_node_user_prefix() {
  echo "${NPM_CONFIG_PREFIX:-$HOME/.local}"
}

extra_apps_node_user_prepare() {
  local prefix
  prefix="$(extra_apps_node_user_prefix)"
  mkdir -p "$prefix/bin" "$prefix/lib/node_modules"
  echo "$prefix"
}

extra_apps_bob_cli_run_install_script() {
  local pm="$1"
  local prefix
  prefix="$(extra_apps_node_user_prepare)"
  extra_apps_run_user bash -c "
    set -euo pipefail
    export npm_config_prefix='${prefix}'
    export PNPM_HOME='${prefix}'
    export PATH='${prefix}/bin':\"\$PATH\"
    curl -fsSL '${BOB_CLI_INSTALL_URL}' | bash -s -- --pm '${pm}'
  "
}

extra_apps_bob_cli_run_pm_global() {
  local pm="$1" url="$2"
  local prefix
  prefix="$(extra_apps_node_user_prepare)"
  case "$pm" in
    npm)
      extra_apps_run_user env npm_config_prefix="$prefix" \
        npm install --registry=https://registry.npmjs.org/ --progress=false --loglevel=error -g "$url"
      ;;
    pnpm)
      extra_apps_run_user env PNPM_HOME="$prefix" npm_config_prefix="$prefix" \
        pnpm add --registry=https://registry.npmjs.org/ -g "$url"
      ;;
    yarn)
      extra_apps_run_user env npm_config_prefix="$prefix" \
        YARN_REGISTRY=https://registry.npmjs.org/ yarn global add "$url"
      ;;
    *)
      extra_apps_bob_cli_run_install_script "$pm"
      ;;
  esac
}

extra_apps_profile() {
  CURSOR_IDE_METHOD="$(extra_apps_cursor_ide_detect)"
  CURSOR_CLI_METHOD="$(extra_apps_cursor_cli_detect)"
  BOB_IDE_METHOD="$(extra_apps_bob_ide_detect)"
  BOB_CLI_METHOD="$(extra_apps_bob_cli_detect)"
  BOB_CLI_PM="$(extra_apps_bob_cli_pm_detect || true)"
}

# ── Cursor IDE ───────────────────────────────────────────────────────────────

extra_apps_cursor_ide_version() {
  local method="$1"
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
  local_ver="$(extra_apps_cursor_ide_version appimage || true)"
  [[ -n "$local_ver" && -n "$remote_ver" ]] && ! extra_apps_version_lt "$local_ver" "$remote_ver"
}

extra_apps_cursor_fetch_release() {
  have_cmd curl || { warn "curl fehlt – Cursor-API nicht erreichbar."; return 1; }
  curl -fsSL -A 'Mozilla/5.0 (X11; Linux x86_64)' "$CURSOR_API_URL"
}

extra_apps_cursor_ide_update_appimage() {
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

  local_ver="$(extra_apps_cursor_ide_version appimage || true)"
  log "Cursor IDE (AppImage): installiert ${local_ver:-unbekannt}, verfügbar $remote_ver"

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

extra_apps_cursor_ide_install() {
  if confirm "Cursor IDE ($CURSOR_AUR_PKG) aus dem AUR installieren?"; then
    extra_apps_yay_update_pkg "$CURSOR_AUR_PKG" 'Cursor IDE' 1
    return
  fi
  if confirm "Stattdessen Cursor AppImage nach ~/Applications/cursor.AppImage laden?"; then
    mkdir -p "$HOME/Applications"
    extra_apps_config_set CURSOR_APPIMAGE "$HOME/Applications/cursor.AppImage"
    extra_apps_cursor_ide_update_appimage
  fi
}

extra_apps_cursor_ide_update() {
  local install="${1:-0}" method
  method="$(extra_apps_cursor_ide_detect)"
  case "$method" in
    pacman) extra_apps_yay_update_pkg "$CURSOR_AUR_PKG" 'Cursor IDE' 0 ;;
    appimage) extra_apps_cursor_ide_update_appimage ;;
    none)
      if [[ "$install" -eq 1 ]]; then
        extra_apps_cursor_ide_install
      else
        log "Cursor IDE nicht installiert – übersprungen."
      fi
      ;;
  esac
}

# ── Cursor CLI ───────────────────────────────────────────────────────────────

extra_apps_cursor_cli_version() {
  local bin ver
  bin="$(extra_apps_cursor_cli_bin || true)"
  [[ -n "$bin" ]] || return 1
  ver="$("$bin" --version 2>/dev/null | head -1 || true)"
  [[ -n "$ver" ]] && echo "$ver"
}

extra_apps_cursor_cli_install() {
  have_cmd curl || { warn "curl fehlt – Cursor CLI kann nicht installiert werden."; return 1; }
  if ! confirm "Cursor CLI (Agent) installieren?"; then
    log "Cursor-CLI-Installation abgebrochen."
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] curl $CURSOR_CLI_INSTALL_URL | bash"
    return 0
  fi
  log "Installiere Cursor CLI …"
  extra_apps_run_user bash -c "curl -fsSL '$CURSOR_CLI_INSTALL_URL' | bash"
}

extra_apps_cursor_cli_update() {
  local install="${1:-0}" bin method
  method="$(extra_apps_cursor_cli_detect)"
  if [[ "$method" == none ]]; then
    if [[ "$install" -eq 1 ]]; then
      extra_apps_cursor_cli_install
    else
      log "Cursor CLI nicht installiert – übersprungen."
    fi
    return 0
  fi

  bin="$(extra_apps_cursor_cli_bin)"
  log "Cursor CLI: installiert $(extra_apps_cursor_cli_version || echo unbekannt)"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] $bin update"
    return 0
  fi
  if ! confirm "Cursor CLI aktualisieren?"; then
    log "Cursor-CLI-Update abgebrochen."
    return 0
  fi
  log "Aktualisiere Cursor CLI …"
  extra_apps_run_user "$bin" update
}

# ── IBM Bob IDE ──────────────────────────────────────────────────────────────

extra_apps_bob_ide_install() {
  if confirm "IBM Bob IDE ($IBM_BOB_PKG) aus dem AUR installieren?"; then
    extra_apps_yay_update_pkg "$IBM_BOB_PKG" 'IBM Bob IDE' 1
  fi
}

extra_apps_bob_ide_update() {
  local install="${1:-0}" method ver bin
  method="$(extra_apps_bob_ide_detect)"
  case "$method" in
    pacman)
      extra_apps_yay_update_pkg "$IBM_BOB_PKG" 'IBM Bob IDE' 0
      ;;
    upstream)
      bin="$(extra_apps_bob_ide_bin || echo '?')"
      ver="$(extra_apps_bob_ide_version upstream || echo '?')"
      log "IBM Bob IDE (Upstream): $bin ($ver)"
      if ! have_cmd yay; then
        warn "yay fehlt – Upstream-Installation manuell aktualisieren oder $IBM_BOB_PKG installieren."
        warn "Download: https://bob.ibm.com/download"
        return 1
      fi
      if ! confirm "IBM Bob IDE über AUR ($IBM_BOB_PKG) aktualisieren?"; then
        log "Bob-IDE-Update abgebrochen."
        return 0
      fi
      if pacman -Qi bobide &>/dev/null; then
        warn "Altes Paket bobide wird durch $IBM_BOB_PKG ersetzt (pacman-Konflikt)."
      fi
      log "Synchronisiere mit $IBM_BOB_PKG …"
      local flags=(-S --needed)
      [[ "$NONINTERACTIVE" -eq 1 || "$YES" -eq 1 ]] && flags+=(--noconfirm)
      extra_apps_run_yay "${flags[@]}" "$IBM_BOB_PKG"
      ;;
    none)
      if [[ "$install" -eq 1 ]]; then
        extra_apps_bob_ide_install
      else
        log "IBM Bob IDE nicht installiert – übersprungen."
      fi
      ;;
  esac
}

# ── IBM Bob CLI ──────────────────────────────────────────────────────────────

extra_apps_bob_cli_version() {
  have_cmd bob || return 1
  bob --version 2>/dev/null | tail -1 | tr -d '[:space:]'
}

extra_apps_bob_cli_fetch_version() {
  have_cmd curl || return 1
  curl -fsSL "$BOB_CLI_VERSION_URL" | tr -d '[:space:]'
}

extra_apps_bob_cli_pm_pick() {
  local pm
  extra_apps_config_load
  [[ -n "${BOB_CLI_PM:-}" ]] && { echo "$BOB_CLI_PM"; return 0; }
  for pm in npm pnpm yarn; do
    have_cmd "$pm" && { echo "$pm"; return 0; }
  done
  return 1
}

extra_apps_bob_cli_install() {
  local pm ver url flags=()
  have_cmd curl || { warn "curl fehlt – Bob CLI kann nicht installiert werden."; return 1; }
  have_cmd node || { warn "Node.js fehlt – Bob CLI benötigt Node.js ≥ 22.15."; return 1; }
  pm="$(extra_apps_bob_cli_pm_pick)" || {
    warn "Kein npm/pnpm/yarn gefunden – Bob CLI kann nicht installiert werden."
    return 1
  }
  if ! confirm "IBM Bob CLI (bob) mit $pm installieren?"; then
    log "Bob-CLI-Installation abgebrochen."
    return 0
  fi
  extra_apps_config_set BOB_CLI_PM "$pm"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] Bob CLI nach $(extra_apps_node_user_prefix) via $pm"
    return 0
  fi
  log "Installiere IBM Bob CLI ($pm) nach $(extra_apps_node_user_prefix) …"
  extra_apps_bob_cli_run_install_script "$pm"
  if [[ -x "$(extra_apps_node_user_prefix)/bin/bob" ]]; then
    log "Bob CLI installiert: $(extra_apps_node_user_prefix)/bin/bob"
  elif have_cmd bob; then
    log "Bob CLI installiert: $(command -v bob)"
  else
    warn "Bob CLI nach Installation nicht gefunden – PATH prüfen: $(extra_apps_node_user_prefix)/bin"
  fi
}

extra_apps_bob_cli_update() {
  local install="${1:-0}" pm remote local url
  if [[ "$(extra_apps_bob_cli_detect)" == none ]]; then
    if [[ "$install" -eq 1 ]]; then
      extra_apps_bob_cli_install
    else
      log "IBM Bob CLI nicht installiert – übersprungen."
    fi
    return 0
  fi

  remote="$(extra_apps_bob_cli_fetch_version || true)"
  local="$(extra_apps_bob_cli_version || true)"
  log "IBM Bob CLI: installiert ${local:-unbekannt}, verfügbar ${remote:-?}"

  if [[ -n "$remote" && -n "$local" && "$local" == "$remote" ]]; then
    log "IBM Bob CLI ist bereits aktuell."
    return 0
  fi
  if ! confirm "IBM Bob CLI auf ${remote:-neueste Version} aktualisieren?"; then
    log "Bob-CLI-Update abgebrochen."
    return 0
  fi

  pm="$(extra_apps_bob_cli_pm_detect || extra_apps_bob_cli_pm_pick)" || pm=npm
  extra_apps_config_set BOB_CLI_PM "$pm"
  url="${BOB_CLI_BASE_URL}/bobshell-${remote}.tgz"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] $pm install -g $url"
    return 0
  fi

  log "Aktualisiere IBM Bob CLI …"
  extra_apps_bob_cli_run_pm_global "$pm" "$url"
}

# ── Sammelaktionen ───────────────────────────────────────────────────────────

extra_apps_cursor_update() {
  local install="${1:-0}"
  extra_apps_profile
  log "Cursor: IDE=${CURSOR_IDE_METHOD}, CLI=${CURSOR_CLI_METHOD}"
  extra_apps_cursor_ide_update "$install"
  extra_apps_cursor_cli_update "$install"
}

extra_apps_bob_update() {
  local install="${1:-0}"
  extra_apps_profile
  log "IBM Bob: IDE=${BOB_IDE_METHOD}, CLI=${BOB_CLI_METHOD}"
  extra_apps_bob_ide_update "$install"
  extra_apps_bob_cli_update "$install"
}

extra_apps_update_all() {
  local install="${1:-0}"
  log "Zusatz-Anwendungen: Cursor und IBM Bob (IDE + CLI)"
  extra_apps_cursor_update "$install"
  extra_apps_bob_update "$install"
}

extra_apps_status_line() {
  local label="$1" method="$2" detail="${3:-}"
  if [[ "$method" == none ]]; then
    echo "  $label: nicht installiert${detail:+ ($detail)}"
  else
    echo "  $label: $method${detail:+ ($detail)}"
  fi
}

extra_apps_status() {
  local ver path
  extra_apps_profile
  echo
  echo "── Zusatz-Anwendungen ──"
  case "$CURSOR_IDE_METHOD" in
    pacman)
      ver="$(extra_apps_cursor_ide_version pacman || echo '?')"
      extra_apps_status_line "Cursor IDE" "$CURSOR_AUR_PKG" "$ver"
      ;;
    appimage)
      ver="$(extra_apps_cursor_ide_version appimage || echo '?')"
      path="$(extra_apps_cursor_appimage_path || echo '?')"
      extra_apps_status_line "Cursor IDE" "AppImage" "$ver – $path"
      ;;
    none) extra_apps_status_line "Cursor IDE" "none" ;;
  esac
  if [[ "$CURSOR_CLI_METHOD" != none ]]; then
    ver="$(extra_apps_cursor_cli_version || echo '?')"
    extra_apps_status_line "Cursor CLI" "cursor-agent" "$ver"
  else
    extra_apps_status_line "Cursor CLI" "none"
  fi
  case "$BOB_IDE_METHOD" in
    pacman)
      ver="$(extra_apps_bob_ide_version pacman || echo '?')"
      extra_apps_status_line "IBM Bob IDE" "$IBM_BOB_PKG" "$ver"
      ;;
    upstream)
      ver="$(extra_apps_bob_ide_version upstream || echo '?')"
      path="$(extra_apps_bob_ide_bin || echo '?')"
      extra_apps_status_line "IBM Bob IDE" "Upstream" "$ver – $path"
      ;;
    none) extra_apps_status_line "IBM Bob IDE" "none" ;;
  esac
  if [[ "$BOB_CLI_METHOD" != none ]]; then
    ver="$(extra_apps_bob_cli_version || echo '?')"
    extra_apps_status_line "IBM Bob CLI" "bob${BOB_CLI_PM:+ ($BOB_CLI_PM)}" "$ver"
  else
    extra_apps_status_line "IBM Bob CLI" "none"
  fi
  echo "  Konfiguration: $EXTRA_APPS_CONFIG"
}

extra_apps_update_after_packages() {
  extra_apps_config_load
  [[ "${EXTRA_APPS_WITH_UPDATE:-1}" -eq 1 ]] || return 0
  extra_apps_update_all 0
}
