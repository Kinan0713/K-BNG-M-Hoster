# 🚗 K BNG M HOSTER

### *(Kinan BeamNG Multiplayer Hoster)*

### ⚡ **The All-In-One Automated BeamMP Hosting & Joining Tool** ⚡

*Solely created and developed by **Kinan** (`@raed713`)*

> ⚠️ **OFFICIAL DOWNLOAD ONLY** - This tool is distributed exclusively through the
> GitHub Releases page: https://github.com/Kinan0713/K-BNG-M-Hoster/releases/latest
> Please do NOT share, reupload, or forward this tool to others - everyone should
> download it from there so they always get the latest version.

---

## 🚀 QUICK START (30 seconds)

1. **Extract** this ZIP to any folder.
2. **Double-click `Start_Here.bat`** — that's it, no other setup.
3. First time: the tool opens the key website, you **paste your key**, press Enter, and your server starts automatically.
4. While playing, tell your friends to connect using the address shown on your screen (press **C** to copy it).

That's everything. The tool handles the server key, settings, ports and problems for you.

---

## 📌 What is K BNG M Hoster?

**K BNG M Hoster** (*Kinan BeamNG Multiplayer Hoster*) is an all-in-one automation utility designed to make hosting, configuring, and joining BeamMP multiplayer servers effortless. Built entirely from scratch by **Kinan**, it handles process execution, automates background server management, and streamlines the direct connection workflow so you and your friends can drive together in seconds.

### ✨ Key Features

* **Zero-Stress Automation:** Handles server startup and process management automatically.
* **Flexible Hosting Options:** Full support for both **Tailscale (No Port Forwarding)** and **Public Port Forwarding**.
* **Seamless Mod Syncing:** Load custom vehicles and maps directly through client resources.
* **One-Click Launch:** Start the host via `Start_Here.bat`.
* **Session-Aware Lifecycle (v0.3):** The server starts with your game session and stops automatically the moment the session ends.
* **Auto Diagnostics (v0.4):** If the server fails to start, the tool reads the server log and tells you exactly why — bad AuthKey, port already in use, missing Visual C++ runtime, or a bad map.
* **Live Player Activity (v0.4):** Shows how many players are online (and who) while you host, with optional Discord join/leave notifications.
* **Mod Manager (v0.4):** Manage your `Resources/Client/` mods from a simple menu — run `Start_Here.bat mods`.
* **Update Checker (v0.4):** Tells you when a newer official BeamMP-Server is available (checked once per day, never blocks startup).
* **Simplest Setup Ever (v0.5):** First run walks you through everything — you only paste your key once. The tool writes all files, auto-picks a free port, and has a one-click **Help / Fix Problems** menu.
* **Lock my IP while hosting (v0.5.3):** Keeps your LAN IP fixed during a session so your router's port-forward never breaks when the DHCP lease renews — it auto-returns to DHCP when the session ends (main menu option 6).
* **Deduplicated Firewall (v0.5.3):** The launcher detects existing Windows Firewall rules and never creates duplicates, even on repeated runs without admin rights.

---

## ⚡ Setup Requirements

Before getting started, make sure you have the following downloads ready:

| Requirement | Purpose | Download Link |
| --- | --- | --- |
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

