## v0.7.2.2 - Update 12: Structural Edgeless Design Overhaul & Tactile Material Elevation

- **Edgeless Design & Destruction of Legacy Boxes (`apple-design` & `emil-design-eng`):**
  - **Outer Bounding Box Eradication**: Completely removed `BorderThickness` and outer card container borders from both the Hero Status Card (`$script:StatusCard`) and the Direct Connect Endpoints Matrix (`$script:ConnContent`), allowing data to sit cleanly on the canvas (`#09090b`).
  - **Unsegregated KPI Telemetry Strip**: Eliminated individual bordered rectangle boxes from the 4 KPI metric chips ("SERVER NAME", "PORT (UDP/TCP)", "VISIBILITY", "GATEWAY STATUS"); layout is now structured purely through Margin, Padding, and high-contrast typography hierarchy.
  - **Hairline Internal Row Dividers**: Enforced that the only lines rendered across the entire Dashboard are ultra-thin (1px), low-opacity (`rgba(255, 255, 255, 0.05)`) internal horizontal row dividers between matrix endpoints.

- **Sidebar Definition & Tactile Button Borders:**
  - **Subtle Surface Lift & Defined Hitboxes**: Re-applied a subtle `#111115` surface elevation with an ultra-thin 1px border (`rgba(255, 255, 255, 0.08)`) and 6px rounded corners across all inactive sidebar navigation items ("Server Settings", "Mod Manager", "Network & Tunnels", "Cloud Transfer", "Scan & Fix", "More Tools"), establishing unambiguous clickable hitboxes without reverting to legacy harsh UI boxes.
  - **Active State Harmony & Glowing Accent**: Harmonized the active "Dashboard" button with a warm accent fill (`rgba(255, 115, 29, 0.14)`), a luminous glowing accent border (`rgba(255, 115, 29, 0.38)`), and floating warm amber shortcut indicators (`^H`).
  - **Consistent Utility Buttons**: Aligned the bottom-left utility actions ("Open Folder", "Guide (^G)") with identical 6px rounded pill geometry and subtle 1px translucent borders.

- **Layered Material Elevation (Tactile Top Buttons):**
  - **Multi-Layered Drop Shadows**: Implemented dual-layer GDI+ drop shadows (soft ambient shadow `rgba(0, 0, 0, 0.16)` + crisp contact shadow `rgba(0, 0, 0, 0.30)`) on top action buttons ("Copy Best IP", "Copy Invite", "Diagnose", "Refresh") and matrix action buttons, physically lifting them off the `#09090b` canvas.
  - **Elevated `#1c1c24` Surface & Top Specular Catch-Light**: Applied subtle translucent borders (`rgba(255, 255, 255, 0.10)`) and a 1px top specular catch-light line across button upper edges.
  - **Tactile Depression Feedback**: Integrated dynamic 1px depression shifts and shadow collapse on click (`$state -eq 'down'`).

- **Semantic Callout Rebuild ("TIP" Box):**
  - **Border Elimination & Solid `#291f00` Fill**: Stripped the stark yellow outline completely in favor of a solid `#291f00` (dark amber) background fill.
  - **Rounded Corner Geometry**: Increased corner radius to 10px with an ambient amber circular icon badge and softened warm amber typography (`#fed7aa`).

## v0.7.2.1 - Update 11: Apple-Design UI Modernization, Runspace Latency Optimization & Dynamic Data-Binding Polish

- **Sidebar Navigation Craft & Tactile Elevation:**
  - **Modern Active Surface Fill**: Eliminated the legacy, harsh thin orange bounding box on the active navigation button; replaced with a subtle semi-transparent accent surface fill (`rgba(255, 115, 29, 0.12)`) and a sharp, solid left-edge indicator bar (`#FF731D`) adhering to Emil Kowalski and Apple Human Interface Guidelines.
  - **Organically Softened Keyboard Shortcuts**: Stripped the rigid rectangular badge backgrounds behind shortcut indicators (`^H`, `^T`, `^M`, `^V`, `^U`, `^F`); shortcuts now float seamlessly with quiet zinc typography (`#696976`) that gracefully brightens upon hover and active states without visual clutter.

