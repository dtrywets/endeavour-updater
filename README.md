# endeavour-updater

Wartung für **Arch Linux** und **EndeavourOS** (Menü, Installation, Cron).  
Orientierung: [EOS Maintenance Guide](https://forum.endeavouros.com/t/a-complete-idiots-guide-to-endeavour-os-maintenance-update-upgrade/25184).

## Schnellstart

```bash
cd scripts/endeavour-updater
chmod +x endeavour-updater
./endeavour-updater
```

Beim ersten Start: Menü **8** → Installation, optional Cronjobs (**7**).

Oder direkt:

```bash
./endeavour-updater --install
```

Danach (neue Shell oder `hash -r`):

```bash
endeavour-updater
```

## Cron / cronie

Bei **`--install`** und **`--cron-install`** wird standardmäßig das Paket **`cronie`** installiert (liefert `crontab`) und der Dienst `cronie.service` aktiviert. Dafür sind sudo-Rechte nötig.

Unterdrücken:

```bash
./endeavour-updater --install --no-cron      # weder cronie noch Cronjobs
./endeavour-updater --install --no-cronie    # cronie nicht installieren; Jobs nur wenn crontab existiert
```

Nur cronie nachinstallieren:

```bash
endeavour-updater --install-cronie
```

## Empfohlene Zyklen (Cron)

| Aufgabe | Zeitplan | Inhalt |
|--------|----------|--------|
| `update` | Sonntag 06:00 | `yay -Syu` / pacman, Hinweis auf .pacnew |
| `monthly` | 1. des Monats 07:00 | Spiegel (reflector + eos-rankmirrors), `-Syyu`, Journal, Cache |

Waisen werden per Cron **nicht** automatisch entfernt (nur im interaktiven Menü mit Bestätigung).

Geschützte Pakete (z. B. `xrdp-git`, `xorgxrdp-git` für RDP) werden bei der Waisen-Bereinigung **nie** entfernt. Weitere Namen in `~/.config/endeavour-updater/orphan-protect` (eine Zeile pro Paket).

Logs: `~/.config/endeavour-updater/logs/`

## Cron steuern

```bash
endeavour-updater --cron-status
endeavour-updater --cron-install
endeavour-updater --cron-remove
```

Manueller Cron-Aufruf (wie in crontab):

```bash
endeavour-updater --cron update -y
endeavour-updater --cron monthly -y
```

## Portable vs. installiert

- **Portable:** `./endeavour-updater` aus dem Projektordner.
- **Installiert:** Kopie nach `~/.local/share/endeavour-updater`, Link `~/.local/bin/endeavour-updater`.

Aktualisieren nach Git-Pull:

```bash
./endeavour-updater --upgrade
```

## AUR-Paket iacs (IBM i Access)

Das AUR-Paket `iacs` benötigt die ZIP-Datei `IBMiAccess_v1r1.zip` von IBM (kostenlos mit IBMid). yay kann sie nicht automatisch laden; beim Rebuild wird die Datei im Cache gelöscht.

Der Updater speichert die ZIP dauerhaft unter `~/.config/endeavour-updater/aur-sources/iacs/` und baut `iacs` beim Update **nach** dem normalen `yay -Syu` separat. Fehlt die Datei, wird `iacs` übersprungen (andere Pakete werden trotzdem aktualisiert).

```bash
# Nach Download von IBM:
endeavour-updater --iacs-import ~/Downloads/IBMiAccess_v1r1.zip
endeavour-updater --update
```

Bereits vorhandene Kopien in `~/.cache/yay/iacs/` oder `~/Downloads/` werden beim ersten Lauf automatisch übernommen, sofern die Prüfsumme passt.

## Cursor IDE und IBM Bob

Der Updater kann **Cursor IDE** und **IBM Bob** (`ibm-bob-bin` aus dem AUR) separat oder zusammen mit dem Paket-Update aktualisieren.

| Installation | Update-Methode |
|--------------|----------------|
| Cursor als AppImage (`~/Applications/cursor.AppImage` o. Ä.) | Offizielle Cursor-API, Download der neuesten AppImage |
| Cursor als AUR-Paket `cursor-bin` | `yay -S cursor-bin` |
| IBM Bob als AUR-Paket `ibm-bob-bin` | `yay -S ibm-bob-bin` |

```bash
endeavour-updater --cursor      # nur Cursor
endeavour-updater --ibm-bob     # nur IBM Bob
endeavour-updater --apps        # beide
```

Bei `--update` und im wöchentlichen Cron werden installierte Zusatz-Anwendungen automatisch mit aktualisiert (abschaltbar in `~/.config/endeavour-updater/extra-apps.conf`: `EXTRA_APPS_WITH_UPDATE=0`).

Im Menü: **10) Cursor IDE / IBM Bob**.

Bei einer **bestehenden AppImage-Installation** kann die lokale Version einmalig in `extra-apps.conf` gesetzt werden (`CURSOR_APPIMAGE_VERSION=3.8.11`). Nach dem ersten Update übernimmt der Updater das automatisch.

## Abhängigkeiten (optional)

- `yay` – AUR-Updates (Cursor/IBM Bob)
- `curl` – Cursor AppImage-Updates
- `reflector` – Arch-Spiegel
- `eos-rankmirrors` – Endeavour-Spiegel
- `pacman-contrib` – `paccache`, `pacdiff`
- `meld` – für `--pacdiff`
