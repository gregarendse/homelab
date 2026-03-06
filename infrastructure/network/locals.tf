locals {
  subnet_private_cdir = cidrsubnet(var.cidr_range, 8, 1)
  subnet_vpn_cdir     = cidrsubnet(var.cidr_range, 8, 7)
  subnet_public_cdir  = cidrsubnet(var.cidr_range, 8, 8)

  protocol_numbers = {
    ALL    = "all"
    ICMP   = "1"
    TCP    = "6"
    UDP    = "17"
    ICMPv6 = "58"
  }

  ports = [
    {
      name     = "http"
      notes    = "HTTP ingress for traffic to the cluster"
      protocol = "TCP"
      sources  = ["0.0.0.0/0"]
      ports = {
        listener = 80
        target   = 30080
      }
      health_check = {
        return_code = 404
        path        = "/ping"
        protocol    = "HTTP"
      }
    },
    {
      name     = "https"
      notes    = "HTTPS ingress for traffic to the cluster"
      protocol = "TCP"
      sources  = ["0.0.0.0/0"]
      ports = {
        listener = 443
        target   = 30443
      }
      health_check = {
        return_code = 404
        path        = "/ping"
        protocol    = "HTTPS"
      }
    },
    {
      name     = "kube-apiserver"
      notes    = "worker, CLI => controller     Authenticated Kube API using Kube TLS client certs, ServiceAccount tokens with RBAC"
      protocol = "TCP"
      # Restricted to home network and ISP range — not open to the internet
      sources = ["192.168.0.0/16", "80.5.0.0/16"]
      ports = {
        listener = 6443
        target   = 6443
      }
      health_check = {
        protocol    = "HTTPS"
        path        = "/healthz"
        return_code = 401
      }
    },
    {
      name     = "dns"
      notes    = "Pi-hole DNS"
      protocol = "UDP"
      # Restricted to RFC1918, home network, and ISP range — not open to the internet
      sources = ["172.16.0.0/12", "192.168.0.0/16", "80.5.0.0/16"]
      ports = {
        listener = 53
        target   = 30053
      }
      health_check = {
        protocol = "DNS"
      }
    },
    # # Device and application communication
    # { name = "portal"; port = 8080; targetPort = "portal"; protocol = "TCP"; nodePort = 30808;}
    {
      name     = "unifi-portal"
      notes    = "Device and application communication"
      protocol = "TCP"
      sources  = ["192.168.1.0/24"]
      ports = {
        listener = 8080
        target   = 30808
      }
      health_check = {
        protocol = "TCP"
      }
    },
    # STUN for device adoption and communication (also required for Remote Management)
    # { name = "stun"; port = 3478; targetPort = "stun"; protocol = "UDP"; nodePort = 30478;}
    {
      name     = "unifi-stun"
      notes    = "STUN for device adoption and communication (also required for Remote Management)"
      protocol = "UDP"
      sources  = ["192.168.1.0/24"]
      ports = {
        listener = 3478
        target   = 30478
      }
      health_check = {
        protocol      = "UDP"
        request_data  = "ABCD" # Placeholder, replace with actual STUN request data
        response_data = "ABCD" # Placeholder, replace with actual STUN response data
      }
    },
    # # Device discovery during adoption
    # { name = "discovery"; port = 10001; targetPort = "discovery"; protocol = "UDP"; nodePort = 31001;}
    {
      name     = "unifi-discovery"
      notes    = "Device discovery during adoption"
      protocol = "UDP"
      sources  = ["192.168.1.0/24"]
      ports = {
        listener = 10001
        target   = 31001
      }
      health_check = {
        protocol      = "UDP"
        request_data  = "ABCD" # Placeholder, replace with actual discovery request data
        response_data = "ABCD" # Placeholder, replace with actual discovery response data
      }
    },
    # # L2 discovery ("Make application discoverable on L2 network")
    # { name = "mdns"; port = 1900; targetPort = "mdns"; protocol = "UDP"; nodePort = 31900;}
    {
      name     = "unifi-mdns"
      notes    = "L2 discovery (Make application discoverable on L2 network)"
      protocol = "UDP"
      sources  = ["192.168.1.0/24"]
      ports = {
        listener = 1900
        target   = 31900
      }
      health_check = {
        protocol      = "UDP"
        request_data  = "ABCD" # Placeholder, replace with actual mDNS request data
        response_data = "ABCD" # Placeholder, replace with actual mDNS response data
      }
    }
    # # UniFi mobile speed test
    # { name = "speedtest"; port = 6789; targetPort = "speedtest"; protocol = "TCP"; nodePort = 30678;}
    # Not currently used
    # {
    #   name     = "dhcp-udp"
    #   notes    = "DHCP for Pi-hole and other DHCP services"
    #   protocol = "UDP"
    #   sources  = ["192.168.1.0/24"]
    #   ports = {
    #     listener = 67
    #     target   = 30067
    #   }
    # },
    # Not currently used
    # {
    #   name     = "ntp-udp"
    #   notes    = "NTP for Pi-hole and other NTP services"
    #   protocol = "UDP"
    #   sources  = ["192.168.1.0/24"]
    #   ports = {
    #     listener = 123
    #     target   = 300123
    #   }
    # }
  ]
}
