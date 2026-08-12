Here is the full, updated `README.md` code reflecting the new project name **K BNG M Hoster** (*Kinan BeamNG Multiplayer Hoster*):

# 🚗 K BNG M HOSTER

### *(Kinan BeamNG Multiplayer Hoster)*

### ⚡ **The All-In-One Automated BeamMP Hosting & Joining Tool** ⚡

*Solely created and developed by **Kinan** (`@raed713`)*

---

## 📌 What is K BNG M Hoster?

**K BNG M Hoster** (*Kinan BeamNG Multiplayer Hoster*) is an all-in-one automation utility designed to make hosting, configuring, and joining BeamMP multiplayer servers effortless. Built entirely from scratch by **Kinan**, it handles process execution, automates background server management, and streamlines the direct connection workflow so you and your friends can drive together in seconds.

### ✨ Key Features

* **Zero-Stress Automation:** Handles server startup and process management automatically.
* **Flexible Hosting Options:** Full support for both **Tailscale (No Port Forwarding)** and **Public Port Forwarding**.
* **Seamless Mod Syncing:** Load custom vehicles and maps directly through client resources.
* **One-Click Launch:** Start the host via `K_BNG_M_Hoster.exe`.
* **Session-Aware Lifecycle (v0.3):** The server starts with your game session and stops automatically the moment the session ends.
* **One-Click Launch:** Pre-configured script execution via `Play_BeamMP.bat`.

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

### 1️⃣ Extract & Open

1. Download **K BNG M Hoster** and extract the ZIP folder to your preferred location.
2. Locate `ServerConfig.toml` inside the main folder.
3. Open `ServerConfig.toml` using **Notepad** or your preferred text editor.

### 2️⃣ Input Your Auth Key *(Automatic — Recommended)*

The launcher now injects your key automatically, so you **never have to paste it into `ServerConfig.toml` by hand**.

1. Go to [BeamMP Keymaster](https://keymaster.beammp.com) and generate a new key.
2. Copy `.env.example` to `.env` in the main folder:
```
copy .env.example .env
```
3. Open `.env` and paste your key:
```
BEAMMP_AUTHKEY=PASTE_YOUR_KEY_HERE
```
4. Save and close. Before every launch, the tool reads `.env`, writes your key into `AuthKey` inside `ServerConfig.toml`, and starts the server.
5. `.env` is **git-ignored**, so your key can never be pushed to GitHub.

> **Alternative — Windows environment variable:** set a system/user variable named `BEAMMP_AUTHKEY`. The environment variable takes priority over `.env`.
>
> **Manual fallback:** you can still paste the key directly into `ServerConfig.toml` (line 7, `AuthKey = "..."`); the launcher leaves an already-set key untouched if neither `.env` nor the environment variable exists.

### 3️⃣ Note on Ports

The server port is read from `Port` in `ServerConfig.toml`. Adjust the connection examples below (and your router/Tailscale rules) to match whatever port you set there.

---

## 🌐 Server Launch & Connection Methods

Choose **one** of the two hosting methods below depending on how you want players to connect:

---

### 🔹 METHOD A: Tailscale (Private / No Port Forwarding)

*Best for playing privately with a group of friends without altering router settings.*

#### 🛠️ Host Setup & Connection

1. Launch **Tailscale** on your PC.
2. Double‑click **`K_BNG_M_Hoster.exe`** to start the host.
3. Accept the license prompt, then the tool opens the BeamMP Launcher automatically.
4. Open **BeamNG.drive**.
5. Go to: `More...` ➔ `BeamMP` ➔ `Direct Connect`
6. Connect using:
* **IP Address:** `127.0.0.1`
* **Port:** `30813` *(or whatever `Port` is set to in ServerConfig.toml)*

#### 👥 How Friends Join

1. Ensure all friends are connected to the Host’s network inside **Tailscale**.
2. Open BeamNG via the official **BeamMP Launcher**.
3. Go to: `More...` ➔ `BeamMP` ➔ `Direct Connect`
4. Connect using:
* **IP Address:** Host's Tailscale IP (`100.x.x.x`)
* **Port:** `30813` *(or whatever `Port` is set to in ServerConfig.toml)*

---

### 🔹 METHOD B: Port Forwarding (Public Server List)

*Best for hosting publicly so anyone can find your server in the BeamMP Server Browser or join via your Public IP.*

#### 🛠️ Host Setup & Connection

1. Access your router settings and forward the port from `ServerConfig.toml` (default **`30813`**, TCP/UDP) to your local IP address.
2. Open `ServerConfig.toml` and verify your settings:
```toml
Private = false
Port = 30813
```
3. Run **`K_BNG_M_Hoster.exe`** to launch the server.
4. Open **BeamNG.drive** and connect via `Direct Connect` (`127.0.0.1:30813`).

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
3. Restart the server by running `K_BNG_M_Hoster.exe` again to sync mods automatically with everyone who joins.

> **Security note (v0.3):** On launch the tool scans `Resources/Client/` (including inside `.zip` mods) and moves any suspicious executable files (`*.exe`, `*.vbs`, `*.cmd`, `*.scr`, `*.pif`) to the `Quarantine/` folder. Everything it does is written to `Logs/launcher.log`.

---

## 🔌 Optional: Discord Server Announcements

1. Create a webhook in your Discord channel (`Channel Settings > Integrations > Webhooks`).
2. Copy `webhook.example.txt` to `webhook.txt` next to the `.exe`.
3. Paste your webhook URL into `webhook.txt` and save.
4. The launcher posts an **`[ONLINE]`** embed when the server starts and an **`[OFFLINE]`** embed when it stops.
   Leave `webhook.txt` empty or deleted to disable this feature.

---

## 🛠️ Troubleshooting & FAQ

> **"Invalid ZIP File" Pop-up?**
> Ignore this message! BeamNG scans files while BeamMP streams them in real time. Simply let the progress bar finish loading.

> **Server Window Closes Instantly?**
> Check your `ServerConfig.toml` file. This usually happens if the `AuthKey` was pasted incorrectly or left blank. With the launcher, make sure your `.env` file contains a valid `BEAMMP_AUTHKEY=...` (or the `BEAMMP_AUTHKEY` environment variable is set).

> **Tool says the server failed to start?**
> The tool waits for the server to actually listen on the configured port before showing "SERVER IS LIVE!". If it reports failure, check that your `.env` `BEAMMP_AUTHKEY` (or the env var / manual `AuthKey`) is valid, that port `30813` isn't already in use, and that Windows Firewall allows `BeamMP-Server.exe`.

---

## 👑 Credits & Ownership

* **Sole Developer & Creator:** **Kinan** (`@raed713`)
*All original code, tools, scripts, and rights belong strictly and exclusively to Kinan.*
* **Official Discord:** [Innocent BeamMP Server Community](https://discord.gg/2FxsJvKr4a)

```

```
