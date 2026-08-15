# ðŸš— K BNG M HOSTER

### *(Kinan BeamNG Multiplayer Hoster)*

### âš¡ **The All-In-One Automated BeamMP Hosting & Joining Tool** âš¡

*Solely created and developed by **Kinan** (`@raed713`)*

> âš ï¸ **OFFICIAL DOWNLOAD ONLY** - This tool is distributed exclusively through the
> GitHub Releases page: https://github.com/Kinan0713/K-BNG-M-Hoster/releases/latest
> Please do NOT share, reupload, or forward this tool to others - everyone should
> download it from there so they always get the latest version.

---

## ðŸš€ QUICK START (30 seconds)

1. **Extract** this ZIP to any folder.
2. **Double-click `Start_Here.bat`** â€” a window opens. That's it, no other setup.
3. First time: accept the license, then the tool asks you to **paste your BeamMP key**, and your server starts automatically.
4. While playing, tell your friends to connect using the address shown in the window (press **Ctrl+C** or the **Copy IP** button to copy it).

That's everything. The tool handles the server key, settings, ports and problems for you.

---

## ðŸ“Œ What is K BNG M Hoster?

**K BNG M Hoster** (*Kinan BeamNG Multiplayer Hoster*) is an all-in-one automation utility designed to make hosting, configuring, and joining BeamMP multiplayer servers effortless. Built entirely from scratch by **Kinan**, it handles process execution, automates background server management, and streamlines the direct connection workflow so you and your friends can drive together in seconds.

### âœ¨ Key Features

* **Home page (v0.6.5):** The hub - live server status, Quick actions tiles (Start / Fix / VPN / Mods / Settings / Guide) and every join address for friends. Private servers are marked `(private - hidden from the server list)`.
* **Public/Private server (v0.6.5):** Settings -> "Server visibility". Public lists your server for everyone; Private hides it - only people you send the address (IP:port) to can join via Direct Connect. Applies on the next server start.
* **Fix all possible (v0.6.5):** One click repairs everything it safely can: busy port, firewall rule, broken map, UPnP forward. The scan streams live progress, adds version/mods/disk-space checks and ends with an OK/attention summary.
* **Full GUI (v0.6.0):** The whole tool is now a **window** - no console, no menus to memorize. Works with **mouse and keyboard**: every button explains itself in a tooltip, `Alt`+underlined letter, `Tab`/`Shift+Tab`, `Enter`, `Esc`, plus `Ctrl+H` Home, `Ctrl+S` Start, `Ctrl+X` Stop, `Ctrl+F` Fix, `Ctrl+V` VPN, `Ctrl+M` Mods, `Ctrl+T` Settings, `Ctrl+D` Diagnose, `Ctrl+C` Copy IP, `Ctrl+G` Guide. The shortcuts are always listed at the bottom of the window.
* **Built-in Guide (v0.6.3):** The whole README is inside the app - press **Guide** (or `Ctrl+G`) for plain-language steps: start, key, how friends connect, firewall, mods, and sharing safely.
* **Zero-Stress Automation:** Handles server startup and process management automatically.
* **One-Click Launch:** Start the host via `Start_Here.bat`.
* **Fix Problems page (v0.6.5):** Every check is one row with [OK] / [X] / [?] and its own Fix button: key, launcher, BeamNG, port, Visual C++ runtime, firewall, mods, disk space, server version, VPNs, CGNAT and external reachability. Plus one-click UPnP forwarding and a "Fix all possible" button.
* **Auto Diagnostics (v0.4):** If the server fails to start, the tool reads the server log and tells you exactly why - bad AuthKey, port already in use, missing Visual C++ runtime, or a bad map.
* **Live Player Activity (v0.4):** Shows how many players are online (and who) while you host, with optional Discord join/leave notifications.
* **Update Checker (v0.4):** Tells you when a newer official BeamMP-Server is available (checked once per day, never blocks startup).
* **Simplest Setup Ever (v0.5):** First run walks you through everything - you only paste your key once. The tool writes all files, auto-picks a free port, and has a one-click **Fix Problems** page.
* **Lock my IP while hosting (v0.5.3):** Keeps your LAN IP fixed during a session so your router's port-forward never breaks when the DHCP lease renews - it auto-returns to DHCP when the session ends (Settings page).
* **Deduplicated Firewall (v0.5.3):** The launcher detects existing Windows Firewall rules and never creates duplicates, even on repeated runs without admin rights.
* **External Reachability Scan (v0.5.3):** The Fix Problems page tests your `publicIP:port` from the internet while your server is live, and gives you step-by-step fixes when it's not reachable.
* **Real CGNAT Detection (v0.5.3):** The tool reads your router's own WAN IP via UPnP - if your ISP hides you behind a `100.x.x.x` carrier NAT, it tells you clearly (and why forwarding can never work) instead of a confusing error.
* **VPN Manager page (v0.5.4):** Shows whether **Radmin VPN / Hamachi / ZeroTier / Tailscale** are installed and running, starts any of them with one click, and opens the official download page for any that are missing. If two VPNs run at once it warns you - friends must use the same one as the IP you send.
* **Pre-Start VPN Help (v0.5.4):** If your ISP is CGNAT, the tool asks whether to start your installed VPNs before the server launches - or offers official download links when you have none.
* **Problem Diagnosis (v0.5.4):** While hosting, press **Ctrl+D** (or the Diagnose button) for a one-screen report of everything (VPNs, LAN/Tailscale/public IPs, CGNAT, UPnP, listening port, firewall) so any problem is explained on the spot.

