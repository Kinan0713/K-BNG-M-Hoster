## v0.6.7 - Update 6, Fix 7: Stats page, the Settings tab is back, and fullscreen/layout fixes

- **Stats page:** the Home page is renamed to **Stats** - it shows your live server
  status and every address friends can use to join (LAN / VPN / internet).
- **Settings tab is back (Ctrl+T):** server name, max players, free port, IP lock,
  server key, map and public/private now live in their own tab again instead of the
  collapsed "Customisation" section on the Home page.
- **Fullscreen fixed:** exiting fullscreen (F11 / Alt+Enter) now restores the window
  exactly as it was - border, size and position - instead of losing the maximized
  state or leaving a stale layout.
- **Layout fixes:** the Fix / VPN / Mods page headers now re-position their buttons
  below wrapped text instead of overlapping it when the window is wide or small.
- **Cleaner labels:** fix-row buttons no longer draw stray underline artifacts.
- **Docs updated:** the README was rewritten - the app is fully explained, only the
  launcher file is ever mentioned, and the license do's and don'ts are spelled out.

## v0.6.5 - Update 6, Fix 5: Public/Private server, a new Home page, one-click Fix all, faster tabs and a fixed fullscreen

- **Public/Private server (Settings):** choose who can find your server in the BeamMP
  list. Private hides it - only people you send the address (IP:port) to can join via
  Direct Connect. The Home page marks the internet line with "(private...)" and the
  server restarts automatically to apply the change.
- **Home page:** the old Dashboard is now a proper hub - live status card, a Quick
  actions panel (Start / Fix / VPN / Mods / Settings / Guide tiles) and every join
  address for friends. Press Ctrl+H or the Home button on the toolbar.
- **Fix Problems upgrades:** the scan streams live progress to the log, adds new
  checks (server version, mods health, disk space, firewall/port match) and finishes
  with a summary banner ("X of N checks OK, M need attention"). A new **"Fix all
  possible"** button repairs everything it safely can in one click (busy port,
  firewall rule, broken map, UPnP forward) and tells you exactly what still needs you.
- **Faster tabs:** the Fix scan no longer re-reads every map zip every time (12h disk
  cache) and reuses the cached public IP instead of a fresh web call. The Mods page
  loads instantly from a cached list and refreshes in the background.
- **Fullscreen fixed:** maximizing (or going fullscreen) no longer leaves the page
  layout stale - every tab now relayouts correctly on the very first maximize.
- **New header:** taller, with the version shown in a chip on the right - the subtitle
  no longer clips into the title.
- **Guide:** new step explaining Public vs Private, updated for the Home page and the
  Fix-all button.

## v0.6.6 - Update 6, Fix 6: the v0.6.5 crash fixed, Settings moved onto the Home page, and small quality-of-life fixes

- **Fixes the v0.6.5 crash:** when a Fix scan finished, the app hit an unexpected error
  window ("Fix Problems is broken"). The root cause was a PowerShell variable-name clash
  inside the color table - a fix-row label leaked into the row builder and turned a
  harmless property set into a fatal exception. The color table is renamed and the crash
  is gone. The Fix page also now completes cleanly after scans and "Fix all possible".
- **Settings moved into the Home page ("Customisation"):** there is no separate Settings
  tab anymore. The Home page has a collapsible **Customisation** section with everything:
  server name, max players, free port, IP lock, server key, public/private and the map
  picker. Open it by clicking the section header, or press **Ctrl+T** from anywhere
  (the Fix "map" row opens it too).
- **Fix page no longer scans on its own:** opening Fix Problems does nothing until you
  press "Re-scan everything" or "Fix all possible" - no surprise background scan, no
  repeated disk work on every visit.
- **Fullscreen (F11 / Alt+Enter):** borderless fullscreen toggle for the whole window,
  press F11 again or Esc to leave. Every page relayouts correctly the first time it
  opens (not only after a resize), so maximize/fullscreen never leaves a stale layout.
- **No more Alt-underline artifacts:** the ampersands that used to draw underlines in
  button labels are gone (the tool never used real Alt-menu mnemonics) - labels are
  clean text now.
- **Docs updated:** README and the in-app Guide describe the Customisation section,
  the new shortcuts and the on-demand Fix scan.

# Changelog

All notable changes to **K BNG M Hoster** are documented here.

## v0.6.4 — Update 6, Fix 4: map picker (all your maps + map mods), mods multi-select, and every text now fits its frame

