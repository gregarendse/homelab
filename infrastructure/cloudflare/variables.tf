variable "cloudflare_api_token" {
  description = "The API token for your Cloudflare account."
  type        = string
  sensitive   = true
  nullable    = false
}

variable "domain_name" {
  description = "The domain name to be managed by Cloudflare."
  type        = string
  nullable    = false
}

# S3 Backend Configuration Variables
variable "s3_backend_access_key" {
  description = "S3 backend access key"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "s3_backend_secret_key" {
  description = "S3 backend secret key"
  type        = string
  sensitive   = true
  nullable    = false
}

variable "s3_backend_bucket" {
  description = "S3 backend bucket name"
  type        = string
  default     = "gregarendse-terraform"
}

