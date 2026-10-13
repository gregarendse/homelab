# RouterOS Script: Pi-hole DNS Health Check & DHCP Failover with Email Alerts
# File: scripts/mikrotik/check_dns_failover.rsc
#
# Description:
#   Monitors Pi-hole DNS server availability from a MikroTik router.
#   - If Pi-hole fails to resolve a test domain, updates the DHCP server network's DNS setting to a safe fallback DNS.
#   - Automatically recovers and switches back to Pi-hole when Pi-hole DNS resolution is restored.
#   - Sends email notifications on failover and recovery events (if emailSend is enabled).

# -----------------------------------------------------------------------------
# User Configuration Parameters
# -----------------------------------------------------------------------------
:local piholeIP "192.168.1.53"
:local fallbackDNS "1.1.1.1"
:local testDomain "google.com"
:local dhcpNetworkAddress "192.168.1.0/24"
:local maxRetries 3
:local retryDelay 1s

# Email Notification Settings
:local emailSend true
:local emailAddress "admin@example.com"

# -----------------------------------------------------------------------------
# Health Check Execution
# -----------------------------------------------------------------------------
:local piholeHealthy false
:local attempt 0

:while ($attempt < $maxRetries && $piholeHealthy = false) do={
    :do {
        :local resolvedIP [:resolve $testDomain server=$piholeIP]
        :if ([:len $resolvedIP] > 0) do={
            :set piholeHealthy true
        }
    } on-error={
        :set attempt ($attempt + 1)
        :if ($attempt < $maxRetries) do={
            :delay $retryDelay
        }
    }
}

# -----------------------------------------------------------------------------
# DHCP Server Network Update, Email Notification & State Transition
# -----------------------------------------------------------------------------
:local dhcpNet [/ip dhcp-server network find address=$dhcpNetworkAddress]
:local identityName [/system identity get name]

:if ([:len $dhcpNet] = 0) do={
    :log error ("Pi-hole Check: Target DHCP network address (" . $dhcpNetworkAddress . ") not found!")
} else={
    :local currentDNS [/ip dhcp-server network get $dhcpNet dns-server]

    :if ($piholeHealthy = true) do={
        # Pi-hole is healthy
        :if ($currentDNS != $piholeIP) do={
            :local logMsg ("Pi-hole Check: Pi-hole (" . $piholeIP . ") is ONLINE. Restoring DHCP DNS server to " . $piholeIP)
            :log info $logMsg
            /ip dhcp-server network set $dhcpNet dns-server=$piholeIP

            :if ($emailSend = true && [:len $emailAddress] > 0) do={
                :do {
                    /tool e-mail send to=$emailAddress \
                        subject=("[" . $identityName . "] RECOVERY: Pi-hole DNS Restored") \
                        body=("Router: " . $identityName . "\nStatus: Primary Pi-hole DNS (" . $piholeIP . ") is back online.\nDHCP Server network (" . $dhcpNetworkAddress . ") DNS setting restored to " . $piholeIP . ".")
                } on-error={
                    :log warning "Pi-hole Check: Failed to send recovery email notification."
                }
            }
        }
    } else={
        # Pi-hole is failing
        :if ($currentDNS != $fallbackDNS) do={
            :local logMsg ("Pi-hole Check: Pi-hole (" . $piholeIP . ") DNS resolution FAILED. Switching DHCP DNS server to fallback (" . $fallbackDNS . ")")
            :log warning $logMsg
            /ip dhcp-server network set $dhcpNet dns-server=$fallbackDNS

            :if ($emailSend = true && [:len $emailAddress] > 0) do={
                :do {
                    /tool e-mail send to=$emailAddress \
                        subject=("[" . $identityName . "] ALERT: Pi-hole DNS Failed - Switched to Fallback") \
                        body=("Router: " . $identityName . "\nStatus: Primary Pi-hole DNS (" . $piholeIP . ") failed health check.\nDHCP Server network (" . $dhcpNetworkAddress . ") DNS setting switched to fallback (" . $fallbackDNS . ").")
                } on-error={
                    :log warning "Pi-hole Check: Failed to send alert email notification."
                }
            }
        }
    }
}
