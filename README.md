<div align="center">

# K BNG M Hoster

### *(Kinan BeamNG Multiplayer Hoster)* — **v0.6.6** *(Update 6 - Fix 6)*

**The All-In-One Automated BeamMP Hosting & Joining Tool**

> 🔽 **Download the latest release:** [K BNG M Hoster v0.6.6-FIX ZIP](https://github.com/Kinan0713/K-BNG-M-Hoster/releases/latest)

> ⚠️ **Official download only:** Get K BNG M Hoster exclusively from the GitHub Releases page above. Please do **not** share, reupload, or forward this tool — everyone should download it from here so they always get the latest version.

*Solely created and developed by **Kinan** (`@raed713`)*

</div>

---

## 🚀 Quick Start (30 seconds)

1. **Extract** the ZIP to any folder.
2. **Double-click `Start_Here.bat`** — a window opens. That's it.
3. First time: accept the license, then paste your **BeamMP key** — your server starts automatically.
4. Send your friends the address shown on the window (press **Ctrl+C** or the **Copy IP** button).

That's everything. The tool handles the key, settings, ports and problems for you.

---

## 🧰 What it does

- **Starts and runs your BeamMP server** with one click — no config files, no console commands.
- **Home page** shows your live status and every address friends can use to join (LAN / VPN / internet).
- **Customisation** (Home page, or `Ctrl+T`): server name, max players, port, IP lock, server key, map, and Public/Private — all in plain language.
- **Fix Problems page** (`Ctrl+F`): checks key, port, firewall, VPNs, maps and more — each with its own one-click Fix. It only scans when you press "Re-scan everything" or "Fix all possible".
- **VPN Manager** (`Ctrl+V`): starts Radmin VPN / Hamachi / ZeroTier / Tailscale for you, or opens their download pages.
- **Mods page** (`Ctrl+M`): list, enable/disable and scan your mods for safety.
- **Built-in Guide** (`Ctrl+G`): the whole README, explained step by step inside the app.
- **Fullscreen**: press `F11` (or `Alt+Enter`) anytime; `Esc` to exit.
- Shortcuts are always shown at the bottom of the window: `Ctrl+H` Home, `Ctrl+S` Start, `Ctrl+X` Stop, `Ctrl+D` Diagnose, `Ctrl+C` Copy IP.

---

## 📡 How friends connect

Pick **one** method:

| Method | When to use it | What friends do |
|---|---|---|
| **Tailscale** | Easy, no router changes, private group | They join your Tailscale network, then Direct Connect to your Tailscale IP |
| **Port forwarding** (Public) | You want anyone to find your server in the BeamMP list | They search your server name in the BeamMP browser, or Direct Connect to your public IP |
| **P2P VPN** (Radmin / Hamachi / ZeroTier) | Your ISP blocks port forwarding (CGNAT) | They install the same VPN app, join your network, then Direct Connect to your VPN IP |

> Stuck? Open **Fix Problems** (`Ctrl+F`) or press **Diagnose** (`Ctrl+D`) — the tool checks everything for you and explains the fix.

---

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
Your `AuthKey` is probably missing or wrong. The tool walks you through it on first run — or open the key setup from Fix Problems.

**"Friends can't connect."**
Usually one of three things: your ISP blocks port forwarding (CGNAT) — use a VPN instead; only TCP is forwarded (BeamMP needs TCP **and** UDP); or Windows Firewall blocks the server. **Fix Problems** checks all of these.

**"Is it safe?"**

---

## 📄 More

- **Credits:** early co-development by **Ali Alldoboni** (`@alialldoboni`) for v0.2–v0.5.2
- **Discord:** [Innocent BeamMP Server Community](https://discord.gg/2FxsJvKr4a)
- **License:** proprietary EULA — see `LICENSE`. By using this software you agree to its terms.

*All original code, tools, scripts, and rights belong strictly and exclusively to Kinan.*