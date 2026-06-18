resource "oci_core_instance_configuration" "ubuntu" {
  compartment_id = data.oci_identity_compartment.homelab.id
  display_name   = "ubuntu"
  freeform_tags  = merge(var.tags, {})

  instance_details {
    instance_type = "compute"

    launch_details {
      compartment_id = data.oci_identity_compartment.homelab.id
      shape          = var.shape

      shape_config {
        ocpus         = local.free_tier.ocpus / var.instance_count
        memory_in_gbs = local.free_tier.memory_gb / var.instance_count
      }

      create_vnic_details {
        subnet_id        = data.oci_core_subnet.private.id
        assign_public_ip = false
      }

      source_details {
        source_type = "image"
        image_id    = data.oci_core_images.images.images[0].id
        # Free tier allows up to local.free_tier.storage_gb (200 GB) total, but
        # the running instance was provisioned with 100 GB. Keep it at 100 to
        # avoid diverging from the live boot volume; resize in place to grow it.
        boot_volume_size_in_gbs = 100
      }

      metadata = {
        ssh_authorized_keys = file(var.public_key_path)
        user_data           = data.cloudinit_config.cloudinit.rendered
      }
    }
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [instance_details[0].launch_details[0].metadata]
  }
}

resource "oci_core_instance_pool" "ubuntu" {
  compartment_id                  = data.oci_identity_compartment.homelab.id
  display_name                    = "ubuntu"
  instance_display_name_formatter = "ubuntu-$${launchCount}"
  size                            = var.instance_count
  freeform_tags                   = merge(var.tags, {})

  instance_configuration_id = oci_core_instance_configuration.ubuntu.id

  dynamic "placement_configurations" {
    for_each = data.oci_identity_availability_domains.availability_domains.availability_domains[*].name
    content {
      availability_domain = placement_configurations.value

      primary_vnic_subnets {
        subnet_id = data.oci_core_subnet.private.id
      }
    }
  }
}