- **Tactile Button & Edgeless Structural Hierarchy:**
  - **Top Action Row Tactile Overhaul**: Redesigned "Copy Best IP", "Copy Invite", "Diagnose", and "Refresh" with soft-elevated `#1c1c24` surfaces, subtle `rgba(255, 255, 255, 0.08)` translucent perimeter borders, and smooth zero-jitter hover state transitions.
  - **Edgeless Telemetry KPI Strip**: Stripped high-contrast solid borders and top specular lines from the 4 KPI metric chips ("SERVER NAME", "PORT (UDP/TCP)", "VISIBILITY", "GATEWAY STATUS") in favor of edgeless dark zinc surfaces (`#111116`) with ultra-thin, low-opacity dividers (`rgba(255, 255, 255, 0.05)`).
  - **Edgeless Direct Connect Matrix**: Eradicated harsh outer bounding strokes around the endpoint routing table, achieving spatial balance through unified surface contrast and hairline internal row dividers (`rgba(255, 255, 255, 0.05)`).
  - **Semantic Callout Polish**: Softened the warning/info box below the matrix by replacing its stark outline with a low-opacity amber surface fill (`rgba(245, 158, 11, 0.08)`), 8px rounded corners, and a borderless ambient amber indicator glyph.
  - **Streamer Toggle Precision Shift**: Modernized the top-right "STREAMER: OFF / ON" toggle with distinct pill geometry, smooth tactile switch dot, and vibrant emerald shield color shifting upon activation.

- **Asynchronous Runspace & Gateway Polling Optimization:**
  - **Instant SSDP Discovery**: Optimized `Get-UpnpControlUrl` to terminate early upon receiving the primary Internet Gateway Device location (reducing discovery wait latency from 6,000ms to <1,800ms) with a 10-minute memory cache, preventing SSDP broadcast floods.
  - **Multi-Endpoint Public IP Resolver**: Upgraded `Get-PublicIpCached` with multi-endpoint fallback resolution (`api.ipify.org`, `icanhazip.com`, `ifconfig.me`) and a tight 3s timeout with regex IPv4 validation, eliminating cold-start WAN polling stalls.
  - **Zero UI-Thread Blocking on Copy**: Removed synchronous `Get-ConnectionInfo` execution from "Copy Best IP" and "Copy Invite" button handlers, reading exclusively from the asynchronous state cache for instantaneous, stutter-free clipboard actions.

- **Data-Binding & WinForms Rendering Bug Eradication:**
  - **Immediate Invalidation on Text Changes**: Enhanced `Set-CtrlText` to invoke deterministic `.Invalidate()` on both target controls and parent containers upon any text or color update, eliminating double-buffered rendering lag where dynamic endpoint changes required manual hover or window resizing.
  - **Port State Synchronization**: Fixed state race condition where background connection probes could latch stale port values; `$script:State.Port` now enforces authoritative bidirectional synchronization across the KPI metric chip, matrix rows, and clipboard buffers.

## v0.7.2.0 - Update 10: Advanced Settings Expansion & Streamer Mode Integration

- **Dashboard Modernization & Command Center Craft:**
  - **Tactile Button Overhaul**: Eradicated legacy heavy grey backgrounds across the top action row and matrix rows; implemented soft-elevated `#1c1c24` surfaces with subtle `rgba(255,255,255,0.08)` translucent borders and zero-jitter hover/press luminance states.
  - **KPI Telemetry Breathing Room**: Expanded the 4-pill telemetry strip to 52px height with 10px inter-chip margins; established strict typographic hierarchy using muted Zinc-400 captions (`#888894`) while reserving high-contrast white and semantic colors purely for live telemetry values.
  - **Direct Connect Matrix Visual Rhythm**: Standardized the 6-row routing table with a uniform 184px title column, strict monospaced Cascadia Mono status alignment, and standardized 90x26px right-aligned action buttons.
  - **Modern Semantic Callout Banner**: Redesigned the harsh yellow TIP banner into a subtle, low-opacity warm amber surface fill (`#1c160c`) with soft 6px rounded corners, inline `[i]` badge glyph, and warm zinc-amber typography.
  - **Precision Streamer Pill Toggle**: Evolved the top-right header button into a sleek pill-shaped toggle switch with tactile thumb indicator and luminous protective emerald shield styling when active.

