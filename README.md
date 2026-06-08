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

## Abhängigkeiten (optional)

- `yay` – AUR-Updates
- `reflector` – Arch-Spiegel
- `eos-rankmirrors` – Endeavour-Spiegel
- `pacman-contrib` – `paccache`, `pacdiff`
- `meld` – für `--pacdiff`
