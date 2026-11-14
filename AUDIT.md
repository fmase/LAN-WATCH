# Audit and test status

This document records completed checks and remaining limitations for LAN WATCH.

LAN WATCH remains experimental. Version 1.0 could produce malformed MAC records when parallel scanner processes wrote to the same file. Version 1.0.1 writes each response separately and combines them serially; it detects existing malformed records and preserves them for inspection instead of silently merging or deleting devices. Equal hostnames do not prove equal identities, and MAC rotation cannot be reliably resolved by ARP alone.

Checks performed for this source tree:

- Shell static analysis and simulated scanner, installer, updater and uninstaller tests, including failed stop and rollback conditions.
- A synthetic stress test with 254 concurrent responses on the target router shell: 254 unique IPs and MACs; no ARP traffic was emitted during that mock test.
- The former configurable 3/30/60/120-second schedule and settings CGI were tested, then removed. The current fixed scheduler targets 60 seconds between starts with at least a 3-second pause after each completed cycle. Legacy settings files are preserved but ignored. Update simulation verifies old settings CGI removal and rollback preservation.
- Isolated user-interface tests in both languages for malformed records, equal names, stale/invalid data, missing responses and theme persistence. The Italian dashboard has also been visually inspected in light and dark themes; a full responsive audit remains outstanding.
- Previous scanner and web server versions were tested separately on an ImmortalWrt router and an OMR system. Version 1.0.2 was installed and removed on one ImmortalWrt 25.12-SNAPSHOT router and one OpenWrt 25.12.5 router. Version 1.0.1 was installed, scanned, and updated to itself on both. Removal initially failed due to procd state timing and whitespace handling; version 1.0.2 includes the correction, retested with immediate removal on both. Real device disconnect/reconnect, reboot, firmware upgrade and power-loss tests remain outstanding.

Residual risks: an entirely empty scan is rejected even when all devices are actually offline; other network failures may look like missed responses. Timestamps approximate scan completion. MAC randomization, IP changes, isolation and routed segments limit identification. Event and state writes are not a single transaction; crashes can duplicate or lose events. History is bounded to 10,000 lines. Backup and restore are attempted during updates; power loss, forced termination and failed service restarts can prevent automatic recovery. An interrupted installation may leave an operation lock requiring manual inspection. Firewall rules are not added; the dashboard has no authentication. LAN-IP binding alone does not guarantee isolation. Firmware-upgrade persistence has not been configured.

A v0.1 build with the fixed scheduler and a chosen port was installed and tried on OMR. The latest update-port waiting fix was simulated and has not yet been tested on a router. A complete cross-version upgrade remains unverified. The software is provided without warranty. No automated external security scan has been performed.