- **Streamer Privacy Mode:**
  - One-click persistent header toggle (`$titleBar`) and dedicated card in Settings with glowing active indicator and tactile toggle feedback.
  - Intercepts and masks sensitive data in real time: Public WAN IPs (`***.***.***.***`), Keymaster AuthKeys (`********************************`), and Windows local user file paths (`C:\Users\***`).
  - Active across the Dashboard Direct Connect Matrix, Network VPN rows, and the Activity Console log stream with pre-render redaction.
  - Clipboard copy protection prevents accidental pasting of sensitive endpoints during live broadcasts and recording sessions.

- **Advanced Server Settings (Collapsible Accordion):**
  - Smooth collapsible accordion container in Server Settings keeping the primary cards uncluttered and focused.
  - Complete mapping of previously unexposed `ServerConfig.toml` variables:
    - Custom Game Listen Port (`Port`, range 1024-65535).
    - Network Bind IP (`IP`, default `::` dual-stack IPv6/IPv4 or `0.0.0.0`).
    - Mod Resource Folder (`ResourceFolder`, default `Resources`).
    - Hide Server Update Prompts (`ImScaredOfUpdates = true/false`).
    - Update Reminder Frequency (`UpdateReminderTime`, default `30s`).

- **Section-Aware TOML Serializer & Fallback Resilience:**
  - Enhanced `Set-ServerConfig` intelligently routes keys to `[General]`, `[Misc]`, and `[FRP]` tables while preserving existing comments, indentation, and ordering.
  - Fallback defaults for all fields prevent null-reference exceptions and crash-to-desktop scenarios on incomplete or legacy configurations.

- **Activity Console Streamer Hook Fix:**
  - Resolved an unassigned variable binding in `Add-LogBatch` where `$cleanLine` was not populated on normal log streams, restoring instant visibility for all server events, status updates, and diagnostic messages with correct timestamps and semantic colors.

- **Dashboard Telemetry & Action Bar Alignment Fix:**
  - Resolved `PORT (TCP+U...` truncation on standard and high-DPI displays by rebalancing KPI grid column styles (23% / 20% / 26% / 31%), modernizing the caption to `PORT (UDP/TCP)`, and optimizing value font sizing to prevent label ellipsis at all window sizes.
  - Aligned the top action buttons (`Copy Best IP`, `Copy Invite`, `Diagnose`, `Refresh`) with uniform 28px height, 4px margins, and expanded card top/bottom padding (14px) eliminating vertical clipping and button misalignment.

## v0.7.1.1 - Update 9: Validation & input fixes

- **No more false-positive validation errors:** the server key check no longer rejects
  custom or unusual key strings. Any non-empty key text is accepted (only line breaks /
  control characters are refused because they would corrupt the config file). "0" and a
  blank key for private servers stay valid.
- **Graceful settings save:** the server name, MaxPlayers/MaxCars, description and tags
  now sanitize edge-case input (quotes, line breaks, overlong names, non-numeric text)
  instead of aborting the whole save with an error. Non-numeric player/car values fall
  back to the existing config; out-of-range values are capped safely.
- **FRP fields never block the save:** pasted URLs / host:port strings are cleaned into a
  valid server address, and a bad or empty port falls back to the default 7000.
- **Config writer fallbacks:** ServerConfig.toml writes are wrapped so unexpected input
  formats degrade to safe, valid TOML instead of blocking server execution, and a failed
  write keeps the previous config.

