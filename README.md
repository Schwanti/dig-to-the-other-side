# Ab durch die Mitte (Dig to the Other Side)

Ein Incremental-Spiel in Ich-Perspektive: Du gräbst von deinem Garten in Deutschland 12.738 km quer durch die Erde, bis du im Südpazifik herauskommst.

- Design-Dokument: https://claude.ai/artifact/UqBxefQH3NcGMzN3jFDbCt
- Browser-Prototyp (Vorlage für alle Werte): https://claude.ai/artifact/Ls8dceZmUjJEHoQPTY67QX

## Projekt öffnen

1. **Godot 4.3 oder neuer** herunterladen: https://godotengine.org/download (die normale Version, nicht ".NET").
2. Godot starten, **Importieren** wählen und die Datei `project.godot` in diesem Ordner auswählen.
3. Mit **F5** (oder dem Play-Knopf oben rechts) starten.

Beim ersten Öffnen legt Godot den Ordner `.godot/` an. Der wird nicht eingecheckt.

## Steuerung

| Taste | Aktion |
| --- | --- |
| Maus | Umschauen |
| W A S D | Laufen |
| Linksklick oder Leertaste | Graben (Presslufthammer: gedrückt halten) |
| F | Leiter hoch oder runter, unterwegs umkehren |
| E | Werkbank im Garten öffnen und schließen |
| Esc | Mauszeiger freigeben (Klick fängt ihn wieder ein) |

## Aufbau

| Datei | Inhalt |
| --- | --- |
| `scripts/game_state.gd` | Spielregeln, Werte und Spielstand. Als Autoload `Game` überall erreichbar. |
| `scripts/main.gd` | Baut die Welt auf und führt die Spielschleife aus. |
| `scripts/shaft.gd` | Das Loch: Schichtwände, Sohle und Leiter. |
| `scripts/player.gd` | Spielfigur in der Ich-Perspektive mit Klettern. |
| `scripts/hud.gd` | Anzeige: Tiefe, Kasse, Eimer, Lampe, Hinweise und Meldungen. |
| `scripts/workbench_ui.gd` | Werkbank zum Aufrüsten. |
| `scenes/main.tscn` | Startszene, lädt `main.gd`. |

Der Spielstand liegt in `user://spielstand.json`. Unter Windows ist das `%APPDATA%\Godot\app_userdata\Ab durch die Mitte\`.

## Stand

**Schritt 1 (fertig):** Kernschleife von Kapitel 1. Graben, Eimer, Lampe mit unscharfer Rückweg-Anzeige, Leiter, Verkaufen, Werkbank mit vier Ausrüstungsbereichen, Ohnmacht, Speichern.

**Paket 1 (fertig):** Takt, Glückstreffer, Goldader, Tiefenbonus, „Knapp geschafft!“, Gang-Serie, Gang-Karten, Rekord-Gang.

**Als Nächstes für Kapitel 1** (aus dem Prototyp übernehmen):
- Klumpen, Aufklopfen, Sammelbuch, Echolot
- Helfer (Maulwurf, Nachbarskinder) und Kaffeemaschine
- Aufträge, Begegnungen (Herr Krüger und Co.), Tiefenleiste, Schilder, Tafel
- Töne und Musik
- Startbildschirm, Pausenmenü, Sprachen (Deutsch und Englisch)

Danach Kapitel 2 (Bohrlager) bis 6 laut Design-Dokument.
