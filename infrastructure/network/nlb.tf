# Public Load Balancer
resource "oci_core_public_ip" "kubernetes" {
  compartment_id = data.oci_identity_compartment.homelab.id
  display_name   = "Kubernetes"
  lifetime       = "RESERVED"

  # ToDo: Replace with reference
  private_ip_id = "ocid1.privateip.oc1.uk-london-1.abwgiljr5fn4y6uuuoakjy3vkdkyen6pjqig6newy7zhl33mki7cuqlkryka"

  freeform_tags = merge(var.tags, {})
}

resource "oci_network_load_balancer_network_load_balancer" "public" {
  compartment_id = data.oci_identity_compartment.homelab.id

  display_name = "Kubernetes"

  # Public Load Balancers must be in a public subnet
  subnet_id = data.oci_core_subnet.public.id

  is_private = false

  nlb_ip_version                 = "IPV4"
  is_preserve_source_destination = false

  # reserved_ips {
  #   id = oci_core_public_ip.kubernetes.id
  # }

  freeform_tags = merge(var.tags, {})
}

resource "oci_network_load_balancer_backend_set" "backend_set" {
  for_each = {
    for port in local.ports : port.name => port
  }
  # https://docs.oracle.com/en-us/iaas/api/#/en/networkloadbalancer/20200501/datatypes/UpdateBackendSetDetails
  # https://docs.oracle.com/en-us/iaas/api/#/en/networkloadbalancer/20200501/BackendSet/CreateBackendSet

  name                     = each.value.name
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.public.id
  policy                   = "FIVE_TUPLE"
  is_preserve_source       = true
  is_fail_open             = each.value.protocol == "UDP" ? true : false
  # ip_version                            = "IPV4"
  # is_instant_failover_enabled           = false
  # is_instant_failover_tcp_reset_enabled = true

  dynamic "health_checker" {
    for_each = each.value.health_check.protocol == "HTTP" || each.value.health_check.protocol == "HTTPS" ? [1] : []

    content {
      protocol    = each.value.health_check.protocol
      return_code = each.value.health_check.return_code
      url_path    = each.value.health_check.path
      port        = each.value.ports.target
    }

  }

  dynamic "health_checker" {
    for_each = each.value.health_check.protocol == "TCP" ? [1] : []

    content {
      protocol = "TCP"
      port     = each.value.ports.target
    }
  }

  dynamic "health_checker" {
    for_each = each.value.health_check.protocol == "UDP" ? [1] : []

    content {
      protocol      = "UDP"
      port          = each.value.ports.target
      request_data  = each.value.health_check.request_data
      response_data = each.value.health_check.response_data
    }
  }

  dynamic "health_checker" {
    for_each = each.value.health_check.protocol == "DNS" ? [1] : []

    content {
      protocol = "DNS"
      # request_data       = "AQAAAgAAABwAAAAAZXhhbXBsZQAuY29tAAEAAQ=="     # DNS query for example.com
      # response_data      = "AAABAAABAAAAAAABAAAAAABleGFtcGxlA2NvbQAAAQAB" # DNS response for example.com
      port               = each.value.ports.target
      interval_in_millis = 100000
      timeout_in_millis  = 10000
      retries            = 1
    }
  }

  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}

resource "oci_network_load_balancer_listener" "listener" {
  for_each = {
    for port in local.ports : port.name => port
  }

  default_backend_set_name = each.value.name
  name                     = each.value.name
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.public.id

  port     = each.value.ports.listener
  protocol = each.value.protocol

  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }

  depends_on = [
    oci_network_load_balancer_backend_set.backend_set
  ]
}

locals {
  instances = flatten([
    for instance in data.oci_core_instances.instances.instances : [
      for port in local.ports : {
        instance = instance
        port     = port
      }
    ]
  ])
}

resource "oci_network_load_balancer_backend" "backend" {
  for_each = { for i in local.instances : "${i.instance.display_name}-${i.port.name}" => i }

  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.public.id
  backend_set_name         = each.value.port.name

  target_id = each.value.instance.id
  port      = each.value.port.ports.target

  timeouts {
    create = "10m"
    update = "10m"
    delete = "10m"
  }
}
