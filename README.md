<div align="center">

```text
██   ██  ██████  ███    ██  ██████   ███    ███     ██   ██ ██████  ███████ ████████ ███████
██  ██   ██   ██ ████   ██ ██        ████  ████     ██   ██ ██    ██ ██         ██    ██     
█████    ██████  ██ ██  ██ ██   ███  ██ ████ ██     ███████ ██    ██ ███████    ██    █████  
██  ██   ██   ██ ██  ██ ██ ██    ██  ██  ██  ██     ██   ██ ██    ██      ██    ██    ██     
██   ██  ██████  ██   ████  ██████   ██      ██     ██   ██  ██████  ███████    ██    ███████
```

</div>

# 🚗 <span style="color: #FF6B6B">K</span> <span style="color: #4ECDC4">BNG</span> <span style="color: #45B7D1">M</span> <span style="color: #FFA07A">H</span><span style="color: #98D8C8">o</span><span style="color: #F7DC6F">s</span><span style="color: #BB8FCE">t</span><span style="color: #85C1E2">e</span><span style="color: #F8B88B">r</span> <span style="display: inline-block; animation: shatter 0.6s ease-out forwards;">✨</span>

### *(Kinan BeamNG Multiplayer Hoster)* — **v0.5.3**

**The All-In-One Automated BeamMP Hosting & Joining Tool**

*Solely created and developed by **Kinan** (`@raed713`)*

---

## 📌 What is K BNG M Hoster?

**K BNG M Hoster** is an all-in-one automation utility designed to make hosting, configuring, and joining BeamMP multiplayer servers effortless. Built entirely from scratch, it handles process execution, automates background server management, and streamlines the direct connection workflow so you and your friends can drive together in seconds.

### ✨ Key Features

- **Zero-Stress Automation:** Handles server startup and process management automatically.
- **Flexible Hosting Options:** Full support for both **Tailscale (No Port Forwarding)** and **Public Port Forwarding**.
- **Seamless Mod Syncing:** Load custom vehicles and maps directly through client resources.
- **One-Click Launch:** Start the host via `Start_Here.bat`.

---

## ⚡ Setup Requirements

Before getting started, make sure you have the following downloads ready:

| Requirement | Purpose | Download Link |
|---|---|---|
| **BeamMP Keymaster** | Get your free server authentication key | [Keymaster Portal](https://keymaster.beammp.com) |
| **BeamMP Client** | Official multiplayer client for BeamNG.drive | [Download Client](https://beammp.com) |
| **Tailscale** *(Method A)* | Secure direct connection without changing router settings | [Download Tailscale](https://tailscale.com) |

---

## ⚙️ Step-by-Step Configuration Guide

### 1️⃣ Extract & Open

1. Download **K BNG M Hoster** and extract the ZIP folder to your preferred location.

### 2️⃣ Input Your Auth Key

1. Go to [BeamMP Keymaster](https://keymaster.beammp.com) and generate a new key.

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
   - **Port:** `30814`

#### 👥 How Friends Join

1. Ensure all friends are connected to the Host's network inside **Tailscale**.
2. Open BeamNG via the official **BeamMP Launcher**.
3. Go to: `More...` ➔ `BeamMP` ➔ `Direct Connect`
4. Connect using:
   - **IP Address:** Host's Tailscale IP (`100.x.x.x`)
   - **Port:** `30814`

---

### 🔹 METHOD B: Port Forwarding (Public Server List)

*Best for hosting publicly so anyone can find your server in the BeamMP Server Browser or join via your Public IP.*

#### 🛠️ Host Setup & Connection

1. Access your router settings and forward port **`30814` (UDP & TCP)** to your local IP address.
   ```toml
   Private = false
   Port = 30814
   ```
3. Double-click **`Start_Here.bat`** to launch the server.
4. Open **BeamNG.drive** and connect via `Direct Connect` (`127.0.0.1:30814`).

#### 👥 How Friends Join

- **Option 1 (Server Browser):** Friends can search for your Server Name in the official BeamMP Server Browser.
- **Option 2 (Direct Connect):** Friends go to `More...` ➔ `BeamMP` ➔ `Direct Connect` and enter your **Public IP** and Port `30814`.

---

## 📦 Adding Custom Mods

To load custom vehicles, maps, or physics mods onto your server:

1. Open the project folder and navigate to:
   ```
   ```
2. Drop your mod `.zip` files directly into this directory.
3. Restart the server by running `Start_Here.bat` again to sync mods automatically with everyone who joins.

---

## 🛠️ Troubleshooting & FAQ

**Q: "Invalid ZIP File" Pop-up?**  
A: Ignore this message! BeamNG scans files while BeamMP streams them in real time. Simply let the progress bar finish loading.

**Q: Server Window Closes Instantly?**  

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
- Removing, altering, or obscuring author attribution (Kinan / @raed713)
- Accessing internal scripts or proprietary files not explicitly permitted


<style>
@keyframes shatter {
  0% {
    opacity: 1;
    transform: scale(1);
  }
  100% {
    opacity: 0;
    transform: scale(0) rotate(360deg);
  }
}
</style>
