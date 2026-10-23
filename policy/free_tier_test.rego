package main_test

import data.main
import rego.v1

# Helper for infrastructure/compute's pool + instance_configuration setup
compute_plan(pool_size, shape, ocpus, memory_gb, boot_gb) := {"resource_changes": [
	{
		"address": "oci_core_instance_configuration.ubuntu",
		"type": "oci_core_instance_configuration",
		"change": {
			"actions": ["create"],
			"after": {"instance_details": [{"launch_details": [{
				"shape": shape,
				"shape_config": [{
					"ocpus": ocpus,
					"memory_in_gbs": memory_gb,
				}],
				"source_details": [{"boot_volume_size_in_gbs": boot_gb}],
			}]}]},
		},
	},
	{
		"address": "oci_core_instance_pool.ubuntu",
		"type": "oci_core_instance_pool",
		"change": {
			"actions": ["create"],
			"after": {"size": pool_size},
		},
	},
]}

test_valid_single_a1_pool if {
	msgs := main.deny with input as compute_plan(1, "VM.Standard.A1.Flex", 2, 12, 100)
	count(msgs) == 0
}

test_valid_two_node_a1_pool if {
	msgs := main.deny with input as compute_plan(2, "VM.Standard.A1.Flex", 1, 6, 100)
	count(msgs) == 0
}

test_deny_pool_exceeds_ocpus if {
	msgs := main.deny with input as compute_plan(2, "VM.Standard.A1.Flex", 2, 6, 50)
	"A1 OCPUs 4 exceed Always Free limit of 2" in msgs
}

test_deny_pool_exceeds_ram if {
	msgs := main.deny with input as compute_plan(2, "VM.Standard.A1.Flex", 1, 12, 50)
	"A1 RAM 24 GB exceeds Always Free limit of 12 GB" in msgs
}

test_deny_pool_exceeds_storage if {
	msgs := main.deny with input as compute_plan(2, "VM.Standard.A1.Flex", 1, 6, 150)
	"Block storage (boot + data) 300 GB exceeds Always Free limit of 200 GB" in msgs
}

test_deny_non_free_shape if {
	msgs := main.deny with input as compute_plan(1, "VM.Standard.E4.Flex", 1, 6, 50)
	"oci_core_instance_configuration.ubuntu: shape VM.Standard.E4.Flex is not Always Free" in msgs
}

test_allow_non_compute_plan if {
	msgs := main.deny with input as {"resource_changes": []}
	count(msgs) == 0
}

test_deny_pool_without_config if {
	msgs := main.deny with input as {"resource_changes": [{
		"address": "oci_core_instance_pool.ubuntu",
		"type": "oci_core_instance_pool",
		"change": {
			"actions": ["create"],
			"after": {"size": 1},
		},
	}]}
	"Instance pool present in plan without an instance configuration to evaluate Always Free limits" in msgs
}

vault_plan(vault_type) := {"resource_changes": [{
	"address": "oci_kms_vault.homelab",
	"type": "oci_kms_vault",
	"change": {
		"actions": ["create"],
		"after": {"vault_type": vault_type},
	},
}]}

test_allow_default_vault if {
	msgs := main.deny with input as vault_plan("DEFAULT")
	count(msgs) == 0
}

test_allow_default_vault_lowercase if {
	msgs := main.deny with input as vault_plan("default")
	count(msgs) == 0
}

test_deny_virtual_private_vault if {
	msgs := main.deny with input as vault_plan("VIRTUAL_PRIVATE")
	"oci_kms_vault.homelab: vault_type VIRTUAL_PRIVATE is not Always Free" in msgs
}

test_deny_virtual_private_vault_lowercase if {
	msgs := main.deny with input as vault_plan("virtual_private")
	"oci_kms_vault.homelab: vault_type virtual_private is not Always Free" in msgs
}

test_deny_external_vault if {
	msgs := main.deny with input as vault_plan("EXTERNAL")
	"oci_kms_vault.homelab: vault_type EXTERNAL is not Always Free" in msgs
}

test_deny_unknown_vault_type if {
	msgs := main.deny with input as {"resource_changes": [{
		"address": "oci_kms_vault.homelab",
		"type": "oci_kms_vault",
		"change": {
			"actions": ["create"],
			"after": {},
		},
	}]}
	"oci_kms_vault.homelab: vault_type must be set explicitly and known at plan time" in msgs
}

key_plan(protection_mode) := {"resource_changes": [{
	"address": "oci_kms_key.homelab",
	"type": "oci_kms_key",
	"change": {
		"actions": ["create"],
		"after": {"protection_mode": protection_mode},
	},
}]}

test_allow_software_key if {
	msgs := main.deny with input as key_plan("SOFTWARE")
	count(msgs) == 0
}

test_allow_software_key_lowercase if {
	msgs := main.deny with input as key_plan("software")
	count(msgs) == 0
}

test_deny_hsm_key if {
	msgs := main.deny with input as key_plan("HSM")
	"oci_kms_key.homelab: protection_mode HSM is not Always Free" in msgs
}

test_deny_external_key if {
	msgs := main.deny with input as key_plan("EXTERNAL")
	"oci_kms_key.homelab: protection_mode EXTERNAL is not Always Free" in msgs
}

test_deny_unknown_protection_mode if {
	msgs := main.deny with input as {"resource_changes": [{
		"address": "oci_kms_key.homelab",
		"type": "oci_kms_key",
		"change": {
			"actions": ["create"],
			"after": {},
		},
	}]}
	"oci_kms_key.homelab: protection_mode must be SOFTWARE and known at plan time (provider default is HSM)" in msgs
}

test_allow_delete_hsm_key if {
	msgs := main.deny with input as {"resource_changes": [{
		"address": "oci_kms_key.homelab",
		"type": "oci_kms_key",
		"change": {
			"actions": ["delete"],
			"after": null,
		},
	}]}
	count(msgs) == 0
}

test_allow_delete_virtual_private_vault if {
	msgs := main.deny with input as {"resource_changes": [{
		"address": "oci_kms_vault.homelab",
		"type": "oci_kms_vault",
		"change": {
			"actions": ["delete"],
			"after": null,
		},
	}]}
	count(msgs) == 0
}