---

## âš¡ Setup Requirements

Before getting started, make sure you have the following downloads ready:

* **BeamMP Keymaster** - Get your free server authentication key: https://keymaster.beammp.com
* **BeamMP Client** - Official multiplayer client for BeamNG.drive: https://beammp.com
* **Tailscale** (Method A) - Secure direct connection without changing router settings: https://tailscale.com
* **Radmin VPN** (Method C) - Free P2P VPN, friends join your virtual network: https://www.radmin-vpn.com/
* **Hamachi** (Method C) - Free P2P VPN (up to 5 devices per network): https://www.vpn.net/
* **ZeroTier** (Method C) - Free, open-source P2P VPN: https://www.zerotier.com/download/

---

---

## 1ï¸âƒ£ Input Your Auth Key *(Automatic - Recommended)*

1. Go to https://keymaster.beammp.com and generate a new key.

>

---

## 2ï¸âƒ£ Note on Ports


## 2ï¸âƒ£.5ï¸âƒ£ Locking your IP while hosting (v0.5.3)

If your ISP/router assigns your PC a **new local IP** from time to time, your port-forward rule silently breaks and players can no longer join. The **Settings page - "Lock my IP while hosting"** fixes this:

- When **ON**, the tool sets your network adapter to a static IP at server start and **restores DHCP automatically** when your session ends.
- The tool never touches adapters it didn't lock itself (a manually configured static IP is left exactly as it is).

---

## 3ï¸âƒ£ Utility Commands

- `Start_Here.bat` - Just double-click this. The window opens - everything else is automatic
- `Start_Here.bat mods` - Open the window on the Mods page (list, disable, enable, scan mods)
- `Start_Here.bat fix` - Open the window on the Fix Problems page (firewall, UPnP, port, key, VPN checks)
- `Start_Here.bat setup` - Open the window with the key setup dialog
- `Start_Here.bat help` - Show usage


---

## ðŸŒ Server Launch & Connection Methods

Choose **one** of the hosting methods below depending on how you want players to connect:

### ðŸ”¹ METHOD A: Tailscale (Private / No Port Forwarding)

*Best for playing privately with a group of friends without altering router settings.*

