===================================================================
                       K BNG M HOSTER
               Official BeamMP Hosting Tool - v0.3
         Join Discord: Innocent (discord.gg/2fxsJvKr4a)
===================================================================

[ 1. QUICK SETUP GUIDE ]
-------------------------------------------------------------------
1. Get your free BeamMP Server Key:
   --> https://keymaster.beammp.com

2. Open 'ServerConfig.toml' with Notepad:
   --> Find line: AuthKey = ""
   --> Replace with: AuthKey = "YOUR_KEY_HERE"

3. Launch 'K_BNG_M_Hoster.exe'!


[ 2. HOW IT WORKS ]
-------------------------------------------------------------------
The launcher:
  • Starts BeamMP-Server.exe (kept running in the background).
  • Waits until your BeamMP game session is open, then stops the
    server the moment the session ends.
  • Runs a security scan on Resources/Client and quarantines any
    suspicious executables inside mods.
  • Writes a log of everything to: Logs/launcher.log

NOTE: The server stays alive while the game launcher is running.
Close the game to stop the server automatically.


[ 3. HOW TO JOIN YOUR OWN SERVER (FOR THE HOST) ]
-------------------------------------------------------------------
1. Open BeamNG via the official BeamMP Launcher.
2. Go to: Direct Connect.
3. Enter IP : 127.0.0.1
4. Enter Port: 30814
5. Click Connect!


[ 4. ADDING MODS ]
-------------------------------------------------------------------
• Drop any vehicle or map '.zip' files directly into:
  --> Resources/Client/

• Suspicious files (*.exe, *.vbs, *.cmd, *.scr, *.pif) are moved to
  the Quarantine folder automatically on launch.


[ 5. OPTIONAL: DISCORD SERVER ANNOUNCEMENTS ]
-------------------------------------------------------------------
1. Create a webhook in your Discord channel:
   --> Channel Settings > Integrations > Webhooks
2. Copy 'webhook.example.txt' to 'webhook.txt' next to the .exe.
3. Paste your webhook URL into 'webhook.txt' and save.
   The launcher will post an [ONLINE] message when the server
   starts and an [OFFLINE] message when it stops.
   Leave webhook.txt empty / absent to disable this feature.


[ 6. TROUBLESHOOTING ]
-------------------------------------------------------------------
• "Invalid ZIP file" error:
  --> Ignore it! BeamNG automatically scans mods while downloading.

• Server closes instantly:
  --> Make sure your AuthKey is pasted correctly inside
      ServerConfig.toml without missing quotes.

• "SERVER IS LIVE!" shows but friends can't connect:
  --> Check that Windows Firewall allowed network access for the
      server, and double-check Port 30814 forwarding or Tailscale.

• Everything ran but you see no server in the list:
  --> BeamMP server registration requires a valid AuthKey and a
      stable internet connection.

===================================================================
Created by Kinan | Server Community: Innocent
===================================================================
