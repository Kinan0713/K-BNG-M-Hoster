<div align="center">

# K BNG M Hoster

### *(Kinan BeamNG Multiplayer Hoster)* — **v0.7.2.2** *(Structural Edgeless Overhaul & Material Elevation Pass)*

**The All-In-One Automated BeamMP Hosting & Joining Tool**

> 🔽 **Download the latest release:** [K BNG M Hoster v0.7.2.2 ZIP](https://github.com/Kinan0713/K-BNG-M-Hoster/releases/latest)

> ⚠️ **Official download only:** Get K BNG M Hoster exclusively from the GitHub Releases page above. Please do **not** share, reupload, or forward this tool — everyone should download it from here so they always get the latest version.

*Created and developed by **Kinan** (`@kinan_sx240`) · UI/UX Overhaul by **`@bomberrie`***

</div>

---

## 🚀 Quick Start (30 seconds)

1. **Extract** the ZIP to any folder.
2. **Double-click `Start_Here.bat`** — a window opens. That's it.
3. First time: accept the license, then paste your **BeamMP key** — your server starts automatically.
4. Send your friends the address shown on the window (press **Ctrl+C** or the **Copy IP** button).

That's everything. The tool handles the key, settings, ports and problems for you.

---

## 🧭 What it does

- **Starts and runs your BeamMP server** with one click — no config files, no console commands.
- **Dashboard (`Ctrl+H`)** features a 4-Pill Telemetry KPI Strip (Server State, Port & Protocol, Visibility Mode, Network Reachability), live AuthKey readiness banner, Recommended Friend Route badge, and a 5-row Connection Matrix with one-click Copy buttons (Loopback, LAN, FRP Tunnel, VPN/Playit.gg, and WAN).
- **Server Settings (`Ctrl+T`)**: server name, max players, max cars, port, IP lock, server key, searchable map picker, Public/Private visibility, and saved Presets — plus a collapsible **Advanced Server Settings** accordion mapping custom game ports, network bind IP (`::`/`0.0.0.0`), resource folders, and update reminders.
- **Streamer Privacy Mode**: one-click persistent header toggle and dedicated settings switch that actively redacts Public WAN IPs, AuthKeys, and local Windows user paths (`***`) across the Dashboard, Network tab, and Activity Console during live broadcasts.
- **Scan & Fix (`Ctrl+F`)**: checks key, port, firewall, VPNs, maps, CGNAT, and external reachability — each with its own one-click Fix, plus **Fix All Possible**.
- **Network & Tunnels (`Ctrl+V`)**: starts Radmin VPN / Hamachi / ZeroTier / Tailscale / Playit.gg for you, or hosts through a bundled **FRP tunnel** with zero router port forwarding.
- **Mod Manager (`Ctrl+M`)**: drag & drop `.zip` mods, multi-select enable/disable, and scan mods for safety.
- **Cloud Transfer (`Ctrl+U`)**: export server mods into cloud-sized chunks (5GB–25GB), install downloaded client mods, and selectively delete client mods.
- **Built-in Guide (`Ctrl+G`)**: step-by-step interactive walkthrough with structured typography, callout badges, and quick-jump navigation buttons.
- **Fullscreen**: press `F11` (or `Alt+Enter`) anytime; `Esc` to exit.
- Shortcuts are always shown at the bottom of the window: `Ctrl+H` Dashboard, `Ctrl+S` Start, `Ctrl+X` Stop, `Ctrl+D` Diagnose, `Ctrl+C` Copy IP.

---

## 📡 How friends connect

Pick **one** method:

| Method | When to use it | What friends do |
|---|---|---|
| **FRP tunnel** | Anywhere, even CGNAT — needs a shared frps server | They Direct Connect to the FRP server address shown on your Stats page |
| **Tailscale** | Easy, no router changes, private group | They join your Tailscale network, then Direct Connect to your Tailscale IP |
| **Port forwarding** (Public) | You want anyone to find your server in the BeamMP list | They search your server name in the BeamMP browser, or Direct Connect to your public IP |
| **P2P VPN** (Radmin / Hamachi / ZeroTier) | Your ISP blocks port forwarding (CGNAT) | They install the same VPN app, join your network, then Direct Connect to your VPN IP |

> Stuck? Open **Scan & Fix** (`Ctrl+F`) or press **Diagnose** (`Ctrl+D`) — the tool checks everything for you and explains the fix.

---

## 🛠️ Requirements

| Requirement | What it's for | Download |
|---|---|---|
| **BeamMP Keymaster** | Your free server key | [keymaster.beammp.com](https://keymaster.beammp.com) |
| **BeamMP Client** | Play multiplayer in BeamNG | [beammp.com](https://beammp.com) |
| **Tailscale** (optional) | Private hosting without router setup | [tailscale.com](https://tailscale.com) |
| **Radmin VPN / Hamachi / ZeroTier** (optional) | VPN hosting when port forwarding can't work | [radmin-vpn.com](https://www.radmin-vpn.com/) · [vpn.net](https://www.vpn.net/) · [zerotier.com](https://www.zerotier.com/download/) |

---

## ❓ Common questions

**"My server closes instantly."**
Your key is probably missing or wrong. The tool walks you through it on first run — or open the key setup from Scan & Fix.

**"Friends can't connect."**
Usually one of three things: your ISP blocks port forwarding (CGNAT) — use a VPN instead; only TCP is forwarded (BeamMP needs TCP **and** UDP); or Windows Firewall blocks the server. **Scan & Fix** checks all of these.

**"Is it safe?"**
Yes. No data collection, no phoning home. Your key is used only while hosting and is wiped when you stop. Mods are scanned for executables before being served.

---

## 📜 License

This software is distributed under a proprietary EULA. By using this software you agree to its terms.

**Permitted actions:**
- Running the unmodified packaged software
- Editing the server settings through the app's Settings tab
- Adding your own mod files for server-side mod syncing

**Strictly prohibited:**
- Modifying, patching, or reverse-engineering the internal scripts and logic
- Decompiling or attempting to derive the source code of the software
- Reuploading, mirroring, forking, redistributing, or selling the software
- Sharing the ZIP or the tool itself outside the official GitHub Releases page
- Using the software for paid hosting or commercial services without written permission
- Removing, altering, or obscuring author attribution (Kinan / @kinan_sx240)

**For permissions, DMCA, or legal inquiries:** open an issue on GitHub: https://github.com/Kinan0713/K-BNG-M-Hoster/issues

---

## 📄 Credits & Contributions

- **Sole Developer & Creator:** **Kinan** (`@kinan_sx240`)
- **`@bomberrie`** — v0.7.1 Complete Command Center UI/UX Redesign
- **Ali Alldoboni** (`@alialldoboni`) — early co-development for v0.2–v0.5.2
- **Discord:** [Innocent BeamMP Server Community](https://discord.gg/2FxsJvKr4a)

*All original code, tools, scripts, and rights belong strictly and exclusively to the original author.*
