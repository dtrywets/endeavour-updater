# shellcheck shell=bash
# Zusatz-Anwendungen: Cursor, IBM Bob und Agent-Stack (Herdr + Pi + Firstmate)

: "${EXTRA_APPS_CONFIG:=$CONFIG_DIR/extra-apps.conf}"

CURSOR_AUR_PKG='cursor-bin'
IBM_BOB_PKG='ibm-bob-bin'
PI_NPM_PKG='@earendil-works/pi-coding-agent'
CURSOR_API_URL='https://cursor.com/api/download?platform=linux-x64&releaseTrack=stable'
CURSOR_CLI_INSTALL_URL='https://cursor.com/install'
# shellcheck disable=SC2034 # dokumentierte Upstream-URL, derzeit ungenutzt
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
# Pi CLI: npm, pnpm oder yarn (leer = automatisch erkennen)
PI_CLI_PM=
# npm global prefix (leer = ~/.local, Fallback ~/.config/endeavour-updater/npm)
NPM_CONFIG_PREFIX=
# Bob IDE Binary (leer = automatisch /usr/share/bobide/bobide, /usr/bin/bobide)
BOB_IDE_BINARY=
# Firstmate-Root (leer = FIRSTMATE_HOME/FM_HOME/FM_ROOT oder übliche Pfade)
FIRSTMATE_HOME=
# Bei --update / Cron: Cursor + Bob mit aktualisieren (1=ja, 0=nein)
EXTRA_APPS_WITH_UPDATE=1
# Bei --update / Cron: Agent-Stack (Herdr/Pi/Firstmate) mit aktualisieren (1=ja, 0=nein)
AGENT_STACK_WITH_UPDATE=0
# Bei --apps: Agent-Stack zusätzlich zu Cursor/Bob (1=ja, 0=nein)
AGENT_STACK_WITH_APPS=0
# Einzelne Agent-Stack-Komponenten überspringen (1=ja)
SKIP_HERDR=0
SKIP_PI=0
SKIP_FIRSTMATE=0
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
  extra_apps_config_load
  [[ -n "${NPM_CONFIG_PREFIX:-}" ]] && { echo "$NPM_CONFIG_PREFIX"; return 0; }
  echo "$HOME/.local"
}

extra_apps_node_user_dir_writable() {
  local prefix="$1" dir
  for dir in "$prefix" "$prefix/bin" "$prefix/lib" "$prefix/lib/node_modules"; do
    [[ -e "$dir" && ! -w "$dir" ]] && return 1
  done
  return 0
}

extra_apps_node_user_fix_permissions() {
  local prefix="$1" dir owner need_fix=0
  for dir in "$prefix/lib" "$prefix/lib/node_modules" "$prefix/bin"; do
    [[ -e "$dir" ]] || continue
    if [[ ! -w "$dir" ]]; then
      owner="$(stat -c '%U' "$dir" 2>/dev/null || echo '?')"
      warn "Keine Schreibrechte: $dir (Besitzer: $owner)"
      need_fix=1
    fi
  done
  [[ "$need_fix" -eq 0 ]] && return 0
  warn "Oft Ursache: frühere Installation mit sudo/npm als root."
  if ! confirm "Besitz von $prefix/lib und $prefix/bin auf $USER setzen (sudo chown)?"; then
    return 1
  fi
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  run_root chown -R "$USER:$USER" "$prefix/lib" "$prefix/bin" 2>/dev/null \
    || run_root chown -R "$USER:$USER" "$prefix"
}

extra_apps_node_user_prepare() {
  local prefix
  prefix="$(extra_apps_node_user_prefix)"
  if ! extra_apps_node_user_dir_writable "$prefix"; then
    extra_apps_node_user_fix_permissions "$prefix" || {
      prefix="$CONFIG_DIR/npm"
      warn "Nutze alternativen npm-Prefix: $prefix"
      extra_apps_config_set NPM_CONFIG_PREFIX "$prefix"
    }
  fi
  mkdir -p "$prefix/bin" "$prefix/lib/node_modules"
  echo "$prefix"
}

extra_apps_bob_cli_run_install_script() {
  local pm="$1" remote url
  remote="$(extra_apps_bob_cli_fetch_version)" || {
    warn "Bob-CLI-Version nicht ermittelbar."
    return 1
  }
  url="${BOB_CLI_BASE_URL}/bobshell-${remote}.tgz"
  log "Direktes Paket: bobshell-${remote}.tgz"
  extra_apps_bob_cli_run_pm_global "$pm" "$url"
}

