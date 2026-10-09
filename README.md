# Potion

A digital prototype of the potion card game: draft cards from shared middle
decks into a 4-card potion, score values, modifier icons, potion types and a
special order over 4 rounds. Godot 4.7, GL Compatibility. Local hot-seat for
now; the code is structured so the rules can move to a server for online play.

The Godot project lives in [`potion-card-game/`](potion-card-game/).

## Running

Open `potion-card-game/project.godot` in Godot and press F5.

```bash
# Rules tests (fast, headless)
godot --headless --path potion-card-game -s res://tests/run_tests.gd

# Play full games through the real UI with random clicks (2, 3 or 4 players)
godot --headless --path potion-card-game --scene res://tests/autoplay.tscn --fixed-fps 60 -- 4
```

`tests/card_gallery.tscn` shows every card in the deck; open it and press F6 to check card art.

## Layout

| Folder | What lives there | Depends on |
|---|---|---|
| `scripts/core/` | The rules. Pure data, no nodes: `Rules` (every tunable number), `CardData`, `DeckBuilder`, `Scoring`, `SpecialOrder`, `GameState` (the engine). | nothing else |
| `scripts/skin/` | The art style: `CardArt` (sprites, card colours, tinting) and `Palette` (all UI/table colours). | core |
| `scripts/views/` | World-space nodes: `CardView`, `PotionView`, `MiddleDeckView`, `GhostSlot`, `ScoreSequence`, `TableLayout`, `TableRoot`, background. | core, skin, fx |
| `scripts/ui/` | Screen-space UI: `Hud`, `OrderChoiceOverlay`, `GameOverOverlay`, `UiKit` (button styling). | skin, fx |
| `scripts/fx/` | `Fx` autoload: shake, hit-stop, particles, floating text, banners. | skin |
| `scripts/` | `game.gd` (controller), `main_menu.gd`, `session.gd` (autoload). | everything |
| `tests/` | Rules tests, autoplay, card gallery. | |
| `tools/` | `export_sprites.sh`: Aseprite sources to PNGs. | |

## Common changes

- **Balance** (deck, combos, orders, rounds, deck count): edit `scripts/core/rules.gd`, then update the
  numbers pinned in `tests/run_tests.gd`.
- **A new special order**: add a `Kind` in `special_order.gd` with its `is_met`, `title` and
  `description` cases, and list it in `Rules.ORDERS`.
- **Card art**: redraw the `.aseprite` files and run `tools/export_sprites.sh`. Card size, icon
  positions and grey levels are read from the sprites, so other resolutions work. A different
  style (e.g. painted cards instead of tinted greyscale) means changing `CardArt` and
  `CardView.set_card()`, the only place a card face is built.
- **UI colours/fonts**: `scripts/skin/palette.gd`, and the font in `Fx._ready()`.
- **Table layout**: `scripts/views/table_layout.gd`.

## Architecture notes (for online play)

- `GameState` is the single source of truth. Every action takes the acting player and is
  rejected if illegal (wrong phase, not your turn, bad index). `GameState.apply(action)` takes
  the same actions as plain dictionaries, e.g. `{"type": "play_card", "player": 0, "deck": 2, "side": 1}`,
  which is the shape to send over the network.
- Moves are atomic: taking and placing a card is one `play_card`, and a swap is one `swap`.
  The UI only shows the in-between steps locally, and nothing is committed until the move is complete.
- A game is reproducible from its seed (`GameState.new(players, seed)`). Card ids are stable
  for a given deck recipe.
- Rounds score themselves when the last card is played (`last_round_scores`, `totals`);
  the host calls `next_round()` once the scores have been shown.
- `game.gd` never edits rules state directly. After each action it checks its views against
  `GameState`, and `_resync()` rebuilds them from state. A networked client would apply
  server state the same way.

Still to do before online play: serialise `GameState` (or send actions plus seed),
hide other players' special orders and pending offers, and add a lobby and turn ownership.