## v0.7.1 - UI Overhaul & Performance (by @bomberrie)

- Redesigned the dashboard and command center with a dark theme, sidebar navigation, and cleaner direct connect cards.
- Optimized window rendering, scrolling, and page switching to reduce lag.

## v0.7.1.0 - Update 8: Public/Private toggle fix & AuthKey "0" support

- **Public/Private toggle fixed:** clicking Private or Public now updates the interface
  instantly and stores the choice in ServerConfig.toml (`Private = true/false`). The
  toggle handlers no longer re-read the config file, so the selection can never bounce
  back or revert on its own.
- **Settings now save to ServerConfig.toml:** the new Save-AuthConfig pipeline writes the
  server key and the visibility state to disk on every Save Key / Apply visibility /
  Save settings / Start Server click - previously key entries could fail to persist.
- **AuthKey "0" support:** the key field accepts "0" (and blank for private servers) as a
  valid value with no red error or clearing - private servers use it to skip Keymaster
  authentication.
- **Boot-loop fix:** the startup key validation now breaks out immediately when
  Private = true or the AuthKey is "0", so a keyless private server launches cleanly.
- **Session end keeps your settings:** a server session no longer wipes the saved
  AuthKey from ServerConfig.toml.

## v0.7.0.2 - Update 7, Fix 2: first-run license/internet check no longer locks out new users

- **First-run license fix:** brand-new users who start the tool without internet (or
  whose firewall blocks the license check) were shown a hard error and the app closed
  before they could ever accept the license. The startup gate now always presents the
  interactive license dialog on the very first run - even when the remote license
  version cannot be fetched - records the acceptance locally, and lets the user in.
- **Non-blocking internet check:** the reachability probe already ran on a background
  thread with a short timeout and a try/catch fallback; the gate logic now wraps the
  whole version decision in try/catch so a transient offline state, a firewall block or
  a DNS hiccup can never abort initialization or crash the launcher.
- **Self-update version matching:** the update checker now accepts four-part version
  tags (e.g. 0.7.0.2) so hotfix releases are detected and offered correctly.

## v0.7.0 - Update 7: Transfer tab, FRP tunneling & GitHub-verified license

### 🚀 Added (New features)

- **New "Transfer" tab** (toolbar button or Ctrl+U) for automated mod packaging:
  - **Scan Server Mods** - matches the server's mod list (Resources/Client) against the mods actually cached on the host and shows the total count and combined size.
  - **Smart Client Mod Export** - exports the hashed, cached mod copies from the host's own BeamMP launcher data (AppData), never the raw server files, so recipients get exactly what BeamMP verifies.
  - **Dynamic folder size-chunking** - "Max folder size" selector (5GB / 10GB / 15GB / 20GB / 25GB); the export automatically splits into numbered parts (Export\Part_1, Part_2, ...) whenever a file would push a folder past the limit - tuned for free cloud tiers.
  - **Select Export Destination** - a folder picker that saves the chosen path globally and shows it on the page ("Export Path: ..."); "Export Server Mods" refuses to run until a destination is chosen.
  - **Cloud upload shortcuts** - "Upload to Google Drive (15GB)" and "Upload to Mega.io (20GB Free)" open the right cloud page in the browser for the exported parts.
  - **Install Downloaded Mods** - picks a folder and moves only its .zip files into the BeamMP client mods folder; every other file type is ignored.
  - **Selective Mod Deletion** - a checklist of installed client mods (name + size) with Refresh, Select All / Deselect All and "Delete Selected Mods": only ticked files are removed after a confirmation, so mods belonging to other servers are never wiped.