extra_apps_bob_cli_run_pm_global() {
  local pm="$1" url="$2"
  local prefix rc=0
  prefix="$(extra_apps_node_user_prepare)"
  case "$pm" in
    npm)
      extra_apps_run_user env npm_config_prefix="$prefix" \
        npm install --registry=https://registry.npmjs.org/ --progress=false --loglevel=error -g "$url" \
        || rc=1
      ;;
    pnpm)
      extra_apps_run_user env PNPM_HOME="$prefix" npm_config_prefix="$prefix" \
        pnpm add --registry=https://registry.npmjs.org/ -g "$url" \
        || rc=1
      ;;
    yarn)
      extra_apps_run_user env npm_config_prefix="$prefix" \
        YARN_REGISTRY=https://registry.npmjs.org/ yarn global add "$url" \
        || rc=1
      ;;
    *)
      warn "Unbekannter Paketmanager: $pm"
      return 1
      ;;
  esac
  [[ "$rc" -eq 0 ]]
}

extra_apps_profile() {
  CURSOR_IDE_METHOD="$(extra_apps_cursor_ide_detect)"
  CURSOR_CLI_METHOD="$(extra_apps_cursor_cli_detect)"
  BOB_IDE_METHOD="$(extra_apps_bob_ide_detect)"
  BOB_CLI_METHOD="$(extra_apps_bob_cli_detect)"
  BOB_CLI_PM="$(extra_apps_bob_cli_pm_detect || true)"
  HERDR_METHOD="$(extra_apps_herdr_detect)"
  PI_METHOD="$(extra_apps_pi_detect)"
  PI_CLI_PM="$(extra_apps_pi_pm_detect || true)"
  FIRSTMATE_METHOD="$(extra_apps_firstmate_detect)"
  FIRSTMATE_ROOT="$(extra_apps_firstmate_root || true)"
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
  extra_apps_bob_cli_run_install_script "$pm" || return 1
  if [[ -x "$(extra_apps_node_user_prefix)/bin/bob" ]]; then
    log "Bob CLI installiert: $(extra_apps_node_user_prefix)/bin/bob"
  elif have_cmd bob; then
    log "Bob CLI installiert: $(command -v bob)"
  else
    warn "Bob CLI nach Installation nicht gefunden – PATH prüfen: $(extra_apps_node_user_prefix)/bin"
  fi
}

extra_apps_bob_cli_update() {
  local install="${1:-0}" pm remote installed_ver url
  if [[ "$(extra_apps_bob_cli_detect)" == none ]]; then
    if [[ "$install" -eq 1 ]]; then
      extra_apps_bob_cli_install
    else
      log "IBM Bob CLI nicht installiert – übersprungen."
    fi
    return 0
  fi

  remote="$(extra_apps_bob_cli_fetch_version || true)"
  installed_ver="$(extra_apps_bob_cli_version || true)"
  log "IBM Bob CLI: installiert ${installed_ver:-unbekannt}, verfügbar ${remote:-?}"

  if [[ -n "$remote" && -n "$installed_ver" && "$installed_ver" == "$remote" ]]; then
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
  extra_apps_config_load
  if [[ "${AGENT_STACK_WITH_APPS:-0}" -eq 1 ]]; then
    extra_apps_agent_stack_update "$install"
  fi
}

# ── Agent-Stack: Herdr + Pi + Firstmate ──────────────────────────────────────

extra_apps_herdr_bin() {
  local c
  if [[ -x "$HOME/.local/bin/herdr" ]]; then
    echo "$HOME/.local/bin/herdr"
    return 0
  fi
  if have_cmd herdr; then
    command -v herdr
    return 0
  fi
  return 1
}

extra_apps_herdr_detect() {
  extra_apps_config_load
  if [[ "${SKIP_HERDR:-0}" -eq 1 ]]; then
    echo skipped
    return 0
  fi
  if extra_apps_herdr_bin >/dev/null; then
    echo herdr
  else
    echo none
  fi
}

extra_apps_herdr_version() {
  local bin out
  bin="$(extra_apps_herdr_bin || true)"
  [[ -n "$bin" ]] || return 1
  out="$("$bin" --version 2>/dev/null | head -1 || true)"
  out="${out#herdr }"
  out="${out//[$'\t\r\n']/}"
  [[ -n "$out" ]] && echo "$out"
}

