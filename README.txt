**Important — License & Usage:** By downloading, installing, or using this software you accept the Proprietary End‑User License Agreement in [LICENSE](./LICENSE). You may only run the unmodified software; edit the authorized Configuration Files (e.g., ServerConfig.toml) as described in the docs; and add user mod archives to Resources/Client/ for client mod syncing.
All other modifications, reverse‑engineering, redistribution, reuploads, resale, removal of attribution, or access to internal scripts is strictly forbidden. For legal notices: behindtheshadows95@gmail.com

```markdown
<div align="center">

```text
██   ██  ██████  ███    ██  ██████   ███    ███     ██   ██ ██████  ███████ ████████ ██�...
██  ██   ██   ██ ████   ██ ██        ████  ████     ██   ██ ██    ██ ██         ██    ██      ██   ██ 
█████    ██████  ██ ██  ██ ██   ███  ██ ████ ██     ███████ ██    ██ ███████    ██    ███�...
██  ██   ██   ██ ██  ██ ██ ██    ██  ██  ██  ██     ██   ██ ██    ██      ██    ██    ██      ██   ██ 
██   ██  ██████  ██   ████  ██████   ██      ██     ██   ██  ██████  ███████    ██    ██████��...

```

# 🚗 K BNG M HOSTER

### *(Kinan BeamNG Multiplayer Hoster)*

### ⚡ **The All-In-One Automated BeamMP Hosting & Joining Tool** ⚡

*Solely created and developed by **Kinan** (`@raed713`)*

---

---

## 📌 What is K BNG M Hoster?

**K BNG M Hoster** (*Kinan BeamNG Multiplayer Hoster*) is an all-in-one automation utility designed to make hosting, configuring, and joining BeamMP multiplayer servers effortless. Built entirely from scratch by Kinan, it handles process execution, automates background server management, and streamlines the direct connection workflow so you and your friends can drive together in seconds.

### ✨ Key Features

* **Zero-Stress Automation:** Handles server startup and process management automatically.
* **Flexible Hosting Options:** Full support for both **Tailscale (No Port Forwarding)** and **Public Port Forwarding**.
* **Seamless Mod Syncing:** Load custom vehicles and maps directly through client resources.
* **One-Click Launch:** Start the host via `K_BNG_M_Hoster.exe`.

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

### 2️⃣ Input Your Auth Key

1. Go to [BeamMP Keymaster](https://keymaster.beammp.com) and generate a new key.
2. In `ServerConfig.toml`, find **Line 7**:
```toml
AuthKey = "YOUR_KEY_HERE"

```


3. Replace `"YOUR_KEY_HERE"` with your generated key *(keep the quotation marks)*.
4. Save (`Ctrl + S`) and close the file.

---

## 🌐 Server Launch & Connection Methods

Choose **one** of the two hosting methods below depending on how you want players to connect:

---

### 🔹 METHOD A: Tailscale (Private / No Port Forwarding)

*Best for playing privately with a group of friends without altering router settings.*

#### 🛠️ Host Setup & Connection

1. Launch **Tailscale** on your PC.
2. Right‑click **`K_BNG_M_Hoster.exe`** and choose **"Run as administrator"** to start the host (recommended). 
3. Open **BeamNG.drive**.
4. Go to: `More...` ➔ `BeamMP` ➔ `Direct Connect`
5. Connect using:
* **IP Address:** `127.0.0.1`
* **Port:** `30814`



#### 👥 How Friends Join

1. Ensure all friends are connected to the Host’s network inside **Tailscale**.
2. Open BeamNG via the official **BeamMP Launcher**.
3. Go to: `More...` ➔ `BeamMP` ➔ `Direct Connect`
4. Connect using:
* **IP Address:** Host's Tailscale IP (`100.x.x.x`)
* **Port:** `30814`



---

### 🔹 METHOD B: Port Forwarding (Public Server List)

*Best for hosting publicly so anyone can find your server in the BeamMP Server Browser or join via your Public IP.*

#### 🛠️ Host Setup & Connection

1. Access your router settings and forward port **`30814` (UDP & TCP)** to your local IP address.
2. Open `ServerConfig.toml` and verify your settings:
```toml
Private = false
Port = 30814

```


3. Run **`K_BNG_M_Hoster.exe`** to launch the server. Right‑click the exe and choose **"Run as administrator"**
4. Open **BeamNG.drive** and connect via `Direct Connect` (`127.0.0.1:30814`).

#### 👥 How Friends Join

* **Option 1 (Server Browser):** Friends can search for your Server Name in the official BeamMP Server Browser.
* **Option 2 (Direct Connect):** Friends go to `More...` ➔ `BeamMP` ➔ `Direct Connect` and enter your **Public IP** and Port `30814`.

---

## 📦 Adding Custom Mods

To load custom vehicles, maps, or physics mods onto your server:

1. Open the project folder and navigate to:
```text
Resources/Client/

```


2. Drop your mod `.zip` files directly into this directory.
3. Restart the server by running `K_BNG_M_Hoster.exe` again to sync mods automatically with everyone who joins (right‑click → Run as administrator if needed).

---

## 🛠️ Troubleshooting & FAQ

> **"Invalid ZIP File" Pop-up?**
> Ignore this message! BeamNG scans files while BeamMP streams them in real time. Simply let the progress bar finish loading.

> **Server Window Closes Instantly?**
> Check your `ServerConfig.toml` file. This usually happens if the `AuthKey` was pasted incorrectly or left blank.

---

## 👑 Credits & Ownership

* **Sole Developer & Creator:** **Kinan** (`@raed713`)
*All original code, tools, scripts, and rights belong strictly and exclusively to Kinan.*
* **Official Discord:** [Innocent BeamMP Server Community](https://discord.gg/2FxsJvKr4a)


## Legal / License

This project is distributed under a proprietary EULA. By using this software you agree to the terms set in [LICENSE](./LICENSE).

Summary of permitted actions:
- Running the unmodified packaged software.
- Editing authorized configuration files (ServerConfig.toml) only as instructed.
- Adding mod archive files to Resources/Client/ to enable mod syncing.

Strictly prohibited:
- Modifying source code or scripts that are not explicitly authorized.
- Reverse‑engineering, decompilation, or extraction of internal logic.
- Reuploading, mirroring, forking, redistributing, or selling the Software.
- Removing, altering, or obscuring author attribution (Kinan / @raed713).
- Accessing Internal Scripts or proprietary files not explicitly permitted.

For permissions, DMCA, or legal inquiries: behindtheshadows95@gmail.com
