# Source from https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_security_list

resource "oci_core_security_list" "private" {
  # Required
  compartment_id = data.oci_identity_compartment.homelab.id
  vcn_id         = data.oci_core_vcn.homelab.id

  # Optional
  display_name = "private"

  # Allow all egress traffic
  egress_security_rules {
    description = "Egress ALL"
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # Allow Ingress traffic from the public subnet
  ingress_security_rules {
    description = "Allow Ingress traffic from the public subnet"
    source      = local.subnet_public_cdir
    source_type = "CIDR_BLOCK"
    protocol    = "all"
  }

  # Public ports
  dynamic "ingress_security_rules" {
    for_each = {
      for i in local.ports : i.name => i
      if contains(i.sources, "0.0.0.0/0") && i.protocol != "TCP/UDP"
    }
    iterator = port_rule
    content {
      description = port_rule.value.notes
      source      = "0.0.0.0/0"
      source_type = "CIDR_BLOCK"
      protocol    = port_rule.value.protocol == "HTTPS" ? local.protocol_numbers.TCP : (port_rule.value.protocol == "TCP" ? local.protocol_numbers.TCP : local.protocol_numbers.UDP)

      dynamic "tcp_options" {
        for_each = port_rule.value.protocol == "TCP" || port_rule.value.protocol == "HTTPS" ? [1] : []
        content {
          min = port_rule.value.ports.target
          max = port_rule.value.ports.target
        }
      }

      dynamic "udp_options" {
        for_each = port_rule.value.protocol == "UDP" ? [1] : []
        content {
          min = port_rule.value.ports.target
          max = port_rule.value.ports.target
        }
      }
    }
  }

  dynamic "ingress_security_rules" {
    for_each = {
      for i in local.ports : i.name => i
      if !contains(i.sources, "0.0.0.0/0") && contains(["TCP", "HTTP", "HTTPS", "UDP", "DNS"], i.protocol)
    }
    iterator = port_rule
    content {
      description = port_rule.value.notes
      source      = "192.168.1.0/24"
      source_type = "CIDR_BLOCK"
      protocol    = local.protocol_numbers[port_rule.value.protocol] # == "HTTPS" ? local.protocol_numbers.TCP : (port_rule.value.protocol == "TCP" ? local.protocol_numbers.TCP : local.protocol_numbers.UDP)

      dynamic "tcp_options" {
        for_each = contains(["TCP", "HTTP", "HTTPS"], port_rule.value.protocol) ? [1] : []
        # for_each = port_rule.value.protocol == "TCP" || port_rule.value.protocol == "HTTPS" ? [1] : []
        content {
          min = port_rule.value.ports.target
          max = port_rule.value.ports.target
        }
      }

      dynamic "udp_options" {
        for_each = contains(["UDP", "DNS"], port_rule.value.protocol) ? [1] : []
        # for_each = port_rule.value.protocol == "UDP" ? [1] : []
        content {
          min = port_rule.value.ports.target
          max = port_rule.value.ports.target
        }
      }
    }
  }

  # Additional rules
  ingress_security_rules {
    description = "Ingress etcd client port"
    stateless   = false
    source      = local.subnet_private_cdir
    protocol    = local.protocol_numbers.TCP
    tcp_options {
      min = 2379
      max = 2379
    }
  }
  ingress_security_rules {
    description = "Ingress kube-apiserver"
    stateless   = false
    source      = local.subnet_private_cdir
    protocol    = local.protocol_numbers.TCP
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  # Allow all VCN traffic
  ingress_security_rules {
    description = "Allow all VCN traffic"
    source      = data.oci_core_vcn.homelab.cidr_block
    protocol    = "all"
  }

  # Allow all subnet traffic
  ingress_security_rules {
    description = "Allow all subnet traffic"
    source      = local.subnet_private_cdir
    protocol    = "all"
  }

  ingress_security_rules {
    description = "Ingress SSH from Home"
    stateless   = false
    source      = "192.168.1.0/24"
    source_type = "CIDR_BLOCK"
    protocol    = local.protocol_numbers.TCP
    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    description = "Ingress ICMP Destination Unreachable (public)"
    stateless   = false
    source      = local.subnet_public_cdir
    source_type = "CIDR_BLOCK"
    protocol    = local.protocol_numbers.ICMP
  }

  freeform_tags = merge(var.tags, {})
}