extra_apps_herdr_update() {
  local bin before after
  extra_apps_config_load
  if [[ "${SKIP_HERDR:-0}" -eq 1 ]]; then
    log "Herdr: übersprungen (SKIP_HERDR=1)."
    return 0
  fi
  bin="$(extra_apps_herdr_bin || true)"
  if [[ -z "$bin" ]]; then
    log "Herdr nicht installiert – übersprungen."
    return 0
  fi

  before="$(extra_apps_herdr_version || echo unbekannt)"
  log "Herdr: installiert $before ($bin)"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] $bin update"
    return 0
  fi
  if ! confirm "Herdr aktualisieren (herdr update)?"; then
    log "Herdr-Update abgebrochen."
    return 0
  fi

  log "Aktualisiere Herdr …"
  # Immer als realer Benutzer, nie als root (Self-Update schreibt nach ~/.local)
  if ! extra_apps_run_user "$bin" update; then
    warn "Herdr-Update fehlgeschlagen."
    return 1
  fi
  after="$(extra_apps_herdr_version || echo unbekannt)"
  log "Herdr: vorher $before → nachher $after"
}

extra_apps_pi_bin() {
  local c prefix
  if [[ -x "$HOME/.local/bin/pi" ]]; then
    echo "$HOME/.local/bin/pi"
    return 0
  fi
  prefix="$(extra_apps_node_user_prefix)"
  if [[ -x "$prefix/bin/pi" ]]; then
    echo "$prefix/bin/pi"
    return 0
  fi
  if have_cmd pi; then
    command -v pi
    return 0
  fi
  return 1
}

extra_apps_pi_detect() {
  extra_apps_config_load
  if [[ "${SKIP_PI:-0}" -eq 1 ]]; then
    echo skipped
    return 0
  fi
  if extra_apps_pi_bin >/dev/null; then
    echo pi
  else
    echo none
  fi
}

extra_apps_pi_version() {
  local bin out
  bin="$(extra_apps_pi_bin || true)"
  [[ -n "$bin" ]] || return 1
  out="$("$bin" --version 2>/dev/null | head -1 || true)"
  out="${out//[$'\t\r\n']/}"
  [[ -n "$out" ]] && echo "$out"
}

extra_apps_pi_pm_detect() {
  local pm
  extra_apps_config_load
  if [[ -n "${PI_CLI_PM:-}" ]]; then
    echo "$PI_CLI_PM"
    return 0
  fi
  for pm in npm pnpm yarn; do
    have_cmd "$pm" || continue
    if "$pm" list -g --depth=0 2>/dev/null | grep -qiE 'pi-coding-agent|@earendil-works/pi'; then
      echo "$pm"
      return 0
    fi
  done
  return 1
}

extra_apps_pi_pm_pick() {
  local pm
  extra_apps_config_load
  [[ -n "${PI_CLI_PM:-}" ]] && { echo "$PI_CLI_PM"; return 0; }
  pm="$(extra_apps_pi_pm_detect || true)"
  [[ -n "$pm" ]] && { echo "$pm"; return 0; }
  for pm in npm pnpm yarn; do
    have_cmd "$pm" && { echo "$pm"; return 0; }
  done
  return 1
}

extra_apps_pi_run_pm_global() {
  local pm="$1" pkg="$2"
  local prefix rc=0
  prefix="$(extra_apps_node_user_prepare)"
  case "$pm" in
    npm)
      extra_apps_run_user env npm_config_prefix="$prefix" \
        npm install --registry=https://registry.npmjs.org/ --progress=false --loglevel=error -g "$pkg" \
        || rc=1
      ;;
    pnpm)
      extra_apps_run_user env PNPM_HOME="$prefix" npm_config_prefix="$prefix" \
        pnpm add --registry=https://registry.npmjs.org/ -g "$pkg" \
        || rc=1
      ;;
    yarn)
      extra_apps_run_user env npm_config_prefix="$prefix" \
        YARN_REGISTRY=https://registry.npmjs.org/ yarn global add "$pkg" \
        || rc=1
      ;;
    *)
      warn "Unbekannter Paketmanager: $pm"
      return 1
      ;;
  esac
  [[ "$rc" -eq 0 ]]
}

