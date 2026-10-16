# Always Free guard, evaluated against `terraform show -json` output.
# Fails closed: values unknown at plan time are treated as violations.
#
# Supports both standalone `oci_core_instance` resources and
# `oci_core_instance_pool` + `oci_core_instance_configuration` pairs.
#
# Limits reflect Oracle's reduced Always Free Ampere A1 allocation
# (see infrastructure/compute/locals.tf):
#   - 2 A1 OCPUs total
#   - 12 GB A1 RAM total
#   - 200 GB total block storage (boot + data volumes)
package main

import rego.v1

max_a1_ocpus := 2

max_a1_ram_gb := 12

max_storage_gb := 200

default_boot_gb := 47

allowed_shapes := {"VM.Standard.A1.Flex", "VM.Standard.E2.1.Micro"}

# Resources that will exist after apply (everything except pure deletes)
live_resources(resource_type) := [rc |
	some rc in input.resource_changes
	rc.type == resource_type
	rc.change.actions != ["delete"]
]

live_instances := live_resources("oci_core_instance")

live_pools := live_resources("oci_core_instance_pool")

live_configs := live_resources("oci_core_instance_configuration")

live_volumes := live_resources("oci_core_volume")

# --- Standalone oci_core_instance helpers ---

instance_shape(rc) := object.get(rc.change.after, "shape", "unknown")

a1_instances := [rc | some rc in live_instances; instance_shape(rc) == "VM.Standard.A1.Flex"]

known_instance_cfg(rc) if {
	cfg := rc.change.after.shape_config[0]
	is_number(cfg.ocpus)
	is_number(cfg.memory_in_gbs)
}

instance_boot_gb(rc) := n if {
	n := to_number(rc.change.after.source_details[0].boot_volume_size_in_gbs)
	n > 0
} else := default_boot_gb

# --- oci_core_instance_configuration + oci_core_instance_pool helpers ---

config_launch(cfg) := cfg.change.after.instance_details[0].launch_details[0]

config_shape(cfg) := object.get(config_launch(cfg), "shape", "unknown")

a1_configs := [cfg | some cfg in live_configs; config_shape(cfg) == "VM.Standard.A1.Flex"]

known_config_cfg(cfg) if {
	sc := config_launch(cfg).shape_config[0]
	is_number(sc.ocpus)
	is_number(sc.memory_in_gbs)
}

config_boot_gb(cfg) := n if {
	n := to_number(config_launch(cfg).source_details[0].boot_volume_size_in_gbs)
	n > 0
} else := default_boot_gb

known_pool_size(pool) if {
	is_number(pool.change.after.size)
	pool.change.after.size >= 0
}

# Total active pool size across all live instance pools.
total_pool_instances := sum([pool.change.after.size | some pool in live_pools; known_pool_size(pool)])

# When an instance configuration is paired with pool(s), multiply the active
# configuration's per-instance resources by the pool size (or 1 if no pool is
# in the plan).
effective_pool_multiplier := total_pool_instances if {
	count(live_pools) > 0
} else := 1

# --- Totals ---

volume_gb(rc) := to_number(rc.change.after.size_in_gbs)

instance_ocpus := sum([rc.change.after.shape_config[0].ocpus | some rc in a1_instances; known_instance_cfg(rc)])

config_ocpus := sum([ocpus |
	some cfg in a1_configs
	known_config_cfg(cfg)
	ocpus := config_launch(cfg).shape_config[0].ocpus * effective_pool_multiplier
])

total_ocpus := instance_ocpus + config_ocpus

instance_ram := sum([rc.change.after.shape_config[0].memory_in_gbs | some rc in a1_instances; known_instance_cfg(rc)])

config_ram := sum([ram |
	some cfg in a1_configs
	known_config_cfg(cfg)
	ram := config_launch(cfg).shape_config[0].memory_in_gbs * effective_pool_multiplier
])

total_ram := instance_ram + config_ram

instance_storage := sum([instance_boot_gb(rc) | some rc in live_instances])

config_storage := sum([boot |
	some cfg in live_configs
	boot := config_boot_gb(cfg) * effective_pool_multiplier
])

volume_storage := sum([volume_gb(rc) | some rc in live_volumes])

total_storage := (instance_storage + config_storage) + volume_storage

# --- Denials ---

deny contains msg if {
	count(live_pools) > 0
	count(live_configs) == 0
	msg := "Instance pool present in plan without an instance configuration to evaluate Always Free limits"
}

deny contains msg if {
	some rc in live_instances
	not instance_shape(rc) in allowed_shapes
	msg := sprintf("%s: shape %v is not Always Free", [rc.address, instance_shape(rc)])
}

deny contains msg if {
	some cfg in live_configs
	not config_shape(cfg) in allowed_shapes
	msg := sprintf("%s: shape %v is not Always Free", [cfg.address, config_shape(cfg)])
}

deny contains msg if {
	some rc in a1_instances
	not known_instance_cfg(rc)
	msg := sprintf("%s: A1 ocpus and memory_in_gbs must be set explicitly and known at plan time", [rc.address])
}

deny contains msg if {
	some cfg in a1_configs
	not known_config_cfg(cfg)
	msg := sprintf("%s: A1 ocpus and memory_in_gbs must be set explicitly and known at plan time", [cfg.address])
}

deny contains msg if {
	some pool in live_pools
	not known_pool_size(pool)
	msg := sprintf("%s: instance pool size must be known at plan time", [pool.address])
}

deny contains msg if {
	total_ocpus > max_a1_ocpus
	msg := sprintf("A1 OCPUs %v exceed Always Free limit of %v", [total_ocpus, max_a1_ocpus])
}

deny contains msg if {
	total_ram > max_a1_ram_gb
	msg := sprintf("A1 RAM %v GB exceeds Always Free limit of %v GB", [total_ram, max_a1_ram_gb])
}

deny contains msg if {
	total_storage > max_storage_gb
	msg := sprintf("Block storage (boot + data) %v GB exceeds Always Free limit of %v GB", [total_storage, max_storage_gb])
}
