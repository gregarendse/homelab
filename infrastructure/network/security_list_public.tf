# Source from https://registry.terraform.io/providers/oracle/oci/latest/docs/resources/core_security_list

resource "oci_core_security_list" "public" {

  # Required
  compartment_id = data.oci_identity_compartment.homelab.id
  vcn_id         = data.oci_core_vcn.homelab.id
  # module.vcn.vcn_id

  # Optional
  display_name = "public"


  # Allow all outbound traffic to any destination
  egress_security_rules {
    description      = "Egress ALL"
    stateless        = false
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
  }

  dynamic "ingress_security_rules" {
    for_each = {
      for combo in flatten([
        for port in local.ports : [
          for source in port.sources : {
            key    = "${port.name}-${source}"
            port   = port
            source = source
          }
        ]
      ]) : combo.key => combo
    }
    iterator = rule

    content {
      description = rule.value.port.notes
      protocol    = rule.value.port.protocol == "HTTPS" ? local.protocol_numbers.TCP : (rule.value.port.protocol == "TCP" ? local.protocol_numbers.TCP : local.protocol_numbers.UDP)
      source      = rule.value.source
      source_type = "CIDR_BLOCK"
      stateless   = false

      dynamic "tcp_options" {
        for_each = contains(["TCP", "HTTP", "HTTPS"], rule.value.port.protocol) ? [1] : []
        content {
          min = rule.value.port.ports.listener
          max = rule.value.port.ports.listener
        }
      }

      dynamic "udp_options" {
        for_each = contains(["UDP", "DNS"], rule.value.port.protocol) ? [1] : []
        content {
          min = rule.value.port.ports.listener
          max = rule.value.port.ports.listener
        }
      }
    }
  }

  ingress_security_rules {
    description = "Ingress ICMP Destination Unreachable"
    stateless   = false
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    # Get protocol numbers from https://www.iana.org/assignments/protocol-numbers/protocol-numbers.xhtml ICMP is 1  
    protocol = "1"

    # For ICMP type and code see: https://www.iana.org/assignments/icmp-parameters/icmp-parameters.xhtml
    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    description = "Allow all VCN traffic"
    source      = data.oci_core_vcn.homelab.cidr_block
    protocol    = "all"
  }

  # WireGuard site-to-site tunnel: OCI <-> Trinity (on-prem), direct link.
  # Kept as a static rule (not folded into local.ports) because its NLB
  # backend is pinned to a single instance rather than the whole pool —
  # see network/wireguard-trinity.tf for why.
  ingress_security_rules {
    description = "WireGuard: direct OCI<->Trinity tunnel"
    stateless   = false
    source      = var.trinity_public_ip_cidr
    source_type = "CIDR_BLOCK"
    protocol    = local.protocol_numbers.UDP

    udp_options {
      min = 51820
      max = 51820
    }
  }

  freeform_tags = merge(var.tags, {})
}
