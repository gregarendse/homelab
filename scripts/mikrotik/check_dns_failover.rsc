# RouterOS Script: Pi-hole DNS Health Check & DHCP Failover
# File: scripts/mikrotik/check_dns_failover.rsc
#
# Description:
#   Monitors Pi-hole DNS server availability from a MikroTik router.
#   - If Pi-hole fails to resolve a test domain, updates the DHCP server network's DNS setting to a safe fallback DNS.
#   - Automatically recovers and switches back to Pi-hole when Pi-hole DNS resolution is restored.

# -----------------------------------------------------------------------------
# User Configuration Parameters
# -----------------------------------------------------------------------------
:local piholeIP "192.168.1.53"
:local fallbackDNS "1.1.1.1"
:local testDomain "google.com"
:local dhcpNetworkAddress "192.168.1.0/24"
:local maxRetries 3
:local retryDelay 1s

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
# DHCP Server Network Update & State Transition
# -----------------------------------------------------------------------------
:local dhcpNet [/ip dhcp-server network find address=$dhcpNetworkAddress]

:if ([:len $dhcpNet] = 0) do={
    :log error ("Pi-hole Check: Target DHCP network address (" . $dhcpNetworkAddress . ") not found!")
} else={
    :local currentDNS [/ip dhcp-server network get $dhcpNet dns-server]

    :if ($piholeHealthy = true) do={
        # Pi-hole is healthy
        :if ($currentDNS != $piholeIP) do={
            :log info ("Pi-hole Check: Pi-hole (" . $piholeIP . ") is ONLINE. Restoring DHCP DNS server to " . $piholeIP)
            /ip dhcp-server network set $dhcpNet dns-server=$piholeIP
        }
    } else={
        # Pi-hole is failing
        :if ($currentDNS != $fallbackDNS) do={
            :log warning ("Pi-hole Check: Pi-hole (" . $piholeIP . ") DNS resolution FAILED. Switching DHCP DNS server to fallback (" . $fallbackDNS . ")")
            /ip dhcp-server network set $dhcpNet dns-server=$fallbackDNS
        }
    }
}
