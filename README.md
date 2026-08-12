# endeavour-updater

Wartungsskript für **Arch Linux** und **EndeavourOS** — interaktives Menü, Cronjobs und CLI für Updates, Aufräumen und Sonderfälle (AUR, Cursor, IBM Bob, Agent-Stack, iacs).

Orientierung am [EndeavourOS Maintenance Guide](https://forum.endeavouros.com/t/a-complete-idiots-guide-to-endeavour-os-maintenance-update-upgrade/25184).

## Inhalt

- [Features](#features)
- [Voraussetzungen](#voraussetzungen)
- [Installation](#installation)
- [Erste Schritte](#erste-schritte)
- [Verwendung](#verwendung)
- [Automatisierung](#automatisierung)
- [Konfiguration](#konfiguration)
- [Sonderfälle](#sonderfälle)
- [Projektstruktur](#projektstruktur)

## Features

- Paket-Updates mit `yay` oder `pacman` (`-Syu` / `-Syyu`)
- Spiegel sortieren (`reflector`, `eos-rankmirrors`)
- Journal und Pacman-Cache bereinigen
- Waisen-Pakete prüfen und entfernen (mit Schutzliste für kritische Pakete)
- `.pacnew` / `.pacsave` per `pacdiff`
- Cronjobs für wöchentliche und monatliche Wartung
- AUR-Paket `iacs` mit manueller IBM-Quelldatei
- Cursor IDE/CLI und IBM Bob IDE/CLI — Erkennung und passendes Update
- Agent-Stack (Herdr + Pi + Firstmate) — Erkennung und sicheres Update
- Portable Nutzung aus dem Git-Clone oder Installation nach `~/.local`

## Voraussetzungen

| Paket | Zweck |
|-------|--------|
| `pacman` | Basis (Arch/EndeavourOS) |
| `yay` | AUR-Updates (empfohlen) |
| `reflector` | Arch-Spiegel |
| `eos-rankmirrors` | Endeavour-Spiegel |
| `pacman-contrib` | `paccache`, `pacdiff` |
| `cronie` | Cronjobs (wird bei `--install` optional mit eingerichtet) |
| `curl` | Cursor AppImage / CLI |
| `meld` | Interaktives `pacdiff` |
| `node` + `npm`/`pnpm`/`yarn` | IBM Bob CLI, Pi CLI |

## Installation

Repository klonen und Skript ausführbar machen:

```bash
git clone https://github.com/thelad-dev/endeavour-updater.git
cd endeavour-updater
chmod +x endeavour-updater
```

**Empfohlen:** dauerhaft installieren (Kopie nach `~/.local/share`, Symlink in `~/.local/bin`):

```bash
./endeavour-updater --install
```

Stelle sicher, dass `~/.local/bin` in deiner `PATH` steht. Danach reicht:

```bash
endeavour-updater
```

Installation ohne Cronjobs:

```bash
./endeavour-updater --install --no-cron
```

Nach einem `git pull` die installierte Kopie aktualisieren:

```bash
./endeavour-updater --upgrade
```

Deinstallation:

```bash
endeavour-updater --uninstall
```

## Erste Schritte

1. `./endeavour-updater` starten (öffnet das Menü)
2. **8** → Installation (falls noch nicht geschehen)
3. **7** → Cronjobs einrichten (optional, empfohlen)
4. **1** → Erstes Paket-Update

Status prüfen:

```bash
endeavour-updater --status
```

Hilfe und alle Optionen:

```bash
endeavour-updater --help
```

## Verwendung

### Interaktives Menü

| Nr. | Aktion |
|-----|--------|
| 1 | Pakete aktualisieren |
| 2 | Spiegel neu sortieren + vollständiges Update |
| 3 | Aufräumen (Journal, Pacman-Cache) |
| 4 | Waisen-Pakete |
| 5 | `.pacnew` / `.pacsave` |
| 6 | Volle Wartung (Schritt für Schritt) |
| 7 | Cronjobs |
| 8 | Installation / Update / Deinstallation |
| 9 | Hilfe |
| 10 | Zusatz-Apps (Cursor, Bob, Agent-Stack) |

### Kommandozeile

**Wartung**

```bash
endeavour-updater --update      # Paket-Update
endeavour-updater --mirrors     # Spiegel + Sync/Update
endeavour-updater --clean       # Journal + Cache
endeavour-updater --orphans     # Waisen prüfen
endeavour-updater --pacdiff     # Konfigurations-Diffs
endeavour-updater --full        # Volle Wartung (interaktiv)
```

**Zusatz-Anwendungen**

```bash
endeavour-updater --cursor              # Cursor IDE + CLI (nur installiertes)
endeavour-updater --cursor-cli          # nur Cursor CLI
endeavour-updater --ibm-bob             # IBM Bob IDE + CLI
endeavour-updater --ibm-bob-cli         # nur Bob CLI
endeavour-updater --apps                # Cursor + Bob (Agent-Stack optional via Config)
endeavour-updater --agent-stack         # Herdr + Pi + Firstmate
endeavour-updater --herdr-pi-firstmate  # Alias für --agent-stack
endeavour-updater --herdr               # nur Herdr
endeavour-updater --pi                  # nur Pi (pi-coding-agent)
endeavour-updater --firstmate           # nur Firstmate (Fast-Forward)
endeavour-updater --install-cursor-cli  # Cursor CLI installieren
endeavour-updater --install-bob-cli     # Bob CLI installieren
```

**Optionen**

| Option | Beschreibung |
|--------|--------------|
| `-y`, `--yes` | Keine Rückfragen (für Cron) |
| `-n`, `--dry-run` | Nur anzeigen, nichts ausführen |
| `-h`, `--help` | Hilfe |

## Automatisierung

Bei `--install` und `--cron-install` wird standardmäßig `cronie` installiert und aktiviert (sudo nötig).

| Aufgabe | Zeitplan | Inhalt |
|---------|----------|--------|
| `update` | So 06:00 | `yay -Syu` / pacman, Cursor/Bob (Agent-Stack optional), `.pacnew`-Hinweis |
| `monthly` | 1. des Monats 07:00 | Spiegel, `-Syyu`, Journal, Cache |

Cron verwalten:

```bash
endeavour-updater --cron-status
endeavour-updater --cron-install
endeavour-updater --cron-remove
```

Manuell wie in der Crontab:

```bash
endeavour-updater --cron update -y
endeavour-updater --cron monthly -y
```

Nur `cronie` nachinstallieren:

```bash
endeavour-updater --install-cronie
```

Logs: `~/.config/endeavour-updater/logs/`

> Waisen werden per Cron **nicht** automatisch entfernt — nur im interaktiven Menü mit Bestätigung.

## Konfiguration

Alle Dateien unter `~/.config/endeavour-updater/`:

| Datei | Zweck |
|-------|--------|
| `install.conf` | Installationspfade (nach `--install`) |
| `orphan-protect` | Pakete, die bei Waisen-Bereinigung nie entfernt werden |
| `extra-apps.conf` | Cursor, Bob, Agent-Stack, Cron-/Apps-Integration |
| `aur-sources/iacs/` | IBM-ZIP für AUR-Paket `iacs` |
| `logs/` | Cron- und Laufzeit-Logs |

**Waisen-Schutz:** Standardmäßig geschützt sind `xrdp-git` und `xorgxrdp-git`. Weitere Pakete — eine Zeile pro Name in `orphan-protect`.

**Zusatz-Apps abschalten** (kein Cursor/Bob bei `--update` / Cron):

```bash
# in extra-apps.conf
EXTRA_APPS_WITH_UPDATE=0
```

**Agent-Stack optional mitziehen** (Standard: aus — nur Menü / `--agent-stack`):

```bash
# in extra-apps.conf
AGENT_STACK_WITH_UPDATE=1   # bei --update / Cron
AGENT_STACK_WITH_APPS=1     # bei --apps zusätzlich zu Cursor/Bob
FIRSTMATE_HOME=/pfad/zu/firstmate
SKIP_HERDR=0
SKIP_PI=0
SKIP_FIRSTMATE=0
PI_CLI_PM=                  # npm|pnpm|yarn, leer = auto
```

## Sonderfälle

### IBM i Access (`iacs`)

Das AUR-Paket `iacs` braucht `IBMiAccess_v1r1.zip` von IBM (kostenlos mit IBMid). yay kann die Datei nicht automatisch laden.

```bash
endeavour-updater --iacs-import ~/Downloads/IBMiAccess_v1r1.zip
endeavour-updater --update
```

Die ZIP wird dauerhaft unter `aur-sources/iacs/` gespeichert und beim Update separat gebaut. Kopien in `~/.cache/yay/iacs/` oder `~/Downloads/` werden beim ersten Lauf übernommen, wenn die Prüfsumme passt.

### Cursor IDE und IBM Bob

Der Updater erkennt, **was installiert ist**, und wählt die passende Methode:

| Komponente | Erkennung | Update |
|------------|-----------|--------|
| Cursor IDE (AppImage) | `.desktop`, `~/Applications/cursor.AppImage` | Cursor-API |
| Cursor IDE (AUR) | `cursor-bin` | `yay -S cursor-bin` |
| Cursor CLI | `cursor-agent` / `agent` | `cursor-agent update` |
| IBM Bob IDE | `ibm-bob-bin` (AUR) oder `/usr/share/bobide/bobide` | `yay -S ibm-bob-bin` |
| IBM Bob CLI | `bob` (npm/pnpm/yarn) | IBM-Release |

Bei einer bestehenden Cursor-AppImage-Installation kann die Version einmalig gesetzt werden:

```bash
# in extra-apps.conf
CURSOR_APPIMAGE_VERSION=3.8.11
```

Nach dem ersten Update übernimmt der Updater das automatisch.

**Hinweise**

- Updater **nicht als root** starten (`sudo ./endeavour-updater`). Falls doch: Konfiguration liegt unter `/root/.config/…` statt beim Benutzer.
- Bob CLI wird nach `~/.local` installiert (npm-User-Prefix), nicht nach `/usr/lib/node_modules`.
- Schreibrechte auf `~/.local/lib` fehlen? Der Updater bietet `sudo chown` an oder nutzt `~/.config/endeavour-updater/npm` als Fallback.
- Migration von Upstream-Bob zu `ibm-bob-bin` entfernt ggf. das alte Paket `bobide` (Pacman-Konflikt).

### Agent-Stack (Herdr + Pi + Firstmate)

Menüpfad: **10 → Zusatz-Apps** → Einträge 3 / 5–8.

| Komponente | Erkennung | Update |
|------------|-----------|--------|
| Herdr | `~/.local/bin/herdr` oder `herdr` in `PATH` | `herdr update` (als Benutzer, nicht root) |
| Pi | `pi` / `@earendil-works/pi-coding-agent` (npm/pnpm/yarn global) | globales Paket-Update auf `@latest` |
| Firstmate | `FIRSTMATE_HOME` / `FM_HOME` / `FM_ROOT`, Config, oder `~/dtry-agent-workspace` (+ `bin/fm-update.sh`) | `bin/fm-update.sh` — **nur Fast-Forward**, nie force/stash |

```bash
endeavour-updater --agent-stack -y    # alle erkannten Komponenten
endeavour-updater --herdr -y
endeavour-updater --pi -y
endeavour-updater --firstmate -y
```

**Hinweise Agent-Stack**

- Firstmate bei dirty/diverged Working Tree: `fm-update.sh` meldet Skip-Gründe und bricht nicht mit Force durch.
- Herdr-Versionen werden vor und nach dem Update angezeigt.
- Pi nutzt denselben npm-User-Prefix wie Bob CLI (`~/.local` bzw. `NPM_CONFIG_PREFIX`).
- Standard: Agent-Stack **nicht** in `--update` / Cron / `--apps` — nur über Menü oder `--agent-stack`. Optional: `AGENT_STACK_WITH_UPDATE=1` / `AGENT_STACK_WITH_APPS=1`.

## Projektstruktur

```
endeavour-updater/
├── endeavour-updater      # Haupteinstieg
└── lib/
    ├── common.sh          # Hilfsfunktionen, Logging
    ├── maintain.sh        # Wartungsaktionen
    ├── cron.sh            # Cronjob-Verwaltung
    ├── install.sh         # Installation / Deinstallation
    ├── menu.sh            # Interaktives Menü
    ├── aur_sources.sh     # iacs / manuelle AUR-Quellen
    └── extra_apps.sh      # Cursor, IBM Bob, Agent-Stack
```

## Portable vs. installiert

| Modus | Aufruf | Speicherort |
|-------|--------|-------------|
| Portable | `./endeavour-updater` aus dem Clone | Projektordner |
| Installiert | `endeavour-updater` | `~/.local/share/endeavour-updater` + `~/.local/bin` |