> The server always runs using the **top-level** `ServerConfig.toml` and `Resources/` — that is why they stay visible. Everything personal or temporary lives inside `Server\`, and menu option **"Clean personal info"** removes all personal information from the folder (menu option 5).

### 1️⃣ Extract & Open

1. Download **K BNG M Hoster** and extract the ZIP folder to your preferred location.
2. Locate `ServerConfig.toml` inside the main folder.
3. Open `ServerConfig.toml` using **Notepad** or your preferred text editor (optional — the launcher can change name/players for you).

### 2️⃣ Input Your Auth Key *(Automatic — Recommended)*

The launcher handles your key automatically, so you **never have to paste it into `ServerConfig.toml` by hand**.

1. Go to [BeamMP Keymaster](https://keymaster.beammp.com) and generate a new key.
2. Run `Start_Here.bat` — on first launch it asks you to paste the key once, then saves it into `Server\.env` automatically.
3. Before every launch, the tool reads `Server\.env`, writes your key into `AuthKey` inside `ServerConfig.toml`, starts the server, and **removes the key from the config again when the session ends** so nothing personal is ever left behind.
4. `Server\.env` is your private file — you can remove all personal information with **"Clean personal info"** (menu option 5).

> **Alternative — Windows environment variable:** set a system/user variable named `BEAMMP_AUTHKEY`. The environment variable takes priority over `.env`.
>
> **Manual fallback:** you can still paste the key directly into `ServerConfig.toml` (line 7, `AuthKey = "..."`); the launcher leaves an already-set key untouched if neither `.env` nor the environment variable exists.

### 3️⃣ Note on Ports

The server port is read from `Port` in `ServerConfig.toml`. Adjust the connection examples below (and your router/Tailscale rules) to match whatever port you set there.

### 4️⃣ Utility Commands *(v0.4)*

| Command | What it does |
| --- | --- |
| `Start_Here.bat` | **Just double-click this.** Everything else is automatic |
| `Start_Here.bat mods` | Open the Mod Manager (list, disable, enable, scan mods) |
| `Start_Here.bat fix` | Open the Help / Fix Problems menu |
| `Start_Here.bat help` | Show usage |

*(All commands just launch `Server\Play_BeamMP.ps1` — one codebase. PowerShell users: `.\Play_BeamMP.ps1 -Mods`, `.\Play_BeamMP.ps1 -Fix`, `.\Play_BeamMP.ps1 -Help`)*

---

## 🌐 Server Launch & Connection Methods

Choose **one** of the two hosting methods below depending on how you want players to connect:

---

### 🔹 METHOD A: Tailscale (Private / No Port Forwarding)

*Best for playing privately with a group of friends without altering router settings.*

#### 🛠️ Host Setup & Connection

1. Launch **Tailscale** on your PC.
2. Double-click **`Start_Here.bat`** to start the host.
3. Accept the license prompt, then the tool opens the BeamMP Launcher automatically.
4. Open **BeamNG.drive**.
5. Go to: `More...` ➔ `BeamMP` ➔ `Direct Connect`
6. Connect using:
* **IP Address:** `127.0.0.1`
* **Port:** `30814` *(or whatever `Port` is set to in ServerConfig.toml)*

#### 👥 How Friends Join

1. Ensure all friends are connected to the Host’s network inside **Tailscale**.
2. Open BeamNG via the official **BeamMP Launcher**.
3. Go to: `More...` ➔ `BeamMP` ➔ `Direct Connect`
4. Connect using:
* **IP Address:** Host's Tailscale IP (`100.x.x.x`)
* **Port:** `30814` *(or whatever `Port` is set to in ServerConfig.toml)*

---

### 🔹 METHOD B: Port Forwarding (Public Server List)

*Best for hosting publicly so anyone can find your server in the BeamMP Server Browser or join via your Public IP.*

#### 🛠️ Host Setup & Connection

1. Access your router settings and forward the port from `ServerConfig.toml` (default **`30814`**, TCP/UDP) to your local IP address.
2. Open `ServerConfig.toml` and verify your settings:
```toml
Private = false
Port = 30814
```
3. Double-click **`Start_Here.bat`** to launch the server.
4. Open **BeamNG.drive** and connect via `Direct Connect` (`127.0.0.1:30814`).

#### 👥 How Friends Join

* **Option 1 (Server Browser):** Friends can search for your Server Name in the official BeamMP Server Browser.
* **Option 2 (Direct Connect):** Friends go to `More...` ➔ `BeamMP` ➔ `Direct Connect` and enter your **Public IP** and Port from `ServerConfig.toml`.

---

## 📦 Adding Custom Mods

To load custom vehicles, maps, or physics mods onto your server:

1. Open the project folder and navigate to:
```text
Resources/Client/
```
2. Drop your mod `.zip` files directly into this directory.
3. Restart the server by running `Start_Here.bat` again to sync mods automatically with everyone who joins.

> **Security note (v0.3):** On launch the tool scans `Resources/Client/` (including inside `.zip` mods) and moves any suspicious executable files (`*.exe`, `*.vbs`, `*.cmd`, `*.scr`, `*.pif`) to the `Quarantine/` folder. Everything it does is written to `Logs/launcher.log`.
>
> **Tip (v0.4):** Run `Start_Here.bat mods` for a menu that lists your mods with sizes, lets you disable/enable them (moved to `Server\Backups\mods\`), re-runs the security scan, and opens the folder in Explorer.

---

## 🔌 Optional: Discord Server Announcements

1. Create a webhook in your Discord channel (`Channel Settings > Integrations > Webhooks`).
2. Copy `webhook.example.txt` to `webhook.txt` next to the `.exe`.
3. Paste your webhook URL into `webhook.txt` and save.
4. The launcher posts an **`[ONLINE]`** embed when the server starts, an **`[OFFLINE]`** embed when it stops, and **join/leave** embeds when players enter or leave the server *(v0.4)*.
   Leave `webhook.txt` empty or deleted to disable this feature.

---

## 🛠️ Troubleshooting & FAQ

> **"Invalid ZIP File" Pop-up?**
> Ignore this message! BeamNG scans files while BeamMP streams them in real time. Simply let the progress bar finish loading.

> **Server Window Closes Instantly?**
> Check your `ServerConfig.toml` file. This usually happens if the `AuthKey` was pasted incorrectly or left blank. With the launcher, make sure your `.env` file contains a valid `BEAMMP_AUTHKEY=...` (or the `BEAMMP_AUTHKEY` environment variable is set).

> **Tool says the server failed to start?**
> The tool waits for the server to actually listen on the configured port before showing "SERVER IS LIVE!". If it fails, it **auto-diagnoses the cause** *(v0.4)* — bad/empty AuthKey, port already in use, missing Visual C++ runtime, unreachable BeamMP backend, or a missing map — and shows you the exact fix. Also make sure Windows Firewall allows `BeamMP-Server.exe` (the launcher's Fix menu creates the rules for you and never duplicates them).

---

## 👑 Credits & Ownership

* **Sole Developer & Creator:** **Kinan** (`@raed713`)
*All original code, tools, scripts, and rights belong strictly and exclusively to Kinan.*
* **Official Discord:** [Innocent BeamMP Server Community](https://discord.gg/2FxsJvKr4a)
