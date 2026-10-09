# Running the multiplayer server

Multiplayer uses one central server: this same Godot project, run headless.
The server holds every room and runs every game, so players can't cheat and
everyone sees the same room list. Players never run anything themselves:
the game connects to `wss://potion.matteob.dev` when they open Multiplayer.

The setup below runs the server on your home server behind Caddy, which
handles HTTPS/WSS certificates automatically.

```
player's game --wss://potion.matteob.dev--> router :443 --> Caddy --ws://127.0.0.1:9080--> Godot server
```

## 1. Put the game on the server

The server is the Godot editor binary run headless against a copy of the project.
Use the same Godot version as the game (4.7.2).

```bash
# Godot (Linux x86_64; use the arm64 build on a Raspberry Pi or other ARM box)
sudo mkdir -p /opt/potion
cd /opt/potion
sudo curl -LO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
sudo unzip Godot_v4.7.2-stable_linux.x86_64.zip
sudo mv Godot_v4.7.2-stable_linux.x86_64 godot

# The project
sudo git clone <your repo url> repo

# A user to run it as
sudo useradd --system --home /var/lib/potion --create-home potion
sudo chown -R potion:potion /opt/potion
```

Import the project once. This builds the `.godot/` cache, which isn't in git:

```bash
sudo -u potion /opt/potion/godot --headless --path /opt/potion/repo/potion-card-game --import
```

Try it:

```bash
sudo -u potion /opt/potion/godot --headless --path /opt/potion/repo/potion-card-game -- --server --port=9080 --bind=127.0.0.1
# -> Potion server listening on 127.0.0.1:9080
```

Server options (after the `--`):

| Option | Default | |
|---|---|---|
| `--server` | | run as the server instead of the game |
| `--port=9080` | 9080 | port to listen on |
| `--bind=127.0.0.1` | all addresses | listen address. Keep it on `127.0.0.1` behind Caddy, so the plain `ws://` port is never exposed |

> You can export a dedicated server binary instead: in the editor, Project → Export → Add → Linux, set
> Export Mode to "Dedicated Server", and export to `/opt/potion/potion-server.x86_64`. Then use
> `/opt/potion/potion-server.x86_64 --headless -- --server ...` in the service below in place of
> `godot --path ...`. If you strip resources, keep the scripts; the server never loads the card art.

## 2. Keep it running with systemd

`/etc/systemd/system/potion.service`:

```ini
[Unit]
Description=Potion multiplayer server
After=network-online.target
Wants=network-online.target

[Service]
User=potion
Group=potion
WorkingDirectory=/opt/potion/repo/potion-card-game
Environment=HOME=/var/lib/potion
ExecStart=/opt/potion/godot --headless --path /opt/potion/repo/potion-card-game -- --server --port=9080 --bind=127.0.0.1
Restart=on-failure
RestartSec=3
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=/var/lib/potion /opt/potion/repo/potion-card-game/.godot

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now potion
journalctl -u potion -f      # logs: rooms created, games started, rooms closed
```

## 3. HTTPS/WSS with Caddy

If Caddy isn't installed: `sudo apt install caddy` (Debian/Ubuntu). Add to `/etc/caddy/Caddyfile`:

```
potion.matteob.dev {
	reverse_proxy 127.0.0.1:9080
}
```

```bash
sudo systemctl reload caddy
```

Caddy gets a Let's Encrypt certificate for the name and passes WebSocket upgrades
through without extra settings.

**Already running nginx or Traefik on port 443?** Add a site for `potion.matteob.dev` to it instead. For nginx:

```nginx
server {
	listen 443 ssl;
	server_name potion.matteob.dev;
	# ssl_certificate ... (your usual certbot lines)
	location / {
		proxy_pass http://127.0.0.1:9080;
		proxy_http_version 1.1;
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header Connection "upgrade";
		proxy_read_timeout 120s;   # the server pings every 15 s; this just needs to be longer
	}
}
```

## 4. DNS and router

- **DNS:** add a record for `potion` in the `matteob.dev` zone pointing at your home connection:
  an `A` record to your public IPv4 (and `AAAA` for IPv6), or a `CNAME` to your dynamic-DNS name
  if your IP changes.
- **Router:** forward TCP **443** (and **80**, which Let's Encrypt uses to verify the name) to the
  home server. If other sites on matteob.dev already work over HTTPS, this is already done.
  Only Caddy needs to be reachable from outside, never port 9080.

## 5. Check it

```bash
# From any machine, with websocat (brew install websocat / cargo install websocat):
websocat wss://potion.matteob.dev
{"t":"hello","v":1,"name":"test","token":"x"}
# -> {"t":"welcome",...} then {"t":"rooms","rooms":[]}
```

Then open the game, choose MULTIPLAYER, and CONNECT.

## Updating

```bash
cd /opt/potion/repo && sudo -u potion git pull
sudo -u potion /opt/potion/godot --headless --path /opt/potion/repo/potion-card-game --import
sudo systemctl restart potion
```

Restarting ends every game in progress, so do it when nobody's playing.

If you change the messages in `scripts/net/protocol.gd`, bump `Protocol.VERSION` and update the
server **first**. Old games then get a "please update" message instead of misbehaving.

## Testing without the home server

- **Two windows on one machine:** in the first, MULTIPLAYER → HOST LOCAL SERVER (it runs a
  server inside the game and joins it). In the second, set SERVER to `ws://localhost:9080` and
  CONNECT. Or launch the second window with
  `godot --path potion-card-game -- --url=ws://localhost:9080 --name=Bob`.
- **Local headless server:** `godot --headless --path potion-card-game -- --server`, then connect
  the game to `ws://localhost:9080`.
- **Automated:** `godot --headless --path potion-card-game -s res://tests/net_smoke.gd`.

## Limits built into the server

These are constants in `scripts/net/potion_server.gd` and `room.gd`:
- 500 connected players and 200 rooms.
- 20 messages per second per player (dropped after 100).
- 5 wrong room codes per 10 seconds, so private codes can't be guessed by brute force.
- Players silent for 45 s are dropped. A player who drops mid-game is replaced by a Medium CPU.
- The next round starts when everyone has seen the scores, or after 10 s + 8 s per player.
