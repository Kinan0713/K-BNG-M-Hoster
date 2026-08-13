<div align="center">

```text
██   ██  ██████  ███    ██  ██████   ███    ███     ██   ██ ██████  ███████ ████████ ███████
██  ██   ██   ██ ████   ██ ██        ████  ████     ██   ██ ██    ██ ██         ██    ██     
█████    ██████  ██ ██  ██ ██   ███  ██ ████ ██     ███████ ██    ██ ███████    ██    █████  
██  ██   ██   ██ ██  ██  ██ ██    ██  ██  ██  ██     ██   ██ ██    ██      ██    ██    ██     
██   ██  ██████  ██   ████  ██████   ██      ██     ██   ██  ██████  ███████    ██    ███████
```

</div>

# 🚗 K BNG M Hoster

### *(Kinan BeamNG Multiplayer Hoster)* — **v0.5.3**

**The All-In-One Automated BeamMP Hosting & Joining Tool**

> 🔽 **Download the latest release:** [K BNG M Hoster v0.5.3 ZIP](https://github.com/Kinan0713/K-BNG-M-Hoster/releases/latest)

*Solely created and developed by **Kinan** (`@raed713`)*

---

## 📌 What is K BNG M Hoster?

**K BNG M Hoster** is an all-in-one automation utility designed to make hosting, configuring, and joining BeamMP multiplayer servers effortless. Built entirely from scratch, it handles process execution, automates background server management, and streamlines the direct connection workflow so you and your friends can drive together in seconds.

### ✨ Key Features

| Feature | What it does for you |
| --- | --- |
| 🖱️ **One-Click Launch** | Double-click `Start_Here.bat`. Everything else is automatic. |
| 🔑 **Auto AuthKey** | Paste your BeamMP key once — the tool stores it privately, injects it at start, and removes it again when the session ends. |
| 🔄 **Auto Diagnostics** | If the server fails to start, the tool reads the server log and tells you *exactly* why (bad key, busy port, missing runtime, bad map). |
| 🌍 **UPnP Port Forwarding** | Automatically forwards your port (TCP+UDP) on router-enabled setups — no manual router login needed. |
| 🛡️ **Auto Firewall** | Opens the correct Windows Firewall rules with one polite UAC prompt. |
| 🧭 **Reachability Test** | Checks whether your public IP:port is actually reachable from the internet and tells you on screen. |
| ⚠️ **Smart Warnings** | Detects CGNAT ISPs and VPN adapters (Radmin VPN, Hamachi, ZeroTier) that silently break BeamMP's UDP traffic. |
| 🔄 **Busy-Port Auto-Switch** | If your port is taken, picks a free one and warns you loudly. |
| 🎮 **Mod Manager** | List, enable/disable and scan your `Resources/Client/` mods from a menu. |
| 🔐 **Malware Guard** | Scans mod ZIPs for executables and quarantines anything suspicious. |
| 👥 **Live Player Activity** | Shows who's online, with optional Discord join/leave notifications. |
| 🧹 **Privacy Cleaner** | One menu option wipes every personal/temporary file before you share the folder. |
| 📡 **Flexible Hosting** | Works with **Tailscale** (no port forwarding) **or** public port forwarding. |

---

## 🚀 QUICK START (30 seconds)

1. **Extract** the ZIP to any folder.
2. **Double-click `Start_Here.bat`** — that's it, no other setup.
3. First time: the tool opens the key website, you **paste your BeamMP key**, press Enter, and your server starts automatically.
4. While playing, tell players to connect using the address shown on your screen (press **C** to copy it).

That's everything. The tool handles the server key, settings, ports and problems for you.

---

## ⚡ Setup Requirements

| Requirement | Purpose | Download Link |
|---|---|---|
| **BeamMP Keymaster** | Get your free server authentication key | [Keymaster Portal](https://keymaster.beammp.com) |
| **BeamMP Client** | Official multiplayer client for BeamNG.drive | [Download Client](https://beammp.com) |
| **Tailscale** *(Method A)* | Secure direct connection without changing router settings | [Download Tailscale](https://tailscale.com) |

---

## ⚙️ Step-by-Step Configuration Guide

### 📁 Folder Layout

Keep it simple — the top level only shows the things you actually use:

| Top level (visible) | What it is |
| --- | --- |
| `Start_Here.bat` | **Just double-click this to start.** |
| `ServerConfig.toml` | Your server settings (name, port, players, map...) |
| `Resources/` | Your mods (drop mod `.zip` files into `Resources/Client/`) |
| `README.md` / `README.txt` | This documentation |

| `Server/` (the engine — you never need to open it) | What it is |
| --- | --- |
| `BeamMP-Server.exe` | The official BeamMP server program |
| `Play_BeamMP.ps1` / `.bat` | The launcher code (single source of truth) |
| `.env` *(created automatically)* | Your secret server key |
| `Launcher.cfg`, `webhook.example.txt` | Support files |
| `Logs/`, `Server.log`, `CONNECTING.txt` *(created automatically)* | Logs, IP caches and session files |

> The server always runs using the **top-level** `ServerConfig.toml` and `Resources/` — that is why they stay visible. Everything personal or temporary lives inside `Server\`, and menu option **"Clean personal info"** wipes it before you share the folder.

### 1️⃣ Input Your Auth Key *(Automatic — Recommended)*

1. Go to [BeamMP Keymaster](https://keymaster.beammp.com) and generate a new key.
2. Run `Start_Here.bat` — on first launch it asks you to paste the key once, then saves it into `Server\.env` automatically.
3. Before every launch, the tool reads `Server\.env`, writes your key into `AuthKey` inside `ServerConfig.toml`, starts the server, and **removes the key from the config again when the session ends** so nothing personal is ever left behind.
4. `Server\.env` is your private file — never share the folder before running **"Clean personal info"** (menu option 5).

> **Alternative — Windows environment variable:** set a system/user variable named `BEAMMP_AUTHKEY`. The environment variable takes priority over `.env`.
>
> **Manual fallback:** you can still paste the key directly into `ServerConfig.toml` (line 7, `AuthKey = "..."`); the launcher leaves an already-set key untouched if neither `.env` nor the environment variable exists.

### 2️⃣ Note on Ports

The server port is read from `Port` in `ServerConfig.toml` (default **30814**, the BeamMP standard). Adjust the connection examples below (and your router/Tailscale rules) to match whatever port you set there. BeamMP requires **both TCP and UDP** on the same port.

### 3️⃣ Utility Commands

| Command | What it does |
| --- | --- |
| `Start_Here.bat` | **Just double-click this.** Everything else is automatic |
| `Start_Here.bat mods` | Open the Mod Manager (list, disable, enable, scan mods) |
| `Start_Here.bat fix` | Open the Help / Fix Problems menu (firewall, UPnP, port, key, VPN checks) |
| `Start_Here.bat help` | Show usage |

*(All commands just launch `Server\Play_BeamMP.ps1` — one codebase. PowerShell users: `.\Play_BeamMP.ps1 -Mods`, `.\Play_BeamMP.ps1 -Fix`, `.\Play_BeamMP.ps1 -Help`)*

---

## 🌐 Server Launch & Connection Methods

Choose **one** of the two hosting methods below depending on how you want players to connect:

### 🔹 METHOD A: Tailscale (Private / No Port Forwarding)

*Best for playing privately with a group of friends without altering router settings.*

#### 🛠️ Host Setup & Connection

1. Launch **Tailscale** on your PC.
2. Double-click **`Start_Here.bat`** to start the host.
3. Open **BeamNG.drive**.
4. Go to: `More...` ➔ `BeamMP` ➔ `Direct Connect`
5. Connect using:
   - **IP Address:** `127.0.0.1`
   - **Port:** `30814` *(or whatever `Port` is set to in ServerConfig.toml)*

#### 👥 How Friends Join

1. Ensure all players are connected to the Host's network inside **Tailscale**.
2. Open BeamNG via the official **BeamMP Launcher**.
3. Go to: `More...` ➔ `BeamMP` ➔ `Direct Connect`
4. Connect using:
   - **IP Address:** Host's Tailscale IP (`100.x.x.x`)
   - **Port:** `30814`

---

### 🔹 METHOD B: Port Forwarding (Public Server List)

*Best for hosting publicly so anyone can find your server in the BeamMP Server Browser or join via your Public IP.*

#### 🛠️ Host Setup & Connection

1. **Let the tool try first:** on server start the launcher automatically attempts a **UPnP** port forward (TCP+UDP) — no router login needed on UPnP-enabled routers.
2. **Manual fallback:** if your router has no UPnP (like many ISP routers), log into your router admin page and forward the port from `ServerConfig.toml` (default **`30814`**, **TCP and UDP**) to your PC's local IP address.
3. Open `ServerConfig.toml` and verify your settings:
   ```toml
   Private = false
   Port = 30814
   ```
4. Double-click **`Start_Here.bat`** to launch the server.
5. Watch the live status screen: it shows whether your `public IP:port` is **reachable** from the internet, and warns you about VPN adapters or CGNAT networks that would block players.
6. Open **BeamNG.drive** and connect via `Direct Connect` (`127.0.0.1:30814`).

#### 👥 How Friends Join

- **Option 1 (Server Browser):** players can search for your Server Name in the official BeamMP Server Browser.
- **Option 2 (Direct Connect):** players go to `More...` ➔ `BeamMP` ➔ `Direct Connect` and enter your **Public IP** and Port from `ServerConfig.toml`.

> ⚠️ **Why won't players connect?** The three usual culprits, in order: (1) a **VPN adapter** (Radmin VPN, Hamachi, ZeroTier) is running on the host — close it, BeamMP's UDP traffic breaks through VPNs; (2) **UDP is not forwarded** — BeamMP needs both TCP *and* UDP; (3) **Windows Firewall** doesn't allow `BeamMP-Server.exe`. The launcher's **Fix menu (option 4)** checks all of these for you.

---

## 📦 Adding Custom Mods

To load custom vehicles, maps, or physics mods onto your server:

1. Open the project folder and navigate to:
   ```
   Resources/Client/
   ```
2. Drop your mod `.zip` files directly into this directory.
3. Restart the server by running `Start_Here.bat` again to sync mods automatically with everyone who joins.

> **Security note:** On launch the tool scans `Resources/Client/` (including inside `.zip` mods) and moves any suspicious executable files (`*.exe`, `*.vbs`, `*.cmd`, `*.scr`, `*.pif`) to the `Quarantine/` folder. Everything it does is written to `Logs/launcher.log`.
>
> **Tip:** Run `Start_Here.bat mods` for a menu that lists your mods with sizes, lets you disable/enable them (moved to `Server\Backups\mods\`), re-runs the security scan, and opens the folder in Explorer.

---

## 🔌 Optional: Discord Server Announcements

1. Create a webhook in your Discord channel (`Channel Settings > Integrations > Webhooks`).
2. Copy `webhook.example.txt` to `webhook.txt` inside `Server\`.
3. Paste your webhook URL into `webhook.txt` and save.
4. The launcher posts an **`[ONLINE]`** embed when the server starts, an **`[OFFLINE]`** embed when it stops, and **join/leave** embeds when players enter or leave the server.
   Leave `webhook.txt` empty or deleted to disable this feature.

---

## 🛠️ Troubleshooting & FAQ

> **"Invalid ZIP File" Pop-up?**
> Ignore this message! BeamNG scans files while BeamMP streams them in real time. Simply let the progress bar finish loading.

> **Server Window Closes Instantly?**
> Check your `ServerConfig.toml` file. This usually happens if the `AuthKey` was pasted incorrectly or left blank. With the launcher, make sure your `.env` file contains a valid `BEAMMP_AUTHKEY=...` (or the `BEAMMP_AUTHKEY` environment variable is set).

> **Tool says the server failed to start?**
> The tool waits for the server to actually listen on the configured port before showing "SERVER IS LIVE!". If it fails, it **auto-diagnoses the cause** — bad/empty AuthKey, port already in use, missing Visual C++ runtime, unreachable BeamMP backend, or a missing map — and shows you the exact fix.

> **"NOT reachable" on the external test?**
> That means players from the internet can't reach your port. Run the **Fix menu** (option 4) and follow its instructions: close any VPN adapters, forward **TCP+UDP 30814** to your PC, and allow `BeamMP-Server.exe` through Windows Firewall.

> **Does everyone use the same port?**
> Yes — port 30814 is the BeamMP standard for everyone. That's fine: every host has a unique public IP, so `IP:port` never collides between different networks. The only exception is two hosts sharing one public IP (same LAN/VPN) — the launcher auto-switches the port in that case.

> **I don't want to touch my router at all.**
> Use **Method A (Tailscale)** — no port forwarding needed, works over any network.

---

## 🔐 Security & Privacy

- **No data collection.** The tool is offline, local-only software. It never phones home, sends logs, or uploads anything except the normal BeamMP server traffic.
- **Your key stays yours.** The AuthKey lives in `Server\.env` (private, git-ignored), is injected into the config only during a session, and is wiped when the session ends.
- **Share safely.** Before distributing your folder, run **"Clean personal info"** (menu option 5) — it wipes `.env`, `webhook.txt`, logs, backups and session files.
- **Mod safety.** ZIP mods are scanned for executable payloads before being served to players.

---

## 📜 Version History

See [CHANGELOG.md](./CHANGELOG.md) for all changes.

---

## 👑 Credits & Ownership

- **Sole Developer & Creator:** **Kinan** (`@raed713`)
- *All original code, tools, scripts, and rights belong strictly and exclusively to Kinan.*
- **Official Discord:** [Innocent BeamMP Server Community](https://discord.gg/2FxsJvKr4a)

---

## 📜 License & Legal

This project is distributed under a proprietary EULA. By using this software you agree to the terms set in [LICENSE](./LICENSE).

### ✅ Permitted Actions

- Running the unmodified packaged software
- Editing authorized configuration files (`ServerConfig.toml`) only as instructed
- Adding mod archive files to `Resources/Client/` to enable mod syncing

### ❌ Strictly Prohibited

- Modifying source code or scripts that are not explicitly authorized
- Reverse-engineering, decompilation, or extraction of internal logic
- Reuploading, mirroring, forking, redistributing, or selling the software
- Removing, altering, or obscuring author attribution (Kinan / @raed713)
- Accessing internal scripts or proprietary files not explicitly permitted

**For permissions, DMCA, or legal inquiries:** open an [issue on GitHub](https://github.com/Kinan0713/K-BNG-M-Hoster/issues)