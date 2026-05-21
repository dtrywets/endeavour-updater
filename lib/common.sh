# Gemeinsame Hilfsfunktionen (wird von endeavour-updater gesourct)
# shellcheck shell=bash

: "${LOG_TAG:=endeavour-updater}"
: "${CONFIG_DIR:=$HOME/.config/endeavour-updater}"
: "${CONFIG_FILE:=$CONFIG_DIR/install.conf}"
: "${LOG_DIR:=$CONFIG_DIR/logs}"
: "${NONINTERACTIVE:=0}"
: "${DRY_RUN:=0}"
: "${YES:=0}"

log()  { printf '[%s] %s\n' "$LOG_TAG" "$*"; }
warn() { printf '[%s] WARNUNG: %s\n' "$LOG_TAG" "$*" >&2; }
die()  { printf '[%s] FEHLER: %s\n' "$LOG_TAG" "$*" >&2; exit 1; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

is_tty() { [[ -t 0 && -t 1 ]]; }

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] $*"
    return 0
  fi
  log "→ $*"
  "$@"
}

as_root() {
  if [[ "$EUID" -eq 0 ]]; then
    "$@"
  elif have_cmd sudo; then
    sudo "$@"
  else
    die "Root-Rechte nötig für: $*"
  fi
}

run_root() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "[dry-run] (root) $*"
    return 0
  fi
  log "→ (root) $*"
  as_root "$@"
}

confirm() {
  local prompt="$1"
  [[ "$YES" -eq 1 || "$NONINTERACTIVE" -eq 1 ]] && return 0
  [[ "$DRY_RUN" -eq 1 ]] && return 0
  read -r -p "${prompt} [j/N] " ans
  [[ "${ans,,}" == "j" || "${ans,,}" == "ja" || "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

pause_menu() {
  [[ "$NONINTERACTIVE" -eq 1 ]] && return 0
  echo
  read -r -p "Enter zum Fortfahren …" _
}

ensure_pacman() {
  have_cmd pacman || die "pacman nicht gefunden – Arch-basiertes System erwartet."
}

cron_log() {
  mkdir -p "$LOG_DIR"
  echo "$*"
}
