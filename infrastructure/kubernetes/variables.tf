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

variable "longhorn_backup_endpoint" {
  description = "Backblaze B2 S3-compatible endpoint"
  type        = string
  default     = "https://s3.eu-central-003.backblazeb2.com"
  nullable    = false
}

variable "longhorn_backup_access_key" {
  description = "Backblaze B2 application keyID scoped to the Longhorn backup bucket"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "longhorn_backup_secret_key" {
  description = "Backblaze B2 application key scoped to the Longhorn backup bucket"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "longhorn_backup_retain" {
  description = "Number of recurring backups to retain per volume"
  type        = number
  default     = 7
}