extra_apps_pi_update() {
  local pm before after
  extra_apps_config_load
  if [[ "${SKIP_PI:-0}" -eq 1 ]]; then
    log "Pi: übersprungen (SKIP_PI=1)."
    return 0
  fi
  if [[ "$(extra_apps_pi_detect)" == none ]]; then
    log "Pi (pi-coding-agent) nicht installiert – übersprungen."
    return 0
  fi

  before="$(extra_apps_pi_version || echo unbekannt)"
  log "Pi: installiert $before ($PI_NPM_PKG)"

  pm="$(extra_apps_pi_pm_pick)" || {
    warn "Kein npm/pnpm/yarn gefunden – Pi kann nicht aktualisiert werden."
    return 1
  }

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] $pm install -g ${PI_NPM_PKG}@latest"
    return 0
  fi
  if ! confirm "Pi ($PI_NPM_PKG) mit $pm aktualisieren?"; then
    log "Pi-Update abgebrochen."
    return 0
  fi

  extra_apps_config_set PI_CLI_PM "$pm"
  log "Aktualisiere Pi ($pm) …"
  if ! extra_apps_pi_run_pm_global "$pm" "${PI_NPM_PKG}@latest"; then
    warn "Pi-Update fehlgeschlagen."
    return 1
  fi
  after="$(extra_apps_pi_version || echo unbekannt)"
  log "Pi: vorher $before → nachher $after"
}

extra_apps_firstmate_looks_like_root() {
  local root="$1"
  [[ -n "$root" && -d "$root" ]] || return 1
  [[ -x "$root/bin/fm-update.sh" ]] || return 1
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

extra_apps_firstmate_root() {
  local cand cfg_home
  # Env vor config_load sichern (leere Config-Zeilen überschreiben sonst die Umgebung)
  local env_firstmate="${FIRSTMATE_HOME:-}"
  local env_fm_home="${FM_HOME:-}"
  local env_fm_root="${FM_ROOT:-}"
  local env_firstmate_root="${FIRSTMATE_ROOT:-}"

  extra_apps_config_load
  cfg_home="${FIRSTMATE_HOME:-}"

  # 1) Nicht-leerer Config-Override
  if [[ -n "$cfg_home" ]] && extra_apps_firstmate_looks_like_root "$cfg_home"; then
    echo "$cfg_home"
    return 0
  fi

  # 2) Umgebungsvariablen (vor dem Sourcen der Config)
  for cand in "$env_firstmate" "$env_fm_home" "$env_fm_root" "$env_firstmate_root"; do
    [[ -n "$cand" ]] || continue
    if extra_apps_firstmate_looks_like_root "$cand"; then
      echo "$cand"
      return 0
    fi
  done

  # 3) Übliche Installationsorte
  for cand in \
    "$HOME/dtry-agent-workspace" \
    "$HOME/firstmate" \
    "$HOME/.local/share/firstmate" \
    "$HOME/src/firstmate" \
    "$HOME/code/firstmate"; do
    if extra_apps_firstmate_looks_like_root "$cand"; then
      echo "$cand"
      return 0
    fi
  done

  return 1
}

extra_apps_firstmate_detect() {
  extra_apps_config_load
  if [[ "${SKIP_FIRSTMATE:-0}" -eq 1 ]]; then
    echo skipped
    return 0
  fi
  if extra_apps_firstmate_root >/dev/null; then
    echo firstmate
  else
    echo none
  fi
}

extra_apps_firstmate_version() {
  local root short branch dirty
  root="$(extra_apps_firstmate_root || true)"
  [[ -n "$root" ]] || return 1
  short="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || true)"
  [[ -n "$short" ]] || return 1
  branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
  dirty=""
  if [[ -n "$(git -C "$root" status --porcelain 2>/dev/null || true)" ]]; then
    dirty=" dirty"
  fi
  echo "${short} (${branch}${dirty})"
}

extra_apps_firstmate_update() {
  local root script before after rc=0
  extra_apps_config_load
  if [[ "${SKIP_FIRSTMATE:-0}" -eq 1 ]]; then
    log "Firstmate: übersprungen (SKIP_FIRSTMATE=1)."
    return 0
  fi

  root="$(extra_apps_firstmate_root || true)"
  if [[ -z "$root" ]]; then
    log "Firstmate-Root nicht gefunden – übersprungen."
    log "Hinweis: FIRSTMATE_HOME in $EXTRA_APPS_CONFIG setzen oder FM_HOME exportieren."
    return 0
  fi

  script="$root/bin/fm-update.sh"
  if [[ ! -x "$script" ]]; then
    warn "Firstmate-Update-Skript fehlt oder nicht ausführbar: $script"
    return 1
  fi

  before="$(extra_apps_firstmate_version || echo unbekannt)"
  log "Firstmate: $root – $before"
  log "Update nur per Fast-Forward (fm-update.sh; kein force/stash)."

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] $script"
    return 0
  fi
  if ! confirm "Firstmate aktualisieren (fm-update.sh, nur Fast-Forward)?"; then
    log "Firstmate-Update abgebrochen."
    return 0
  fi

  log "Aktualisiere Firstmate …"
  # Ausgabe durchreichen, damit skip/dirty/diverged sichtbar bleibt
  if ! extra_apps_run_user env FM_HOME="$root" FM_ROOT="$root" "$script"; then
    rc=1
    warn "Firstmate-Update meldete einen Fehler (siehe Ausgabe oben; dirty/diverged = übersprungen)."
  fi
  after="$(extra_apps_firstmate_version || echo unbekannt)"
  log "Firstmate: vorher $before → nachher $after"
  return "$rc"
}

