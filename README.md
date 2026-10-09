# Potion

A digital prototype of the potion card game: draft cards from shared middle
decks into a 4-card potion, score values, modifier icons, potion types and a
special order over 4 rounds. Godot 4.7, GL Compatibility.

Three modes:
- **Tutorial**: 1v1 against a scripted CPU. Tips walk you through rounds 1–2, including how
  scoring works; then you play rounds 3–4 on your own.
- **VS CPU**: 1–3 CPUs at Easy, Medium or Optimal.
- **Multiplayer**: rooms on a central server. Every room is listed in the browser; private ones
  need their code to join. The host picks 2–4 players. Rooms support rematches. The server is
  this same project run headless; see [DEPLOY.md](DEPLOY.md).

The Godot project lives in [`potion-card-game/`](potion-card-game/).

## Running

Open `potion-card-game/project.godot` in Godot and press F5.

```bash
# Rules tests (fast, headless)
godot --headless --path potion-card-game -s res://tests/run_tests.gd

# Bot tests: always legal, stronger beats weaker (a few minutes; add "quick" for fewer games)
godot --headless --path potion-card-game -s res://tests/bot_tests.gd

# Multiplayer: in-process server + 3 clients (rooms, codes, a game, rematch, a dropout)
godot --headless --path potion-card-game -s res://tests/net_smoke.gd

# Play full games through the real UI with random clicks for your seat
godot --headless --path potion-card-game --scene res://tests/autoplay.tscn --fixed-fps 60 -- cpu 3 optimal --fast
godot --headless --path potion-card-game --scene res://tests/autoplay.tscn --fixed-fps 60 -- tutorial --fast
godot --headless --path potion-card-game --scene res://tests/autoplay.tscn --fixed-fps 60 -- online

# Multiplayer server (see DEPLOY.md)
godot --headless --path potion-card-game -- --server --port=9080 --bind=127.0.0.1
```

To try multiplayer on one machine: in one window choose MULTIPLAYER → HOST LOCAL SERVER; start a
second with `godot --path potion-card-game -- --url=ws://localhost:9080 --name=Bob`.

`tests/card_gallery.tscn` shows every card in the deck; open it and press F6 to check card art.

## Layout

| Folder | What lives there | Depends on |
|---|---|---|
| `scripts/core/` | The rules. Pure data, no nodes: `Rules` (every tunable number), `CardData`, `DeckBuilder`, `Scoring`, `SpecialOrder`, `GameState` (the engine, snapshots). | nothing else |
| `scripts/ai/` | CPU players, no nodes: `Bot` (base + factory), `EasyBot`, `MediumBot`, `OptimalBot`, `PotionEval` (heuristic), `WorldSampler`, `ScriptedBot`. | core |
| `scripts/net/` | Multiplayer: `Protocol` (message list), `WsServer`, `PotionServer`, `Room`, `NetClient`, the `Net` autoload, `server_main.gd`. | core, ai |
| `scripts/match/` | What the game plays against: `Match`, `LocalMatch` (CPUs, tutorial), `NetMatch` (server). | core, ai, net |
| `scripts/tutorial/` | `TutorialScript` (the scripted deck, CPU moves, tips) and `TutorialDirector`. | core, views, ui |
| `scripts/skin/` | The art style: `CardArt` (sprites, card colours, tinting) and `Palette` (all UI/table colours). | core |
| `scripts/views/` | World-space nodes: `CardView`, `PotionView`, `MiddleDeckView`, `GhostSlot`, `ScoreSequence`, `TableLayout`, `TableRoot`, background. | core, skin, fx |
| `scripts/ui/` | Screen-space UI: `Hud`, `OrderChoiceOverlay`, `GameOverOverlay`, `TutorialTip`, `UiKit` (buttons, fields, panels). | skin, fx |
| `scripts/fx/` | `Fx` autoload: shake, hit-stop, particles, floating text, banners. | skin |
| `scripts/` | `game.gd` (controller), `main_menu.gd`, `lobby.gd`, `session.gd` (autoload: mode, saved settings, command line). | everything |
| `tests/` | Rules, bot and network tests, autoplay, card gallery. | |
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
- **CPU strength**: `PotionEval` weights (Medium, and Optimal's rollouts), `OptimalBot.max_usec` /
  `max_worlds` (thinking budget), `EasyBot` chances. Check with `tests/bot_tests.gd`.
- **Tutorial**: `scripts/tutorial/tutorial_script.gd`. Decks, offers, CPU moves and tip text live
  there. `test_tutorial_script` pins the scores the tips mention; update `EXPECTED_SCORES` with it.
  Rules changes that break the scripted cards fail that test.
- **Multiplayer messages**: `scripts/net/protocol.gd` lists every message. Bump `Protocol.VERSION`
  when changing them.

## Architecture notes

- `GameState` is the single source of truth. Every action takes the acting player and is
  rejected if illegal (wrong phase, not your turn, bad index). `GameState.apply(action)` takes
  the same actions as plain dictionaries, e.g. `{"type": "play_card", "player": 0, "deck": 2, "side": 1}`,
  which is also what goes over the network. `legal_actions(player)` lists them.
- Moves are atomic: taking and placing a card is one `play_card`, and a swap is one `swap`.
  The UI only shows the in-between steps locally, and nothing is sent until the move is complete.
- Special orders are chosen by everyone at once; turned-down orders go back in seat order, so
  the result doesn't depend on who clicked first.
- `to_snapshot(player)` is the JSON-safe state one player may see: deck tops but not the cards
  under them, their own offers and order, others' orders only once the round is scored, never
  the RNG. `from_snapshot()` rebuilds a `GameState` with unknown cards as `null`, so the same
  queries work on a client.
- `game.gd` drives one seat against a `Match`: `submit(action)` out, `event(action, snapshot)` in,
  for everyone's moves including its own. `LocalMatch` (VS CPU, tutorial) owns the real
  `GameState`; `NetMatch` talks to the server. Both hand the controller redacted snapshots, so
  offline and online run the same code and the UI can't show a secret. Other players' moves queue
  up and are animated one at a time; `_resync()` rebuilds the views from state if they disagree.
- Bots only ever see redacted views. Optimal samples possible hidden cards and secret orders,
  plays each candidate move out to the end of the round with greedy play, and keeps the best
  average margin. It thinks in short slices per frame, so the game keeps animating.
- A game is reproducible from its seed (`GameState.new(players, seed)`). Card ids are stable
  for a given deck recipe.
- Rounds score themselves when the last card is played; the host calls `next_round()` once the
  scores have been shown. Online, the server waits for every player's `ack_round`, with a timeout.
- The server sits behind a TLS proxy and speaks plain WebSocket. A player who drops mid-game is
  replaced by a Medium CPU; there is no rejoining a game yet.