- **Map picker (Settings):** scan all maps found on your PC — the game's built-in maps
  (gridmap, utah, west coast, east coast, italy, industrial, ...) and your MAP MODS.
  Pick one and press Apply map. Map mods are hosted automatically and sent to players
  when they join. The map applies on the next server start — the tool offers to restart
  for you. Changing maps from inside the game is no longer needed (it broke the
  multiplayer player/ping display).
- **Fix Problems** now checks the map: if ServerConfig.toml points to a map that is not
  found on this PC, the row turns red with a one-click fix.
- **Mods multi-select:** Ctrl+click picks several mods, Shift+click selects a range,
  Ctrl+A selects all — just like Windows Explorer. Disable/Enable acts on every selected
  mod. A tip line under the lists explains the shortcuts.
- **Guide page:** removed the duplicate jump buttons (the toolbar on top does that).
- **Everything fits now:** status bar shortcuts, dashboard server line, CGNAT warning,
  VPN tips, mods header and settings page (scrollable) — all text is measured against
  its frame at every window size and never clips or overlaps.

## v0.6.3 — Update 6, Fix 3: mods drag & drop, auto-update, polished Guide and Fix buttons

### 🎮 Mods drag & drop
- Drop any `.zip` mod **anywhere** on the Mods page (either list or the page itself) — it is scanned for executables (`.exe/.vbs/.cmd/.scr/.pif`) and added to `Resources\Client` automatically; suspicious files go to Quarantine instead
- The list highlights green while you drag a zip over it, so you can see exactly where to drop
- Replacing an existing mod shows "(replaced an existing file)" in the log

### 🔄 Automatic updates (checks GitHub every time the app opens)
- On every open, the tool silently checks your GitHub repo for a newer release
- If one exists: **Download & install now / Open link / Not now**
- Download is verified (must be a real K BNG M Hoster zip), then the app closes and reinstalls itself automatically — **your key, mods, settings and logs are kept**, old downloaded versions are deleted, and the new version starts by itself
- Progress is logged to `Server\Logs\updater.log` if anything ever goes wrong

### 📖 Guide page rebuilt (professional look, fixed text size)
- The guide now sits in a **rounded card with real padding** — text no longer touches the edges
- Fixed the text rendering bug: the control is created with an explicit font before any text is written, so everything renders at the intended size
- Step headers (yellow, bold) and indented body text give it a clean, readable hierarchy; jump-buttons are right-aligned and auto-sized
- New **STEP 8** explains how the auto-update works

### 🛠 Fix Problems buttons now fit their text
- The Fix/Info buttons on each row **auto-size to their text** (right-aligned, ellipsis fallback) — long labels like "Show step-by-step fixes for the NOT-reachable result" fit fully instead of clipping

### ✅ Verified
- All scripts parse cleanly; drag & drop, auto-update check + download chain, Guide rendering and fix-scan verified twice on a real screen; the app was re-scanned for personal info before release (no IPs, keys, webhooks or logs in the zip)

## v0.6.2 — Update 6, Fix 2: bulletproof launcher, everything in one folder, built-in Guide

### 🚀 Launcher fixed (no more "cmd opens then nothing")
- `Start_Here.bat` launches the GUI and closes itself instantly — no black console window on screen. The GUI still works exactly the same (mouse, keyboard, all pages)
- If the launcher can't find the GUI script (for example when double-clicked inside the zip without extracting), it now shows a **clear error message** instead of silently closing
- The GUI startup is wrapped in error handling — any fatal problem shows a message box instead of the window vanishing

