# MikroTik RouterOS Pi-hole DNS Health Check & DHCP Failover

This directory contains a RouterOS script (`check_dns_failover.rsc`) for MikroTik routers. It periodically tests whether your primary Pi-hole DNS server is functional and automatically updates your router's DHCP Server network settings to use a safe fallback DNS server if Pi-hole fails. When Pi-hole recovers, the script automatically restores Pi-hole as the primary DNS server for DHCP clients.

---

## Features

- **Direct DNS Querying**: Queries Pi-hole directly using RouterOS `[:resolve <domain> server=<piholeIP>]`.
- **Retry Mechanism**: Attempts multiple resolution tries before declaring Pi-hole down to prevent false-positive failovers during momentary hiccups.
- **Automatic Recovery**: Automatically reverts DHCP DNS configuration to Pi-hole once health check succeeds again.
- **Email Alerts**: Sends email notifications on failover and recovery events using RouterOS `/tool e-mail`.
- **State Aware**: Avoids unnecessary DHCP network writes and log noise when DNS state remains unchanged.
- **Logging**: Emits system log notifications (`:log warning` and `:log info`) on state transitions.

---

## Prerequisites & Configuration

### 1. Router Email Configuration
To receive email notifications when Pi-hole fails or recovers, ensure RouterOS email tool is configured under `/tool e-mail`:

```routeros
/tool e-mail
set server=smtp.example.com port=587 tls=yes from=router@example.com user=smtp_user password=smtp_password
```

### 2. Script Parameters
Open `check_dns_failover.rsc` and adjust the local variables at the top to match your network setup:

```routeros
:local piholeIP "192.168.1.53"           # IP address of your primary Pi-hole DNS server
:local fallbackDNS "1.1.1.1"             # Fallback DNS server IP (e.g. Cloudflare 1.1.1.1 or 8.8.8.8)
:local testDomain "google.com"           # Domain used for health check lookups
:local dhcpNetworkAddress "192.168.1.0/24"# Target DHCP server network address range
:local maxRetries 3                      # Number of retries before switching to fallback DNS
:local retryDelay 1s                     # Delay between retries

# Email Notification Settings
:local emailSend true                    # Set to true to enable email notifications
:local emailAddress "admin@example.com"  # Email address to receive notifications
```

---

## Installation Guide

### Option 1: Via RouterOS Terminal (Copy / Paste)

1. Open WebFig, WinBox, or SSH into your MikroTik router.
2. Open a Terminal session.
3. Import the script by creating a new script under `/system script`:

```routeros
/system script add name="check_dns_failover" policy=read,write,test,policy source="
# Paste the content of check_dns_failover.rsc here
"
```

### Option 2: Upload File & Import

1. Upload `check_dns_failover.rsc` to your MikroTik router storage via WebFig, WinBox, or SFTP.
2. Run the import command in terminal:

```routeros
/import file-name=check_dns_failover.rsc
```

---

## Scheduling Automatic Execution

To run the check automatically every minute (or desired interval), add a scheduler entry:

```routeros
/system scheduler
add name="check_dns_failover_schedule" \
    interval=1m \
    on-event="check_dns_failover" \
    start-time=startup \
    policy=read,write,test,policy
```

---

## Verification & Testing

### Test Manual Execution
Run the script manually from the RouterOS CLI:

```routeros
/system script run check_dns_failover
```

Check system logs to verify:

```routeros
/log print where message~"Pi-hole Check"
```

### Test Failover & Email Alert
1. Temporarily pause Pi-hole DNS or block access to `piholeIP`.
2. Wait for the scheduler run (or execute manually).
3. Verify DHCP server network DNS setting has changed to your fallback DNS (`1.1.1.1`):
   ```routeros
   /ip dhcp-server network print
   ```
4. Verify email notification is received for the failure alert.
5. Unpause Pi-hole and verify DHCP server network DNS setting restores to `piholeIP` and recovery email is received.
