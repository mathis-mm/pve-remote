# Proxmox Remote (iOS)

A small SwiftUI app to control a Proxmox VE server from your iPhone. It lets you:
- Connect to your Proxmox VE API over HTTPS (port 8006)
- Reboot or shutdown the selected node
- Logout to clear the session

Use this app with care: reboot and shutdown actions affect the selected node immediately.

## Requirements
- iOS 18.0 or later (iPhone)
- XCODE (to build from source)
- A reachable Proxmox VE instance (default API port: 8006)

## Getting started
1. Clone the repository.
2. Open the project in Xcode.
3. Build and run on an iOS 18 device or simulator.
4. In the app:
   - Enter Host (IP or DNS of your Proxmox server, no protocol prefix)
   - Enter Username and Password
   - Enter Realm (e.g. `pam`, `pve`, `ldap`)
   - Toggle “Allow self‑signed certificate” if your PVE uses a self‑signed cert
   - Tap “Connect”
5. Pick a node and use “Reboot Node” or “Shutdown Node”. Tap “Logout” to clear the session.

## Notes
- Host should be something like `192.168.1.10` or `pve.local` (no `https://`).
- The app talks to `https://<host>:8006/api2/json`.
- Session ticket and CSRF token are kept only in memory and cleared on logout.
- For production use, prefer a dedicated Proxmox account with minimal permissions for power management.

## Troubleshooting
- Connection errors: check host/port reachability, certificate trust, and firewall.
- Authorization errors: verify credentials, realm, and that the account can manage power for the node.
- Unexpected HTTP errors: ensure your Proxmox VE is up, reachable via HTTPS, and the API is enabled.

## Project structure
- `pve_remoteApp.swift` — App entry point
- `ContentView.swift` — SwiftUI screens and a lightweight Proxmox API client
- `Assets.xcassets` — App icons and images

# later
- Saved connections / keychain integration ?
- More node actions and metrics ?