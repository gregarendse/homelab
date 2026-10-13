variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"

  validation {
    condition     = can(file(var.kubeconfig_path))
    error_message = "Kubeconfig file not found at the specified path"
  }
}


variable "domain_name" {
  description = "The domain name to be managed by External DNS"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", lower(var.domain_name)))
    error_message = "Domain name must be a valid domain (e.g., example.com)"
  }
}

variable "ingress_public_ip" {
  description = "Public IP address advertised by Traefik for ingress status and ExternalDNS"
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^((25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])$", var.ingress_public_ip))
    error_message = "ingress_public_ip must be a valid IPv4 address"
  }
}

variable "cert_manager_email" {
  description = ""
  type        = string
  nullable    = false


}

variable "longhorn_backup_bucket" {
  description = "Backblaze B2 (S3) bucket that stores Longhorn backups"
  type        = string
  default     = "gregarendse-longhorn-backups"
  nullable    = false
}

variable "longhorn_backup_region" {
  description = "Backblaze B2 region of the backup bucket"
  type        = string
  default     = "eu-central-003"
  nullable    = false
}

variable "longhorn_backup_retain" {
  description = "Number of recurring backups to retain per volume"
  type        = number
  default     = 1
}

variable "wireguard_gateway_instance_name" {
  description = <<-EOT
    Must match infrastructure/variables.tf's wireguard_gateway_instance_name —
    same OCI pool instance, referenced here to find its node in the oci
    cluster (kubectl get nodes -o wide, matched by InternalIP) so the
    Deployment's nodeSelector and the route DaemonSet's ConfigMap line up
    with the NLB backend pinned in infrastructure/network/wireguard-trinity.tf.
    This variable isn't consumed directly by Terraform here (Kubernetes
    doesn't know OCI instance names) — it's documentation for whoever runs
    `kubectl label node` per docs/wireguard-trinity.md. Kept as a variable
    rather than a bare comment so `terraform plan` output makes the
    dependency on that manual step explicit.
  EOT
  type        = string
}

variable "wireguard_gateway_private_ip" {
  description = <<-EOT
    Private IP of the pinned WireGuard gateway instance — set this from
    `terraform output wireguard_gateway_instance_private_ip` in
    infrastructure/network after applying that root module. Consumed by
    the route-propagation DaemonSet's ConfigMap in wireguard-trinity.tf so
    non-gateway nodes know the next-hop for Trinity's pod/service CIDRs.
  EOT
  type        = string

  validation {
    condition     = can(regex("^((25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])$", var.wireguard_gateway_private_ip))
    error_message = "wireguard_gateway_private_ip must be a valid IPv4 address"
  }
}

variable "trinity_pod_cidr" {
  description = "Trinity cluster's pod CIDR, routed via the WireGuard gateway node."
  type        = string
}

variable "trinity_svc_cidr" {
  description = "Trinity cluster's service CIDR, routed via the WireGuard gateway node."
  type        = string
}
