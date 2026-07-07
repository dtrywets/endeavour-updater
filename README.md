# endeavour-updater

Wartungsskript für **Arch Linux** und **EndeavourOS** — interaktives Menü, Cronjobs und CLI für Updates, Aufräumen und Sonderfälle (AUR, Cursor, IBM Bob, iacs).

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
| `node` + `npm`/`pnpm`/`yarn` | IBM Bob CLI |

## Installation

Repository klonen und Skript ausführbar machen:

```bash
git clone https://github.com/dtrywets/endeavour-updater.git
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
| 10 | Cursor IDE/CLI und IBM Bob |

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
endeavour-updater --apps                # alles Erkannte
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
| `update` | So 06:00 | `yay -Syu` / pacman, Cursor/Bob, `.pacnew`-Hinweis |
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
| `extra-apps.conf` | Cursor AppImage-Pfad, Version, Bob IDE/CLI, Cron-Integration |
| `aur-sources/iacs/` | IBM-ZIP für AUR-Paket `iacs` |
| `logs/` | Cron- und Laufzeit-Logs |

**Waisen-Schutz:** Standardmäßig geschützt sind `xrdp-git` und `xorgxrdp-git`. Weitere Pakete — eine Zeile pro Name in `orphan-protect`.

**Zusatz-Apps abschalten** (kein Cursor/Bob bei `--update` / Cron):

```bash
# in extra-apps.conf
EXTRA_APPS_WITH_UPDATE=0
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
    └── extra_apps.sh      # Cursor & IBM Bob
```

## Portable vs. installiert

| Modus | Aufruf | Speicherort |
|-------|--------|-------------|
| Portable | `./endeavour-updater` aus dem Clone | Projektordner |
| Installiert | `endeavour-updater` | `~/.local/share/endeavour-updater` + `~/.local/bin` |