**Host setup & connection:**
1. Launch **Tailscale** on your PC.
2. Double-click **`Start_Here.bat`** and press **Start Server** (or `Ctrl+S`).
3. Open **BeamNG.drive**.
4. Go to: `More...` -> `BeamMP` -> `Direct Connect`
5. Connect using:
   - **IP Address:** `127.0.0.1`

**How friends join:**
1. Ensure all players are connected to the Host's network inside **Tailscale**.
2. Open BeamNG via the official **BeamMP Launcher**.
3. Go to: `More...` -> `BeamMP` -> `Direct Connect`
4. Connect using:
   - **IP Address:** Host's Tailscale IP (`100.x.x.x`)
   - **Port:** `30814`

---

### ðŸ”¹ METHOD B: Port Forwarding (Public Server List)

*Best for hosting publicly so anyone can find your server in the BeamMP Server Browser or join via your Public IP. This is also the **right method when hosting for random/unknown players** - it exposes only the game port (TCP+UDP 30814), nothing else on your PC is reachable.*

**Host setup & connection:**
1. **Let the tool try first:** on server start the launcher automatically attempts a **UPnP** port forward (TCP+UDP) - no router login needed on UPnP-enabled routers.
   - `Private = false`
   - `Port = 30814`
4. Double-click **`Start_Here.bat`** and press **Start Server**.
5. Watch the **Home page**: it shows whether your `public IP:port` is **reachable** from the internet, warns about CGNAT networks that block players, and lists every VPN connection line for friends.
6. Open **BeamNG.drive** and connect via `Direct Connect` (`127.0.0.1:30814`).

**How friends join:**
- **Option 1 (Server Browser):** players can search for your Server Name in the official BeamMP Server Browser.


---

### ðŸ”¹ METHOD C: P2P VPN - Radmin VPN / Hamachi / ZeroTier (Private, no port forwarding)

*Best when port forwarding is impossible (e.g. CGNAT ISPs) and you play with a small group of friends. The **VPN Manager page** handles everything below for you: it shows which VPNs are installed and running, starts them with one click, and opens the official download page for any that are missing.*

**Host setup & connection:**
1. Install a P2P VPN - any of **Radmin VPN**, **Hamachi**, or **ZeroTier** (or Tailscale, Method A). All are free and safe.
2. Start it (via the **VPN Manager page**, or yourself) and **create/join a network** inside the VPN app.
3. Double-click **`Start_Here.bat`** - the Home page now shows `Friends (VPN <name>): <26.x.x.x/25.x.x.x> : port`.
4. Open **BeamNG.drive** -> `More...` -> `BeamMP` -> `Direct Connect` (`127.0.0.1:30814`).

**How friends join:**
1. **Every friend installs the same VPN app** and joins **the same network** as the host.
2. BeamNG -> `More...` -> `BeamMP` -> `Direct Connect`.
3. **IP Address:** the host's **VPN IP** shown on the Home page (press **Ctrl+C** to copy it). **Port:** `30814`.

> â„¹ï¸ **Two VPNs running at once?** The tool lists each one with its own IP and reminds you: friends must be on the **same VPN** as the line you send them. Close the unused one to avoid routing confusion.
>
> â„¹ï¸ **Honest note:** BeamMP officially recommends **Tailscale** for VPN hosting. Radmin VPN / Hamachi / ZeroTier work for most users, but occasionally UDP traffic can be unreliable through them - if friends can connect but lag or drop, switch to Tailscale (Method A).
>
> âš ï¸ **SAFETY with strangers:** a P2P VPN puts players on a virtual LAN with your PC - they can reach other things on your machine (file sharing, Remote Desktop, printers). **Only invite people you trust.** To host for random players use **Method B (port forwarding)** - it exposes only the game port - or rent a VPS. Never share your VPN network with strangers. The VPN Manager page warns about this on screen.

---

## ðŸ“¦ Adding Custom Mods

To load custom vehicles, maps, or physics mods onto your server:

2. Drop your mod `.zip` files directly into this directory.
3. Restart the server by running `Start_Here.bat` again to sync mods automatically with everyone who joins.

