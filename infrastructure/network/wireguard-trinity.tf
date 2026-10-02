# Direct OCI <-> Trinity WireGuard tunnel — NLB frontend.
#
# Deliberately NOT added to local.ports in locals.tf. That list drives a
# backend registration for every instance in the pool (see local.instances /
# oci_network_load_balancer_backend in nlb.tf), which is correct for
# stateless HTTP/DNS/etc. services but wrong here: WireGuard only listens on
# whichever single instance is running the gateway pod (see
# infrastructure/kubernetes/wireguard-trinity.tf), and OCI NLB's FIVE_TUPLE
# hashing would otherwise deterministically route Trinity's fixed 5-tuple to
# a pool instance with nothing listening, blackholing the tunnel with no
# retry (not a transient failure — the same 5-tuple always hashes the same
# way). So this backend set targets exactly one, named instance.

data "oci_core_instances" "wireguard_gateway_candidates" {
  compartment_id = data.oci_identity_compartment.homelab.id
  display_name   = var.wireguard_gateway_instance_name
  filter {
    name   = "state"
    values = ["RUNNING"]
  }
}

locals {
  wireguard_gateway_instance = data.oci_core_instances.wireguard_gateway_candidates.instances[0]
}

resource "oci_network_load_balancer_backend_set" "wireguard_trinity" {
  name                     = "wireguard-trinity"
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.public.id
  policy                   = "FIVE_TUPLE"
  is_preserve_source       = true
  # Single backend either way, so fail-open vs fail-closed doesn't change
  # routing here — set true for consistency with the other UDP backend sets.
  is_fail_open = true

  health_checker {
    protocol = "UDP"
    port     = 51820
    # WireGuard won't echo an arbitrary payload back, so this health check
    # will generally show unhealthy. Harmless: is_fail_open = true and
    # there's only one backend, so it's never excluded from routing.
    request_data  = "AA=="
    response_data = "AA=="
  }

  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}

resource "oci_network_load_balancer_listener" "wireguard_trinity" {
  name                     = "wireguard-trinity"
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.public.id
  default_backend_set_name = oci_network_load_balancer_backend_set.wireguard_trinity.name
  port                     = 51820
  protocol                 = "UDP"

  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }

  depends_on = [
    oci_network_load_balancer_backend_set.wireguard_trinity
  ]
}

resource "oci_network_load_balancer_backend" "wireguard_trinity" {
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.public.id
  backend_set_name         = oci_network_load_balancer_backend_set.wireguard_trinity.name
  target_id                = local.wireguard_gateway_instance.id
  port                     = 51820

  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}

output "wireguard_gateway_instance_private_ip" {
  description = "Private IP of the pinned WireGuard gateway instance — needed by infrastructure/kubernetes (route DaemonSet ConfigMap) and for the Trinity-side wg0.conf Endpoint sanity check."
  value       = local.wireguard_gateway_instance.private_ip
}

output "wireguard_public_endpoint" {
  description = <<-EOT
    Public IP:port Trinity's wg0.conf should use as Endpoint. Note the
    "Kubernetes" oci_core_public_ip reservation in nlb.tf isn't actually
    attached to the NLB (its reserved_ips block is commented out), so this
    reads the NLB's own (ephemeral) public IP instead. If you want a fixed
    endpoint that survives NLB recreation, uncomment reserved_ips in nlb.tf
    first and switch this to reference oci_core_public_ip.kubernetes instead.
  EOT
  value       = "${oci_network_load_balancer_network_load_balancer.public.ip_addresses[0].ip_address}:51820"
}