extra_apps_agent_stack_update() {
  # $1 install-flag reserved for API-Symmetrie zu cursor/bob (derzeit ungenutzt)
  : "${1:-0}"
  log "Agent-Stack: Herdr + Pi + Firstmate"
  extra_apps_profile
  log "Agent-Stack: Herdr=${HERDR_METHOD}, Pi=${PI_METHOD}, Firstmate=${FIRSTMATE_METHOD}${FIRSTMATE_ROOT:+ ($FIRSTMATE_ROOT)}"
  extra_apps_herdr_update
  extra_apps_pi_update
  extra_apps_firstmate_update
}

extra_apps_status_line() {
  local label="$1" method="$2" detail="${3:-}"
  if [[ "$method" == none ]]; then
    echo "  $label: nicht installiert${detail:+ ($detail)}"
  elif [[ "$method" == skipped ]]; then
    echo "  $label: übersprungen (Konfiguration)${detail:+ ($detail)}"
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

  echo
  echo "── Agent-Stack (Herdr / Pi / Firstmate) ──"
  if [[ "$HERDR_METHOD" == herdr ]]; then
    ver="$(extra_apps_herdr_version || echo '?')"
    path="$(extra_apps_herdr_bin || echo '?')"
    extra_apps_status_line "Herdr" "herdr" "$ver – $path"
  else
    extra_apps_status_line "Herdr" "$HERDR_METHOD"
  fi
  if [[ "$PI_METHOD" == pi ]]; then
    ver="$(extra_apps_pi_version || echo '?')"
    extra_apps_status_line "Pi" "pi${PI_CLI_PM:+ ($PI_CLI_PM)}" "$ver – $PI_NPM_PKG"
  else
    extra_apps_status_line "Pi" "$PI_METHOD"
  fi
  if [[ "$FIRSTMATE_METHOD" == firstmate ]]; then
    ver="$(extra_apps_firstmate_version || echo '?')"
    path="${FIRSTMATE_ROOT:-$(extra_apps_firstmate_root || echo '?')}"
    extra_apps_status_line "Firstmate" "firstmate" "$ver – $path"
  else
    extra_apps_status_line "Firstmate" "$FIRSTMATE_METHOD"
  fi

  echo "  Konfiguration: $EXTRA_APPS_CONFIG"
}

extra_apps_update_after_packages() {
  extra_apps_config_load
  if [[ "${EXTRA_APPS_WITH_UPDATE:-1}" -eq 1 ]]; then
    extra_apps_update_all 0
  fi
  if [[ "${AGENT_STACK_WITH_UPDATE:-0}" -eq 1 ]]; then
    # Agent-Stack separat, falls EXTRA_APPS_WITH_UPDATE=0 oder AGENT_STACK_WITH_APPS=0
    if [[ "${EXTRA_APPS_WITH_UPDATE:-1}" -ne 1 || "${AGENT_STACK_WITH_APPS:-0}" -ne 1 ]]; then
      extra_apps_agent_stack_update 0
    fi
  fi
}
