# Always Free guard, evaluated against `terraform show -json` output.
# Fails closed: values unknown at plan time are treated as violations.
package main

import rego.v1

max_a1_ocpus := 4

max_a1_ram_gb := 24

max_storage_gb := 200

default_boot_gb := 47

allowed_shapes := {"VM.Standard.A1.Flex", "VM.Standard.E2.1.Micro"}

# Resources that will exist after apply (everything except pure deletes)
live_instances := [rc |
	some rc in input.resource_changes
	rc.type == "oci_core_instance"
	rc.change.actions != ["delete"]
]

live_volumes := [rc |
	some rc in input.resource_changes
	rc.type == "oci_core_volume"
	rc.change.actions != ["delete"]
]

shape(rc) := object.get(rc.change.after, "shape", "unknown")

a1 := [rc | some rc in live_instances; shape(rc) == "VM.Standard.A1.Flex"]

known_cfg(rc) if {
	cfg := rc.change.after.shape_config[0]
	is_number(cfg.ocpus)
	is_number(cfg.memory_in_gbs)
}

boot_gb(rc) := n if {
	n := to_number(rc.change.after.source_details[0].boot_volume_size_in_gbs)
	n > 0
} else := default_boot_gb

volume_gb(rc) := to_number(rc.change.after.size_in_gbs)

total_ocpus := sum([rc.change.after.shape_config[0].ocpus | some rc in a1; known_cfg(rc)])

total_ram := sum([rc.change.after.shape_config[0].memory_in_gbs | some rc in a1; known_cfg(rc)])

total_storage := sum([boot_gb(rc) | some rc in live_instances]) + sum([volume_gb(rc) | some rc in live_volumes])

deny contains msg if {
	some rc in live_instances
	not shape(rc) in allowed_shapes
	msg := sprintf("%s: shape %v is not Always Free", [rc.address, shape(rc)])
}

deny contains msg if {
	some rc in a1
	not known_cfg(rc)
	msg := sprintf("%s: A1 ocpus and memory_in_gbs must be set explicitly and known at plan time", [rc.address])
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