### 📁 Everything in one folder (the user only sees `Start_Here.bat`)
- The release ZIP top level now contains **only** `Start_Here.bat` — that is the only file anyone ever needs to click
- Everything else lives inside the `Server\` folder: `ServerConfig.toml`, `Resources\Client\` (mods), the server engine, scripts, `README.txt`, `CHANGELOG.md`, examples and support files
- Server settings (name, players, port, key) are all managed from the GUI Settings page — no config file ever needs to be opened

### 📖 Built-in Guide (the README is now inside the app)
- New **Guide** page (`Ctrl+G` or the Guide button, also `Start_Here.bat help`): plain-language steps for start, key setup, how friends connect (this PC / LAN / VPN / internet), firewall & port forwarding, mods, and sharing the folder safely
- No need to open any files — everything is one button away

### ✅ Verified
- GUI launches from the new layout with no console window; all paths still resolve (config, mods, logs, key, webhook); all pages and modes (`mods`, `fix`, `setup`, `help`) work

## v0.6.1 — Update 6, Fix 1: polished GUI: rounded corners, responsive layout, smarter VPN page

### 🎨 Visual polish
- Every button, panel and dialog now has **rounded corners** (including the EULA, key-setup and CGNAT dialogs)
- The **Clean personal info** button is now red, so it stands out from the other buttons
- The window **scales to any size**: every control stretches and repositions when you resize the window — nothing overlaps or clips, from tiny windows to full screen
- The whole window is now a single rounded window (no sharp corners) with a cleaner header

### 🧠 Fix Problems page
- The Fix rows now **grow to fit their text** — long explanations wrap onto multiple lines instead of being cut off

### 🖧 VPN Manager page
- Fixed: the Start/Download buttons on VPN rows were stuck in the corner of the page (they are now positioned on the right side of each row, where they belong)
- Rows now span the full page width like the Fix page rows

### ✅ Verified
- Scripts parse cleanly; buttons verified rounded at the pixel level; the VPN rows, resize behaviour and EULA dialog verified on a real screen; no layout errors in the activity log across all pages and sizes

## v0.6.0 — GUI edition: the console menus are now a window

### 🪟 The whole tool is now a window (no console)
- Every menu, screen and prompt from the console edition is now a **graphics window** — friendlier, clearer, and easier to use. The console window no longer opens (the launchers hide it)
- **Works with mouse and keyboard:** every button has a tooltip explaining exactly what it does, and a keyboard shortcut (`Alt`+underlined letter, `Tab`/`Shift+Tab`, `Enter`, `Esc`, plus `Ctrl+S` Start, `Ctrl+X` Stop, `Ctrl+F` Fix, `Ctrl+V` VPN, `Ctrl+M` Mods, `Ctrl+T` Settings, `Ctrl+D` Diagnose, `Ctrl+C` Copy IP — listed in the status bar at all times)

### 🖥️ Main window
- **Dashboard:** live status ("SERVER IS LIVE" / "SERVER STOPPED"), server name + port, all connection lines for friends (this PC, LAN, every running VPN, Tailscale, public IP, router/UPnP state), a CGNAT warning badge, a Diagnose button and a Copy IP button
- **Fix Problems page:** every check is one row with `[OK]` / `[X]` / `[?]` and its own Fix button (key, launcher, BeamNG, port, Visual C++, firewall, VPNs, public IP/CGNAT, external reachability), plus Re-scan and one-click UPnP forwarding
- **VPN Manager page:** Radmin VPN / Hamachi / ZeroTier / Tailscale — installed / running / IP per row, Start and Download buttons, and Start-all-installed
- **Mods page:** two lists (enabled / disabled), Disable / Enable / Scan-for-suspicious-files buttons, sizes shown
- **Settings page:** server name, max players, port, "Lock my IP while hosting", server key setup and update check
- **Clean personal info** button: wipes key, webhook, logs, IP files, IP-lock (restores DHCP first) — run it before zipping the folder to share
- Activity log at the bottom shows everything the tool does and why; **EULA**, **key setup** and **CGNAT help** dialogs were carried over from the console edition

### 🧠 Under the hood
- Logic moved to `Server\HosterCore.ps1` (single source of truth); `Server\Play_BeamMP.ps1` is now only the window
- Background tasks run off the UI thread, so the window never freezes while it scans, checks or starts the server
- Closing the window stops the server cleanly (removes the key from `ServerConfig.toml`, restores DHCP when the IP lock is on) — same guarantees as before
- Launchers (`Start_Here.bat`, `Server\Play_BeamMP.bat`) launch the window with a hidden console; utility modes still work: `Start_Here.bat mods|fix|setup|help`

### ✅ Verified
- Scripts parse cleanly; the window boots and stays responsive; all logic functions (connection info, fix report, VPN scan, mod list) return correct results in the new background-task model
- CGNAT detection, VPN detection and the fix report behave exactly as in v0.5.4 (tested on the same real network)

## v0.5.4 — VPN support: VPN Manager, one-click start, CGNAT-friendly hosting

### 🖧 New VPN Manager (main menu option 7)
- Scans your PC for **Radmin VPN, Hamachi, ZeroTier and Tailscale** (install paths, Start-menu shortcuts, registry — no admin needed) and shows each as *Not installed / installed, not running / RUNNING with its IP*
- **One-click start:** press `R`/`H`/`Z`/`T` to launch an installed VPN, or press `A` to start all installed at once. The tool then watches for the VPN network to connect and reports the result (with its IP)
- **Not installed?** Pressing the key opens that VPN's **official download page** (radmin-vpn.com / vpn.net / zerotier.com/download / tailscale.com/download) — never a mirror
- If **two VPNs are running** at the same time, it lists each with its own IP and reminds you that friends must use the same VPN as the line you send

### 🔗 VPNs are now supported connection methods (works behind CGNAT)
- Radmin VPN / Hamachi / ZeroTier are no longer flagged as "break UDP" — the live screen shows a `Friends (VPN <name>): <IP> : port` line for every running VPN, and `CONNECTING.txt` documents them
- Copy-line priority: LAN > VPN > Tailscale
- The Help / Fix menu now reports each running VPN as `[OK]` with its IP (and notes when one is still connecting), instead of a red failure

### 🤖 Pre-start VPN help (only when CGNAT is detected)
- Before launching the server, if your ISP uses CGNAT the tool asks whether to start your installed-but-idle VPNs, or offers official download links when you have none installed

### 🩺 Problem Diagnosis key (live screen)
- Press **P** while hosting for a one-screen report: running VPNs (+IPs), LAN IP, Tailscale, public IP, CGNAT, UPnP state, listening port, firewall rules — so any problem is explained on the spot

### 🔒 VPN is a fallback, not the main event
- Port forwarding (Method B) is presented as the #1 hosting method; VPNs are only suggested when forwarding is impossible (CGNAT)
- The pre-start VPN help now asks **once per install** (marker file) instead of every launch — no nagging
- **Safety warnings added:** the VPN Manager screen and READMEs now warn that a P2P VPN puts players on a virtual LAN with your PC (file sharing, Remote Desktop reachable) — only invite people you trust; for random/unknown players use port forwarding or a VPS

## v0.5.3 — CGNAT detection upgrade + visible countdown (patch to the Restructured Edition)

### 🌐 CGNAT is now detected correctly (the "NOT reachable" mystery)
- The tool now reads your **router's own WAN IP** via UPnP and checks it too — many ISPs (like yours) give the router a `100.x.x.x` CGNAT address while the public IP looks normal
- The Help / Fix menu now shows **both** IPs and a clear explanation when CGNAT is found, with a new action (`8`) explaining the options (Tailscale / ask ISP for public IP / VPS)
- The live screen and CONNECTING.txt now say "CANNOT WORK - CGNAT" instead of a misleading forwarding hint
- Verified on a real CGNAT network (router WAN in the ISP CGNAT range, RFC 6598) → correctly detected

### ⏱️ Visible countdown in the main menu
- The 30-second auto-start now shows a live countdown (30, 29, 28...)

## v0.5.3 — External reachability scan + longer auto-start (patch to the Restructured Edition)

### 🌐 Help / Fix menu now scans your external reachability
- The Fix menu tests `publicIP:port` from the internet while your server is live and shows `[OK]` / `[X]` / `[..]`
- If it fails, a new action (`8`) walks you through the fixes in order: server running, router forward TCP+UDP, firewall ALLOW rules, VPNs, IP changes
- The test itself is now more reliable: 3 retries against ifconfig.co, plus a fallback service (hackertarget nmap)

### ⏱️ Main menu auto-start extended
- The main menu now waits **30 seconds** before auto-starting the server (was 8 seconds), giving you more time to pick an option

## v0.5.3 — EULA alignment (patch to the Restructured Edition)

### 📜 Built-in license agreement now matches the shipped LICENSE file
- The in-tool EULA screen now mirrors the full proprietary agreement from `LICENSE` (license grant, prohibited conduct, termination, disclaimer, liability, governing law, contact, general)
- Applies to all launcher versions, since `Play_BeamMP.ps1` is the single source of truth

## v0.5.3 — Firewall fix (patch to the Restructured Edition)

### 🛡️ Firewall checks & rule creation fixed
- **Duplicate-rule bug fixed:** the firewall previously re-created its rules on every run (and couldn't see existing ones without admin), piling up dozens of duplicate "K BNG M Hoster" rule sets. Now it removes old/duplicate sets first, then adds exactly one clean set (program + TCP + UDP + outbound)
- **Firewall detection no longer needs admin:** uses `netsh advfirewall` instead of `Get-NetFirewallRule`, so the Fix menu correctly shows the real firewall state
- **Readable result:** the elevated window now prints what it did ([OK]/[FAIL] per rule) and stays open until you press Enter — no more instant flash-close

## v0.5.3 — IP lock (patch to the Restructured Edition)

### 🔒 New: "Lock my IP while hosting" (main menu option 6)
- New main-menu option **"Lock my IP while hosting"** (currently ON/OFF):
  - When enabled, the launcher switches your main adapter to a **static IP** at server start and **restores DHCP automatically** when your session ends — like the AuthKey injection, nothing is left behind
  - This keeps your router's TCP+UDP forward working even when the DHCP lease renews (the usual cause of "last numbers of the IP change")
- One polite UAC prompt when locking and one when unlocking (same pattern as the firewall rule); if declined it logs and skips safely
- The tool only undoes what it changed itself: if your IP was already static before enabling the lock, it is left untouched (no backup = no restore)
- "Clean personal info" (option 5) restores DHCP first and removes the lock marker before sharing the folder
- Backup of the previous network state is kept in `Logs\staticip.undo.json`; if a restore fails, the next run retries automatically

## v0.5.3 — Restructured Edition (folder layout + connectivity + privacy)

### 📁 New folder structure (breaking change for manual users)
- The engine now lives in a dedicated `Server\` folder:
  - Top level (all you need to see): `Start_Here.bat`, `ServerConfig.toml`, `Resources/`, `README.md`, `README.txt`
  - `Server\` holds `BeamMP-Server.exe`, the launcher scripts, `Logs/`, your `.env` key and session files
- The server always runs using the **top-level** `ServerConfig.toml` and `Resources/` — edit them without touching `Server\`
- Old flat-layout files (`Play_BeamMP.ps1` at root, `K_BNG_M_H.exe`, root-level exe) removed; the launcher still auto-detects the legacy flat layout if you run it from an old copy

### 🔌 Connectivity fixes & automation
- **Port changed to the BeamMP standard `30814`** (was 30813) in `ServerConfig.toml` and launcher defaults
- **UPnP port forwarding (new):** the launcher tries to add TCP+UDP 30814 automatically on server start and when the port is busy (COM fast path with SSDP/SOAP fallback, 6-second cap, error 718 = already mapped handled)
- **CGNAT detection (new):** warns if your ISP puts you behind carrier-grade NAT (RFC 6598) where port forwarding can't work
- **VPN detection (new):** warns about Radmin VPN / Hamachi / ZeroTier / LogMeIn adapters that block BeamMP's UDP traffic
- **External reachability test (new):** the live screen shows whether your public IP:port is actually reachable from the internet
- **Auto-firewall (new):** opens Windows Firewall rules (program + explicit TCP/UDP port rules) on first start, with a polite one-time UAC prompt; a `Logs\fw.declined` marker prevents nagging if you decline
- **Busy-port auto-switch:** if port 30814 is taken, the launcher picks a free port, warns loudly, and tries to re-forward it via UPnP

### 🔐 Privacy & cleanup
- **"Clean personal info" menu option** wipes `.env`, `webhook.txt`, `Logs/`, `Backups/`, `Quarantine/`, `CONNECTING.txt` and `Server.log` (both locations) before sharing the folder
- The AuthKey is removed from `ServerConfig.toml` automatically when a session ends
- `Server.log` written to the top level is tucked into `Server\` on normal exit

### 🖥️ Launcher / UX
- New top-level menu: 1) Start server, 2) Settings, 3) Mods, 4) Fix & diagnose, 5) Clean personal info, 6) Exit
- Fix menu gained UPnP forwarding (option 7) alongside firewall, port, VPN, and key checks
- Live status screen and `CONNECTING.txt` now report UPnP status, reachability, CGNAT and VPN warnings
- `Start_Here.bat` supports utility commands: `mods`, `fix`, `help`

### 📄 Documentation
- `README.md` / `README.txt` updated: new folder layout table, `.env` auto-creation in `Server\`, utility commands, removal of obsolete `K_BNG_M_H.exe` references
- `ServerConfig.toml` documented port/UPnP note
- `.gitignore` extended: `Server.log`, `CONNECTING.txt` are runtime artifacts and are never committed

### ✅ Verified
- Launcher parses cleanly, `help` and `fix` menus run end-to-end from the new layout
- Fix menu reads the top-level config correctly and detects VPN / public IP / port status
- No personal data (IPs, keys, webhooks) remains in the shipped files