- **GitHub-verified Proprietary EULA lockout** - the launcher checks the official repository on startup for the latest required license version (background thread, short timeout, try/catch - the UI never freezes). If the user has not accepted yet, or the remote version is newer, every tab, button and shortcut is locked and a modal dialog presents the full Proprietary License Agreement in a scrollable viewer. "Accept & Continue" stays disabled until the "I have read and agree..." checkbox is ticked; "Decline / Exit" closes the app immediately. The accepted version is recorded locally, so the dialog only returns when the agreement itself changes.
- **Offline-friendly licensing** - no internet? Users with a previously accepted license keep full access; brand-new users are told an internet connection is required for first-time verification.
- **FRP tunnel (Fast Reverse Proxy)** - host through a remote frps server with zero router port forwarding (works behind CGNAT), enabled from Settings with a masked token. The official frpc client ships inside the app and self-extracts + verifies itself on first use.
- **Network tab** - VPN Manager, FRP tunnel and CGNAT help consolidated into one place; Playit.gg is now a fully supported VPN (detection, address display, start/stop/copy).

### ðŸ”„ Changed (Modifications to existing features)

- **Toolbar slimmed down** - 12 buttons became 8 (Home, Start, Stop, Settings, Mods, Fix, Network, More); Guide and Extra moved into the "More" menu alongside Support, Open Folder and Clean Info.
- **Every page rebuilt** as a scrollable stack of rounded cards with a sticky header - Settings groups everything into clearly labeled cards with the Save button always visible at the top.
- **Truly responsive layout** - hand-tuned pixel math replaced by TableLayoutPanels, Dock and Anchor; cards, inputs, button bars and notes stretch and reflow at any window size.
- **Cleaner page headers** - the second hint line became a tooltip on the page title; the Mods drop-zip hint moved into the bottom tip line.
- **Fix scan banner** - scan results now open with a prominent "X of N checks OK - Y need attention" summary.
- **Tailscale is a normal VPN** - it has its own row in VPN tools (start/stop/copy/download) instead of a special one-off button.
- **Playit.gg support** - detection, tunnel address display and dedicated stop/copy handling.
- **Upgrade-safe config** - existing ServerConfig.toml files automatically gain an [FRP] section with sane defaults.
- **Full proprietary license text** - the startup agreement now shows the complete Proprietary License Agreement instead of the old short summary.

### ðŸ› ï¸ Fixed (Bug fixes or logic corrections)

- Settings saves that started back-to-back silently dropped the second one - background actions are now queued and a save runs as one atomic action.
- Boolean settings saved as bare values crashed the whole save invisibly - values are now quoted and normalized into valid TOML; toggles persist the moment they are flipped and the page re-loads saved values on every visit.
- VPN row Start/Stop/Download buttons all fired the last row's action (PowerShell handlers do not capture loop variables) - values are now baked into each handler, verified by automated click tests.
- Stopping Playit.gg now goes through the core stop routine.
- WinForms style-collection Add() calls leaked return values into page builders and polluted card lists - suppressed.
- "Start Server" toolbar text clipped - buttons now have explicit widths.
- Header hint lines pushed action buttons off-screen on narrow windows - hints are now tooltips.
- Fix-scan rows flickered and overlapped with long details clipped - rows now rebuild cleanly and wrap.
- Network tab cards overflowed when nested auto-size controls reflowed - cards now size from the table's real preferred size after every layout pass.
- FRP: a busy game port halts cleanly, a missing frpc binary explains itself, a failed tunnel aborts server start, and teardown covers every exit path including orphaned process sweeps.

### ðŸ”’ Security & Privacy (EULA, data scrubbing)

- **Proprietary EULA enforced at startup** - version-checked against the official GitHub repository, full application lockout until accepted, per-version acceptance tracking, and graceful offline behavior.
- **Privacy scrubbing of distributed files** - hardcoded IP-like literals and machine-specific local PC paths were removed from the released code and its on-screen help/status texts; network addresses are only ever detected at runtime, so no personal data ships inside the product or its documentation.
- **Clean Info deep-cleans for sharing** - removes the server key, webhook URL, logs, backups, quarantine folder, the IP-lock marker, and now also the FRP token and its generated config folder, so a shared folder contains no personal data.
- **No lingering tunnel credentials** - the FRP token is masked in Settings, the runtime tunnel config is written atomically and deleted the instant the tunnel stops.
## v0.6.9 - Update 6, Fix 9: UPnP now works with VPNs running

