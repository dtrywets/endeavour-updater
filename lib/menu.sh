# Interaktives Hauptmenü

menu_header() {
  clear 2>/dev/null || true
  echo "╔══════════════════════════════════════════════════╗"
  echo "║         Endeavour / Arch – System-Updater        ║"
  echo "╚══════════════════════════════════════════════════╝"
  if install_is_installed; then
    echo "  Installiert: $BIN_PATH"
  else
    echo "  Modus: portable (nicht installiert)"
  fi
  echo
}

menu_show() {
  echo "  1) Pakete aktualisieren (yay/pacman -Syu)"
  echo "  2) Spiegel neu sortieren + vollständiges Update"
  echo "  3) Aufräumen (Journal 4 Wochen + Pacman-Cache)"
  echo "  4) Waisen-Pakete prüfen / entfernen"
  echo "  5) .pacnew / .pacsave (pacdiff)"
  echo "  6) Volle Wartung (Schritt für Schritt)"
  echo "  ─────────────────────────────────────────"
  echo "  7) Cronjobs: Status / installieren / entfernen"
  echo "  8) Installation / Update / Deinstallation"
  echo "  9) Hilfe"
  echo "  0) Beenden"
  echo
}

menu_cron_sub() {
  while true; do
    menu_header
    echo "── Cronjobs ──"
    cron_show_status
    echo
    echo "  1) cronie + Cronjobs installieren (Standard)"
    echo "  2) Nur cronie/crontab installieren"
    echo "  3) Cronjobs entfernen"
    echo "  4) Zurück"
    echo
    read -r -p "Auswahl: " c
    case "${c:-}" in
      1) cron_install_all || true; pause_menu ;;
      2) cron_install_cronie || true; pause_menu ;;
      3)
        if confirm "Alle endeavour-updater Cronjobs wirklich entfernen?"; then
          cron_remove_all
        fi
        pause_menu
        ;;
      4) return ;;
      *) warn "Ungültige Auswahl."; sleep 1 ;;
    esac
  done
}

menu_install_sub() {
  while true; do
    menu_header
    install_status
    echo
    echo "  1) Installieren (nach ~/.local/share + ~/.local/bin)"
    echo "  2) Installation aus diesem Ordner aktualisieren"
    echo "  3) Deinstallieren"
    echo "  4) Zurück"
    echo
    read -r -p "Auswahl: " c
    case "${c:-}" in
      1)
        install_do
        if confirm "Empfohlene Cronjobs jetzt einrichten?"; then
          install_try_cron || true
        fi
        pause_menu
        ;;
      2) install_upgrade; pause_menu ;;
      3)
        if confirm "endeavour-updater komplett deinstallieren?"; then
          install_uninstall
        fi
        pause_menu
        ;;
      4) return ;;
      *) warn "Ungültige Auswahl."; sleep 1 ;;
    esac
  done
}

menu_main_loop() {
  ensure_pacman
  install_ensure || true
  while true; do
    menu_header
    menu_show
    read -r -p "Auswahl: " choice
    case "${choice:-}" in
      1)
        maintain_update_packages 0
        maintain_check_pacnew_reminder
        pause_menu
        ;;
      2)
        maintain_mirrors_all
        maintain_update_packages 1
        maintain_check_pacnew_reminder
        pause_menu
        ;;
      3)
        if confirm "Journal und Pacman-Cache bereinigen?"; then
          maintain_clean_all
        fi
        pause_menu
        ;;
      4) maintain_remove_orphans 0; pause_menu ;;
      5) maintain_run_pacdiff; pause_menu ;;
      6) maintain_interactive_full; pause_menu ;;
      7) menu_cron_sub ;;
      8) menu_install_sub ;;
      9) eu_usage; pause_menu ;;
      0) log "Tschüss."; exit 0 ;;
      *) warn "Ungültige Auswahl."; sleep 1 ;;
    esac
  done
}
