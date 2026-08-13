# Changelog

All notable changes to **K BNG M Hoster** are documented here.

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
- **CGNAT detection (new):** warns if your ISP puts you behind carrier-grade NAT (100.64.0.0/10) where port forwarding can't work
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