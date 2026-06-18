#   Populated by environment variable TF_VAR_tenancy_ocid
variable "tenancy_ocid" {
  description = "Tenancy OCID"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^ocid1.tenancy.oc1..*$", var.tenancy_ocid))
    error_message = "Invalid OCID format, expected: ocid1.tenancy.oc1..*"
  }
}
#   Populated by environment variable TF_VAR_user_ocid
variable "user_ocid" {
  description = "User OCID"
  type        = string

  validation {
    condition     = can(regex("^ocid1.user.oc1..*$", var.user_ocid))
    error_message = "Invalid OCID format, expected: ocid1.user.oc1..*"
  }
}
#   Populated by environment variable TF_VAR_fingerprint
variable "fingerprint" {
  description = "Fingerprint associated with RSA public key configured to profile"
  type        = string

  validation {
    condition     = can(regex("^(:?.{2})+$", var.fingerprint))
    error_message = "Invalid fingerprint format, expected: xx:xx:xx...xx"
  }
}

#   Populated by environment TF_VAR_private_key_path
variable "private_key_path" {
  description = "Path to private key"
  type        = string
  default     = "~/.oci/oci_api_key.pem"

  validation {
    condition     = can(file(var.private_key_path))
    error_message = "Private key file not found"
  }
}

#   Populated by environment variable TF_VAR_region
variable "region" {
  description = "Region identifier"
  type        = string
  # https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.region))
    error_message = "Invalid region format, expected: xx-xxxx-#, e.g. uk-london-1"
  }
}

variable "compartment_name" {
  description = "Name of compartment to house resources"
  type        = string
  default     = "homelab"
}

variable "cidr_range" {
  description = "VCN CIDR range"
  type        = string
  default     = "10.100.0.0/16"
}

variable "tags" {
  type = map(string)
  default = {
    "terraform"   = "true"
    "environment" = "homelab"
    "project"     = "homelab"
  }
}

variable "shape" {
  type = string
  # default = "VM.Standard.E2.1.Micro"
  default = "VM.Standard.A1.Flex"
}

variable "instance_count" {
  type    = number
  default = 1
}

#   Populated by environment variable TF_VAR_tailscale_api_key
variable "tailscale_api_key" {
  description = "Tailscale auth key"
  type        = string

  validation {
    condition     = length(var.tailscale_api_key) > 0
    error_message = "Tailscale API key must not be empty"
  }
}

#   Populated by environment variable TF_VAR_tailscale_tailnet
variable "tailscale_tailnet" {
  description = "Tailscale tailnet name"
  type        = string

  validation {
    condition     = length(var.tailscale_tailnet) > 0
    error_message = "Tailscale tailnet must not be empty"
  }
}

variable "public_key_path" {
  description = "Path to public SSH key"
  type        = string

  validation {
    condition     = can(file(var.public_key_path))
    error_message = "Public key file not found"
  }
}
