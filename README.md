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

> ⚠️ **Official download only:** Get K BNG M Hoster exclusively from the [GitHub Releases page](https://github.com/Kinan0713/K-BNG-M-Hoster/releases/latest) above. Please do **not** share, reupload, or forward this tool to others — everyone should download it from here so they always get the latest version.

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
| 👥 **Live Player Activity** | Shows who's online, with optional Discord join/leave notifications. |
| 🧹 **Privacy Cleaner** | One menu option removes all personal/temporary files from the folder. |
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

### 1️⃣ Input Your Auth Key *(Automatic — Recommended)*

1. Go to [BeamMP Keymaster](https://keymaster.beammp.com) and generate a new key.

>

### 2️⃣ Note on Ports


### 3️⃣ Utility Commands

| Command | What it does |
| --- | --- |
| `Start_Here.bat` | **Just double-click this.** Everything else is automatic |
| `Start_Here.bat mods` | Open the Mod Manager (list, disable, enable, scan mods) |
| `Start_Here.bat fix` | Open the Help / Fix Problems menu (firewall, UPnP, port, key, VPN checks) |
| `Start_Here.bat help` | Show usage |


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
   ```toml
   Private = false
   Port = 30814
   ```
4. Double-click **`Start_Here.bat`** to launch the server.
5. Watch the live status screen: it shows whether your `public IP:port` is **reachable** from the internet, and warns you about VPN adapters or CGNAT networks that would block players.
6. Open **BeamNG.drive** and connect via `Direct Connect` (`127.0.0.1:30814`).

#### 👥 How Friends Join

- **Option 1 (Server Browser):** players can search for your Server Name in the official BeamMP Server Browser.


---

## 📦 Adding Custom Mods

To load custom vehicles, maps, or physics mods onto your server:

1. Open the project folder and navigate to:
   ```
   ```
2. Drop your mod `.zip` files directly into this directory.
3. Restart the server by running `Start_Here.bat` again to sync mods automatically with everyone who joins.

>

---

## 🔌 Optional: Discord Server Announcements

1. Create a webhook in your Discord channel (`Channel Settings > Integrations > Webhooks`).
4. The launcher posts an **`[ONLINE]`** embed when the server starts, an **`[OFFLINE]`** embed when it stops, and **join/leave** embeds when players enter or leave the server.

---

## 🛠️ Troubleshooting & FAQ

> **"Invalid ZIP File" Pop-up?**
> Ignore this message! BeamNG scans files while BeamMP streams them in real time. Simply let the progress bar finish loading.

> **Server Window Closes Instantly?**

> **Tool says the server failed to start?**
> The tool waits for the server to actually listen on the configured port before showing "SERVER IS LIVE!". If it fails, it **auto-diagnoses the cause** — bad/empty AuthKey, port already in use, missing Visual C++ runtime, unreachable BeamMP backend, or a missing map — and shows you the exact fix.

> **"NOT reachable" on the external test?**

> **Does everyone use the same port?**
> Yes — port 30814 is the BeamMP standard for everyone. That's fine: every host has a unique public IP, so `IP:port` never collides between different networks. The only exception is two hosts sharing one public IP (same LAN/VPN) — the launcher auto-switches the port in that case.

> **I don't want to touch my router at all.**
> Use **Method A (Tailscale)** — no port forwarding needed, works over any network.

---

## 🔐 Security & Privacy

- **No data collection.** The tool is offline, local-only software. It never phones home, sends logs, or uploads anything except the normal BeamMP server traffic.
- **Clean personal info (menu option 5):** you can remove all personal information from the folder (keys, webhooks, logs, backups and session files) at any time.
- **Mod safety.** ZIP mods are scanned for executable payloads before being served to players.

---

## 📜 Version History


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

### ❌ Strictly Prohibited

- Modifying source code or scripts that are not explicitly authorized
- Reverse-engineering, decompilation, or extraction of internal logic
- Reuploading, mirroring, forking, redistributing, or selling the software
- Sharing the ZIP or the tool itself outside the official [GitHub Releases page](https://github.com/Kinan0713/K-BNG-M-Hoster/releases/latest)
- Removing, altering, or obscuring author attribution (Kinan / @raed713)
- Accessing internal scripts or proprietary files not explicitly permitted

**For permissions, DMCA, or legal inquiries:** open an [issue on GitHub](https://github.com/Kinan0713/K-BNG-M-Hoster/issues)