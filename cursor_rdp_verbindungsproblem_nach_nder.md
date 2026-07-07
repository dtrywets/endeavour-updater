# RDP-Verbindungsproblem nach Änderungen
_Exported on 6/9/2026 at 09:40:37 GMT+2 from Cursor (3.6.31)_

---

**User**

nach den letzten arbeiten funktioniert mein rdp nicht mehr. 

---

**Cursor**

RDP-Ausfall nach den letzten Änderungen — ich schaue zuerst im Workspace nach RDP-Konfiguration und kürzlichen Anpassungen.


Ich prüfe jetzt den lokalen RDP-Status: Dienste, Ports und Logs.


Ursache: `xrdp-git` wurde am 8.6. deinstalliert, stabiles `xrdp` gibt es hier nicht — ich stelle RDP jetzt wieder her.


**Ursache:** `xrdp-git` war komplett deinstalliert — deshalb kein Dienst, kein `/etc/xrdp`, Port 3389 nicht offen.

Am **8. Juni um 08:40** wurde `xrdp-git` zusammen mit anderen Paketen entfernt (`pacman -Rns … xrdp-git`). Stabiles `xrdp` aus den offiziellen Repos gibt es auf prodesk nicht; nach dem Entfernen von `xrdp-git` blieb nur noch `xorgxrdp-git` übrig, ohne funktionierenden RDP-Server.

**Behoben:** `apply-xrdp-like-vm88.sh` ausgeführt:

- `xrdp-git` neu installiert (über yay)
- Konfiguration aus dem Repo nach `/etc/xrdp` kopiert
- `xrdp` + `xrdp-sesman` aktiv, **Port 3389 lauscht**
- Firewall: 3389/tcp ist erlaubt

Du kannst dich wieder per RDP verbinden: **prodesk, Port 3389**, Session **Xorg** → KDE Plasma (X11).

**Hinweis für später:** Bei `pacman -Rns $(pacman -Qtdq)` oder ähnlichen Aufräum-Aktionen `xrdp-git` nicht mit entfernen — es ist auf diesem Rechner der einzige RDP-Server. Wenn RDP wieder weg ist, reicht:

```bash
sudo ./scripts/apply-xrdp-like-vm88.sh
```

Bitte kurz testen, ob der Login und der Desktop wie gewohnt erscheinen. Wenn etwas hakt (schwarzer Bildschirm, Login-Fehler), sag Bescheid — dann schauen wir in die Session-Logs.

