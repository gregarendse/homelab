locals {
  # OCI "Always Free" Ampere A1 Compute monthly allocation.
  # Reduced in 2025 to these totals, shared across 1-2 instances:
  #   https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm
  # OCPUs and memory are split evenly across var.instance_count.
  free_tier = {
    ocpus      = 2   # total OCPUs
    memory_gb  = 12  # total memory
    storage_gb = 200 # total block storage (boot + block volumes)
  }
}