>

---

## ðŸ”Œ Optional: Discord Server Announcements

1. Create a webhook in your Discord channel (`Channel Settings > Integrations > Webhooks`).
4. The launcher posts an **[ONLINE]** embed when the server starts, an **[OFFLINE]** embed when it stops, and **join/leave** embeds when players enter or leave the server.

---

## ðŸ› ï¸ Troubleshooting & FAQ

> **"Invalid ZIP File" Pop-up?**
> Ignore this message! BeamNG scans files while BeamMP streams them in real time. Simply let the progress bar finish loading.

> **Server Window Closes Instantly?**

> **Tool says the server failed to start?**
> The tool waits for the server to actually listen on the configured port before showing "SERVER IS LIVE!". If it fails, it **auto-diagnoses the cause** - bad/empty AuthKey, port already in use, missing Visual C++ runtime, unreachable BeamMP backend, or a missing map - and shows you the exact fix.

> **"NOT reachable" on the external test?**

> **Does everyone use the same port?**
> Yes - port 30814 is the BeamMP standard for everyone. That's fine: every host has a unique public IP, so `IP:port` never collides between different networks. The only exception is two hosts sharing one public IP (same LAN/VPN) - the launcher auto-switches the port in that case.

> **I don't want to touch my router at all.**
> Use **Method A (Tailscale)** or **Method C (Radmin VPN / Hamachi / ZeroTier)** - no port forwarding needed, works over any network, even behind CGNAT. The **VPN Manager page** starts or installs them for you.

> **Can I host for random/unknown players?**
> Yes - use **Method B (port forwarding)** or a VPS: it exposes only the game port, so strangers can't reach anything else on your PC. Do **not** invite strangers into a P2P VPN network (Method C) - they'd be on a virtual LAN with your PC and could probe other services. The VPN Manager page warns about this on screen.

---

## ðŸ” Security & Privacy

- **No data collection.** The tool is offline, local-only software. It never phones home, sends logs, or uploads anything except the normal BeamMP server traffic.
- **Clean personal info:** the button removes all personal information from the folder (keys, webhooks, logs, backups and session files) at any time.
- **Mod safety.** ZIP mods are scanned for executable payloads before being served to players.

---

## ðŸ“œ Version History


---

## ðŸ‘‘ Credits & Ownership

- **Sole Developer & Creator:** **Kinan** (`@raed713`)
- *All original code, tools, scripts, and rights belong strictly and exclusively to Kinan.*
- **Official Discord:** https://discord.gg/2FxsJvKr4a (Innocent BeamMP Server Community)

### ðŸ¤ Contributions

- **Ali Alldoboni** (`@alialldoboni`) - early co-development of the launcher:
  - v0.2: initial launcher, README, server config, port fixes
  - v0.3: launcher bug fixes and improvements
  - v0.4: user-friendly features and auto-diagnostics
  - v0.5: zero-skill "Simplest Edition" - guided setup + auto-fix
  - v0.5.1 / v0.5.2: IPv4/IPv6 binding fixes so same-PC clients can connect

*(Changes by contributors are merged only after review and approval by Kinan.)*

---

## ðŸ“œ License & Legal

This project is distributed under a proprietary EULA. By using this software you agree to the terms set in the LICENSE file.

**Permitted actions:**
- Running the unmodified packaged software

**Strictly prohibited:**
- Modifying source code or scripts that are not explicitly authorized
- Reverse-engineering, decompilation, or extraction of internal logic
- Reuploading, mirroring, forking, redistributing, or selling the software
- Sharing the ZIP or the tool itself outside the official GitHub Releases page
- Removing, altering, or obscuring author attribution (Kinan / @raed713)
- Accessing internal scripts or proprietary files not explicitly permitted

**For permissions, DMCA, or legal inquiries:** open an issue on GitHub: https://github.com/Kinan0713/K-BNG-M-Hoster/issues
