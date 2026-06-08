# AUR-Pakete mit manuellen Quelldateien (nicht automatisch herunterladbar)

: "${AUR_SOURCES_DIR:=$CONFIG_DIR/aur-sources}"

IACS_PKG='iacs'
IACS_ZIP='IBMiAccess_v1r1.zip'
IACS_URL='https://www.ibm.com/support/pages/ibm-i-access-client-solutions'

aur_sources_iacs_store_dir() {
  echo "$AUR_SOURCES_DIR/$IACS_PKG"
}

aur_sources_iacs_zip_path() {
  echo "$(aur_sources_iacs_store_dir)/$IACS_ZIP"
}

aur_sources_iacs_installed() {
  pacman -Qi "$IACS_PKG" &>/dev/null
}

aur_sources_iacs_update_pending() {
  have_cmd yay || return 1
  aur_sources_iacs_installed || return 1
  yay -Qu 2>/dev/null | awk '{print $1}' | grep -Fxq "$IACS_PKG"
}

aur_sources_iacs_expected_sha256() {
  local builddir tmp
  if ! have_cmd yay; then
    return 1
  fi
  builddir="$(mktemp -d)"
  if ! (cd "$builddir" && yay -G "$IACS_PKG" &>/dev/null); then
    rm -rf "$builddir"
    return 1
  fi
  tmp="$(awk -F"'" '/^sha256sums=/{print $2; exit}' "$builddir/$IACS_PKG/PKGBUILD" 2>/dev/null || true)"
  rm -rf "$builddir"
  [[ -n "$tmp" ]] || return 1
  echo "$tmp"
}

aur_sources_iacs_verify_zip() {
  local file="$1"
  local expected actual
  [[ -r "$file" ]] || return 1
  expected="$(aur_sources_iacs_expected_sha256)" || return 1
  actual="$(sha256sum "$file" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]]
}

aur_sources_iacs_try_migrate() {
  local dest candidate
  dest="$(aur_sources_iacs_zip_path)"
  [[ -f "$dest" ]] && return 0

  local candidates=(
    "$HOME/.cache/yay/$IACS_PKG/$IACS_ZIP"
    "$HOME/Downloads/$IACS_ZIP"
  )
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]] && aur_sources_iacs_verify_zip "$candidate"; then
      aur_sources_iacs_import "$candidate" 0
      return 0
    fi
  done
  return 1
}

aur_sources_iacs_import() {
  local src="${1:?Quelldatei angeben}"
  local verbose="${2:-1}"
  local dest dir
  dest="$(aur_sources_iacs_zip_path)"
  dir="$(aur_sources_iacs_store_dir)"

  [[ -r "$src" ]] || die "Datei nicht lesbar: $src"
  aur_sources_iacs_verify_zip "$src" || die "SHA256 passt nicht zur aktuellen iacs-PKGBUILD – evtl. neue IBM-Version nötig."

  mkdir -p "$dir"
  [[ "$DRY_RUN" -eq 1 ]] && { log "[dry-run] kopiere $src → $dest"; return 0; }
  cp -f "$src" "$dest"
  chmod 644 "$dest"
  [[ "$verbose" -eq 1 ]] && log "iacs-Quelle gespeichert: $dest"
}

aur_sources_iacs_zip_ready() {
  local zip
  zip="$(aur_sources_iacs_zip_path)"
  [[ -f "$zip" ]] && aur_sources_iacs_verify_zip "$zip" && return 0
  aur_sources_iacs_try_migrate || true
  [[ -f "$zip" ]] && aur_sources_iacs_verify_zip "$zip"
}

aur_sources_iacs_warn_missing() {
  warn "iacs-Update übersprungen: $IACS_ZIP fehlt oder ist ungültig."
  warn "IBM i Access Client Solutions (kostenlos mit IBMid):"
  warn "  $IACS_URL"
  warn "ZIP ablegen und importieren:"
  warn "  endeavour-updater --iacs-import /pfad/zu/$IACS_ZIP"
  warn "Speicherort: $(aur_sources_iacs_zip_path)"
}

aur_sources_run_as_update_user() {
  if [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    sudo -u "$SUDO_USER" -H -- "$@"
  else
    "$@"
  fi
}

aur_sources_iacs_update() {
  local zip builddir
  zip="$(aur_sources_iacs_zip_path)"
  aur_sources_iacs_zip_ready || { aur_sources_iacs_warn_missing; return 1; }

  builddir="$(mktemp -d)"
  log "iacs: separater Build (manuelle IBM-Quelle) …"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] yay -G $IACS_PKG; cp Quelle; makepkg -si in $builddir"
    rm -rf "$builddir"
    return 0
  fi

  local rc=0
  if ! aur_sources_run_as_update_user bash -c "
    set -euo pipefail
    cd '$builddir'
    yay -G '$IACS_PKG'
    cp -f '$zip' '$IACS_PKG/'
    cd '$IACS_PKG'
    makepkg -si --noconfirm
  "; then
    rc=1
    warn "iacs-Build fehlgeschlagen – siehe Ausgabe oben."
  fi
  rm -rf "$builddir"
  return "$rc"
}

# Vor yay -Syu: iacs ggf. ignorieren und danach separat bauen.
# Setzt AUR_SOURCES_EXTRA_IGNORE (Array) und AUR_SOURCES_POST_UPDATE (Funktionsname).
aur_sources_prepare_package_updates() {
  AUR_SOURCES_EXTRA_IGNORE=()
  AUR_SOURCES_POST_UPDATE=''

  aur_sources_iacs_update_pending || return 0

  if aur_sources_iacs_zip_ready; then
    AUR_SOURCES_EXTRA_IGNORE+=(--ignore "$IACS_PKG")
    AUR_SOURCES_POST_UPDATE='aur_sources_iacs_update'
    log "iacs-Update ausstehend – IBM-ZIP bereit, separater Build nach Haupt-Update."
  else
    AUR_SOURCES_EXTRA_IGNORE+=(--ignore "$IACS_PKG")
    aur_sources_iacs_warn_missing
  fi
}

aur_sources_run_post_update() {
  [[ -n "${AUR_SOURCES_POST_UPDATE:-}" ]] || return 0
  if [[ "$EUID" -eq 0 && -n "${SUDO_USER:-}" ]]; then
    aur_sources_run_as_update_user bash -c "
      export CONFIG_DIR='$CONFIG_DIR' DRY_RUN='$DRY_RUN' LOG_TAG='$LOG_TAG'
      source '$UPDATER_ROOT/lib/common.sh'
      source '$UPDATER_ROOT/lib/aur_sources.sh'
      $AUR_SOURCES_POST_UPDATE
    " || true
  else
    "$AUR_SOURCES_POST_UPDATE" || true
  fi
}
