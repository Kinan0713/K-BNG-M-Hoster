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

### *(Kinan BeamNG Multiplayer Hoster)* — **v0.6.6** *(Update 6 - Fix 6)*

**The All-In-One Automated BeamMP Hosting & Joining Tool**

> 🔽 **Download the latest release:** [K BNG M Hoster v0.6.6-FIX ZIP](https://github.com/Kinan0713/K-BNG-M-Hoster/releases/latest)

> ⚠️ **Official download only:** Get K BNG M Hoster exclusively from the [GitHub Releases page](https://github.com/Kinan0713/K-BNG-M-Hoster/releases/latest) above. Please do **not** share, reupload, or forward this tool to others — everyone should download it from here so they always get the latest version.

*Solely created and developed by **Kinan** (`@raed713`)*

---

## 📌 What is K BNG M Hoster?

**K BNG M Hoster** is an all-in-one automation utility designed to make hosting, configuring, and joining BeamMP multiplayer servers effortless. Built entirely from scratch, it handles process execution, automates background server management, and streamlines the direct connection workflow so you and your friends can drive together in seconds.

### ✨ Key Features

| Feature | What it does for you |
| --- | --- |
| 🪟 **Full GUI (v0.6.0)** | The whole tool is now a **window** — no console, no menus to memorize. Works with **mouse and keyboard**: every button explains itself in a tooltip, `Tab`/`Shift+Tab`, `Enter`, `Esc`, plus `Ctrl+H` Home, `Ctrl+S` Start, `Ctrl+X` Stop, `Ctrl+F` Fix, `Ctrl+V` VPN, `Ctrl+M` Mods, `Ctrl+T` Customisation, `Ctrl+D` Diagnose, `Ctrl+C` Copy IP, `Ctrl+G` Guide, `F11`/`Alt+Enter` fullscreen. The shortcuts are always listed at the bottom of the window. |
| 📖 **Built-in Guide** | The whole README is inside the app — press **Guide** (or `Ctrl+G`) for plain-language steps: start, key, how friends connect, firewall, mods, and sharing safely. |
| 🖱️ **One-Click Launch** | Double-click `Start_Here.bat`. Everything else is automatic. |
| 🔑 **Auto AuthKey** | Paste your BeamMP key once — the tool stores it privately, injects it at start, and removes it again when the session ends. |
| 🎛️ **Customisation on Home (v0.6.6)** | All settings live right on the Home page in a collapsible **Customisation** section — server name, max players, free port, IP lock, server key, public/private and the map. No separate Settings tab; `Ctrl+T` opens it from anywhere. |
| 🩺 **Fix Problems page** | Every check is one row with `[OK]` / `[X]` / `[?]` and its own Fix button: key, launcher, BeamNG, port, Visual C++ runtime, firewall, VPNs, CGNAT and external reachability. Plus one-click UPnP forwarding and **Fix all possible** — one click that frees the port, adds the firewall rule, applies a valid map and forwards via UPnP. The scan only runs when you press the button — never on its own. |
| 🔄 **Auto Diagnostics** | If the server fails to start, the tool reads the server log and tells you *exactly* why (bad key, busy port, missing runtime, bad map). |
| 🌍 **UPnP Port Forwarding** | Automatically forwards your port (TCP+UDP) on router-enabled setups — no manual router login needed. |
| 🛡️ **Auto Firewall** | Opens the correct Windows Firewall rules with one polite UAC prompt — existing rules are detected and never duplicated (v0.5.3). |
| 🔒 **Lock my IP while hosting** | Keeps your LAN IP fixed during a session so router port-forwards never break on DHCP renewals; auto-returns to DHCP when the session ends (v0.5.3, Customisation on the Home page). |
| 🧭 **Reachability Test** | Checks whether your public IP:port is actually reachable from the internet and shows the result on the Dashboard — with retries and a fallback service (v0.5.3), plus a full scan inside the Fix Problems page. |
| ⚠️ **Smart Warnings** | Detects CGNAT ISPs (checks both your public IP **and your router's WAN IP** via UPnP — v0.5.3) and tells you exactly what to do. |
| 🖧 **VPN Manager page** | Sees if **Radmin VPN / Hamachi / ZeroTier / Tailscale** are installed and running, starts any of them with one click, or opens the official download page when missing. If you have two VPNs running at once it tells you — friends must be on the same one as the IP you send. |
| 🔗 **VPN Hosting** | VPNs (Radmin VPN, Hamachi, ZeroTier, Tailscale) are supported connection methods that work even behind **CGNAT** — the Dashboard shows the VPN IP line for friends automatically. |
| 🔄 **Busy-Port Auto-Switch** | If your port is taken, picks a free one and warns you loudly. |
| 👥 **Live Player Activity** | Shows who's online, with optional Discord join/leave notifications. |
| 🧹 **Privacy Cleaner** | One button removes all personal/temporary files from the folder. |
| 📡 **Flexible Hosting** | Works with **Tailscale**, **Radmin VPN / Hamachi / ZeroTier** (no port forwarding) **or** public port forwarding. |

---

## 🚀 QUICK START (30 seconds)

1. **Extract** the ZIP to any folder.
2. **Double-click `Start_Here.bat`** — a window opens. That's it, no other setup.
3. First time: accept the license, then the tool asks you to **paste your BeamMP key**, and your server starts automatically.
4. While playing, tell players to connect using the address shown on the window (press **Ctrl+C** or the **Copy IP** button to copy it).

That's everything. The tool handles the server key, settings, ports and problems for you.

---

## ⚡ Setup Requirements

| Requirement | Purpose | Download Link |
|---|---|---|
| **BeamMP Keymaster** | Get your free server authentication key | [Keymaster Portal](https://keymaster.beammp.com) |
| **BeamMP Client** | Official multiplayer client for BeamNG.drive | [Download Client](https://beammp.com) |
| **Tailscale** *(Method A)* | Secure direct connection without changing router settings | [Download Tailscale](https://tailscale.com) |
| **Radmin VPN** *(Method C)* | Free P2P VPN — friends join your virtual network | [Download Radmin VPN](https://www.radmin-vpn.com/) |
| **Hamachi** *(Method C)* | Free P2P VPN (up to 5 devices per network) | [Download Hamachi](https://www.vpn.net/) |
| **ZeroTier** *(Method C)* | Free, open-source P2P VPN | [Download ZeroTier](https://www.zerotier.com/download/) |

---

## ⚙️ Step-by-Step Configuration Guide

### 1️⃣ Input Your Auth Key *(Automatic — Recommended)*

1. Go to [BeamMP Keymaster](https://keymaster.beammp.com) and generate a new key.

>

### 2️⃣ Note on Ports


### 2️⃣.5️⃣ Locking your IP while hosting (v0.5.3)

If your ISP/router assigns your PC a **new local IP** from time to time, your port-forward rule silently breaks and players can no longer join. The **Customisation section — "Lock my IP while hosting"** fixes this:

- When **ON**, the tool sets your network adapter to a static IP at server start and **restores DHCP automatically** when your session ends.
- The tool never touches adapters it didn't lock itself (a manually configured static IP is left exactly as it is).

### 3️⃣ Utility Commands

| Command | What it does |
| --- | --- |
| `Start_Here.bat` | **Just double-click this.** The window opens — everything else is automatic |
| `Start_Here.bat mods` | Open the window on the Mods page (list, disable, enable, scan mods) |
| `Start_Here.bat fix` | Open the window on the Fix Problems page (firewall, UPnP, port, key, VPN checks) |
| `Start_Here.bat setup` | Open the window with the key setup dialog |
| `Start_Here.bat help` | Show usage |


---

## 🌐 Server Launch & Connection Methods

Choose **one** of the hosting methods below depending on how you want players to connect:

### 🔹 METHOD A: Tailscale (Private / No Port Forwarding)

*Best for playing privately with a group of friends without altering router settings.*

#### 🛠️ Host Setup & Connection

1. Launch **Tailscale** on your PC.
2. Double-click **`Start_Here.bat`** and press **Start Server** (or `Ctrl+S`).
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

*Best for hosting publicly so anyone can find your server in the BeamMP Server Browser or join via your Public IP. This is also the **right method when hosting for random/unknown players** — it exposes only the game port (TCP+UDP 30814), nothing else on your PC is reachable.*

#### 🛠️ Host Setup & Connection

1. **Let the tool try first:** on server start the launcher automatically attempts a **UPnP** port forward (TCP+UDP) — no router login needed on UPnP-enabled routers.
   ```toml
   Private = false
   Port = 30814
   ```
4. Double-click **`Start_Here.bat`** and press **Start Server**.
5. Watch the **Home page**: it shows whether your `public IP:port` is **reachable** from the internet, warns about CGNAT networks that block players, and lists every VPN connection line for friends.
6. Open **BeamNG.drive** and connect via `Direct Connect` (`127.0.0.1:30814`).

#### 👥 How Friends Join

- **Option 1 (Server Browser):** players can search for your Server Name in the official BeamMP Server Browser.


---

### 🔹 METHOD C: P2P VPN — Radmin VPN / Hamachi / ZeroTier (Private, no port forwarding)

*Best when port forwarding is impossible (e.g. CGNAT ISPs) and you play with a small group of friends. The **VPN Manager page** handles everything below for you: it shows which VPNs are installed and running, starts them with one click, and opens the official download page for any that are missing.*

#### 🛠️ Host Setup & Connection

1. Install a P2P VPN — any of **Radmin VPN**, **Hamachi**, or **ZeroTier** (or Tailscale, Method A). All are free and safe.
2. Start it (via the **VPN Manager page**, or yourself) and **create/join a network** inside the VPN app.
3. Double-click **`Start_Here.bat`** — the Home page now shows `Friends (VPN <name>): <26.x.x.x/25.x.x.x> : port`.
4. Open **BeamNG.drive** → `More...` ➔ `BeamMP` ➔ `Direct Connect` (`127.0.0.1:30814`).

#### 👥 How Friends Join

1. **Every friend installs the same VPN app** and joins **the same network** as the host.
2. BeamNG → `More...` ➔ `BeamMP` ➔ `Direct Connect`.
3. **IP Address:** the host's **VPN IP** shown on the Home page (press **Ctrl+C** to copy it). **Port:** `30814`.

> ℹ️ **Two VPNs running at once?** The tool lists each one with its own IP and reminds you: friends must be on the **same VPN** as the line you send them. Close the unused one to avoid routing confusion.
>
> ℹ️ **Honest note:** BeamMP officially recommends **Tailscale** for VPN hosting. Radmin VPN / Hamachi / ZeroTier work for most users, but occasionally UDP traffic can be unreliable through them — if friends can connect but lag or drop, switch to Tailscale (Method A).
>
> ⚠️ **SAFETY with strangers:** a P2P VPN puts players on a virtual LAN with your PC — they can reach other things on your machine (file sharing, Remote Desktop, printers). **Only invite people you trust.** To host for random players use **Method B (port forwarding)** — it exposes only the game port — or rent a VPS. Never share your VPN network with strangers. The VPN Manager page warns about this on screen.

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
> Use **Method A (Tailscale)** or **Method C (Radmin VPN / Hamachi / ZeroTier)** — no port forwarding needed, works over any network, even behind CGNAT. The **VPN Manager page** starts or installs them for you.

> **Can I host for random/unknown players?**
> Yes — use **Method B (port forwarding)** or a VPS: it exposes only the game port, so strangers can't reach anything else on your PC. Do **not** invite strangers into a P2P VPN network (Method C) — they'd be on a virtual LAN with your PC and could probe other services. The VPN Manager page warns about this on screen.

---

## 🔐 Security & Privacy

- **No data collection.** The tool is offline, local-only software. It never phones home, sends logs, or uploads anything except the normal BeamMP server traffic.
- **Clean personal info:** the button removes all personal information from the folder (keys, webhooks, logs, backups and session files) at any time.
- **Mod safety.** ZIP mods are scanned for executable payloads before being served to players.

---

## 📜 Version History


---

## 👑 Credits & Ownership

- **Sole Developer & Creator:** **Kinan** (`@raed713`)
- *All original code, tools, scripts, and rights belong strictly and exclusively to Kinan.*
- **Official Discord:** [Innocent BeamMP Server Community](https://discord.gg/2FxsJvKr4a)

### 🤝 Contributions

- **Ali Alldoboni** (`@alialldoboni`) — early co-development of the launcher:
  - v0.2: initial launcher, README, server config, port fixes
  - v0.3: launcher bug fixes and improvements
  - v0.4: user-friendly features and auto-diagnostics
  - v0.5: zero-skill "Simplest Edition" — guided setup + auto-fix
  - v0.5.1 / v0.5.2: IPv4/IPv6 binding fixes so same-PC clients can connect

*(Changes by contributors are merged only after review and approval by Kinan.)*

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