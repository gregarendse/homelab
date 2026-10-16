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
