# 🚗 K BNG M HOSTER

### *(Kinan BeamNG Multiplayer Hoster)*

### ⚡ **The All-In-One Automated BeamMP Hosting & Joining Tool** ⚡

*Solely created and developed by **Kinan** (`@raed713`)*

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
* **Update Checker (v0.4):** Tells you when a newer official BeamMP-Server is available (checked once per day, never blocks startup).
* **Simplest Setup Ever (v0.5):** First run walks you through everything — you only paste your key once. The tool writes all files, auto-picks a free port, and has a one-click **Help / Fix Problems** menu.

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

### 2️⃣ Input Your Auth Key *(Automatic — Recommended)*


1. Go to [BeamMP Keymaster](https://keymaster.beammp.com) and generate a new key.

>

### 3️⃣ Note on Ports


### 4️⃣ Utility Commands *(v0.4)*

| Command | What it does |
| --- | --- |
| `Start_Here.bat` | **Just double-click this.** Everything else is automatic |
| `Start_Here.bat mods` | Open the Mod Manager (list, disable, enable, scan mods) |
| `Start_Here.bat fix` | Open the Help / Fix Problems menu |
| `Start_Here.bat help` | Show usage |


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

#### 👥 How Friends Join

1. Ensure all friends are connected to the Host’s network inside **Tailscale**.
2. Open BeamNG via the official **BeamMP Launcher**.
3. Go to: `More...` ➔ `BeamMP` ➔ `Direct Connect`
4. Connect using:
* **IP Address:** Host's Tailscale IP (`100.x.x.x`)

---

### 🔹 METHOD B: Port Forwarding (Public Server List)

*Best for hosting publicly so anyone can find your server in the BeamMP Server Browser or join via your Public IP.*

#### 🛠️ Host Setup & Connection

```toml
Private = false
Port = 30814
```
3. Double-click **`Start_Here.bat`** to launch the server.
4. Open **BeamNG.drive** and connect via `Direct Connect` (`127.0.0.1:30814`).

#### 👥 How Friends Join

* **Option 1 (Server Browser):** Friends can search for your Server Name in the official BeamMP Server Browser.

---

## 📦 Adding Custom Mods

To load custom vehicles, maps, or physics mods onto your server:

1. Open the project folder and navigate to:
```text
```
2. Drop your mod `.zip` files directly into this directory.
3. Restart the server by running `Start_Here.bat` again to sync mods automatically with everyone who joins.

>

---

## 🔌 Optional: Discord Server Announcements

1. Create a webhook in your Discord channel (`Channel Settings > Integrations > Webhooks`).
4. The launcher posts an **`[ONLINE]`** embed when the server starts, an **`[OFFLINE]`** embed when it stops, and **join/leave** embeds when players enter or leave the server *(v0.4)*.

---

## 🛠️ Troubleshooting & FAQ

> **"Invalid ZIP File" Pop-up?**
> Ignore this message! BeamNG scans files while BeamMP streams them in real time. Simply let the progress bar finish loading.

> **Server Window Closes Instantly?**

> **Tool says the server failed to start?**

---

## 👑 Credits & Ownership

* **Sole Developer & Creator:** **Kinan** (`@raed713`)
*All original code, tools, scripts, and rights belong strictly and exclusively to Kinan.*
* **Official Discord:** [Innocent BeamMP Server Community](https://discord.gg/2FxsJvKr4a)