- **UPnP port-forward fixed:** the router search now binds to your LAN interface,
  so Radmin VPN / Tailscale / ZeroTier can no longer hijack the discovery - "Open
  port on router via UPnP" and the automatic forward on server start now reach the
  router even while a VPN is connected (verified: mapping created on a TP-Link).
- **Clearer failures:** when a router refuses a mapping, the log now shows the
  router's own SOAP error code (conflict, unsupported, LAN-only...) instead of a
  generic "enable UPnP" hint - and the UPnP button says to retry with VPNs closed
  if the forward still fails.

## v0.6.8 - Update 6, Fix 8: Extra tab, upgraded Settings, VPN one-press Stop, presets and invites

- **New "Extra" tab (toolbar button or Ctrl+E):** lists every window the tool opened
  (server console, launcher, game) with a "Show window" button that restores it - the
  minimized server console is never lost again. The same page has **Submit issue**:
  one press copies a ready-made report (app version, system, recent log lines) to your
  clipboard and opens the GitHub issues page - you paste it there yourself.
- **Settings upgraded:** a map **search box** (type to filter long map lists), **max
  cars per player**, server **description** and **tags** (shown in the BeamMP list),
  behavior switches (allow guests, chat log, debug, info packets), and one **Save
  settings** button that writes everything at once. All fields explain themselves.
- **Presets (Settings):** save a whole setup - all settings + your enabled mods -
  under a name ("Drift night", "Crash event"...), then load it back in one press.
  Stored privately in Server\Presets.
- **VPN Manager:** every running VPN row now has **Stop** (fully closes the VPN in
  one press - processes, disconnect and background service) and **Copy IP** (the
  IP:port address to send friends). Fixed in the test round: row buttons are laid out
  correctly for running VPNs (they used to pile up at the left), rows re-layout after
  every Start/Stop/Copy press, and each Copy IP button always copies its own VPN's
  address.
- **Invites:** the Stats page gained **Copy invite** - one press copies a ready-made
  message (address + connect steps) for friends. Private servers get a clearer
  "(PRIVATE server...)" marker and the button changes to "Copy invite (private)".
- **Fix Problems:** new check "Firewall (BeamNG.drive)" with a one-click fix that
  adds the game's own firewall rule (included in "Fix all possible"). New check
  "Teredo (advanced)" - shows the state and can re-enable it in one click (only if
  you ever need it). Fix rows now re-scan automatically after each fix.
- **BeamNG firewall rule:** no more game firewall warnings / blocked joins for friends.
- **Reliability fixes:** the tool now kills leftover BeamMP-Launcher processes before
  starting (a stale launcher used to block port 4444 and spam "bind failed 10048"),
  the launcher opens in its own folder so it stops dropping config/cache files into
  the tool folder, and Resources\Client\mods.json is now a valid object (the server
  no longer fails to hash client mods). Copy IP / Copy invite always fetch fresh
  addresses, and the Stats page has a copy button for every running VPN.
- **Settings tab redesigned:** the page is now a stack of rounded section cards
  (General, Behavior, Port & key & updates, Map, Visibility, Presets) with blue
  section titles and dark inset inputs - every setting is easier to find and the
  page resizes cleanly.
- **Crash fix (copy buttons):** the Copy IP / Copy invite / per-VPN copy buttons
  crashed the whole app ("Error formatting a string") because the click-handler
  template mixed literal `{}` braces with placeholders. Handlers are now built
  without format strings, so every copy button works again.
- **Guide:** new step 10 (lost windows + reporting problems) and the Settings step
  rewritten for the new options.
- **Docs updated:** README and README.txt refreshed for v0.6.8.

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
