# Linux Security Installation Checklist
**Date: 2025-01-30**  
**Objective: Verify security hardening on fresh Linux install**

## PAUSE POINT 1: Network Security
Read each item aloud and run the verification command:

- [ ] **Firewall is enabled and denying by default?**  
  `sudo ufw status verbose | grep "Status: active"`  
  → Must show "Status: active"

- [ ] **Only required ports are open?**  
  `sudo ufw status numbered | grep ALLOW`  
  → Should only show 22, 80, 443 (or your specific needs)

- [ ] **SYN flood protection enabled?**  
  `sysctl net.ipv4.tcp_syncookies`  
  → Must show "= 1"

- [ ] **IP forwarding disabled?**  
  `sysctl net.ipv4.ip_forward`  
  → Must show "= 0"

## PAUSE POINT 2: Access Control
Read each item aloud and run the verification command:

- [ ] **Root SSH login disabled?**  
  `grep "^PermitRootLogin" /etc/ssh/sshd_config`  
  → Must show "PermitRootLogin no"

- [ ] **Password authentication disabled?**  
  `grep "^PasswordAuthentication" /etc/ssh/sshd_config`  
  → Must show "PasswordAuthentication no"

- [ ] **Fail2ban is running?**  
  `systemctl is-active fail2ban`  
  → Must show "active"

- [ ] **Auto-updates configured?**  
  `apt-config dump APT::Periodic::Unattended-Upgrade`  
  → Must show "1" (not "0")

## PAUSE POINT 3: Monitoring
Read each item aloud and run the verification command:

- [ ] **AIDE database initialized?**  
  `ls -la /var/lib/aide/aide.db*`  
  → Must show database file exists

- [ ] **Critical logs are being collected?**  
  `ls -la /var/log/auth.log /var/log/syslog`  
  → Both files must exist and be growing

## CRITICAL FAILURE POINTS
**STOP deployment if any of these fail:**
- Firewall not active
- Root SSH still permitted  
- Password authentication still enabled

---
*Review this checklist quarterly or after any major system changes*