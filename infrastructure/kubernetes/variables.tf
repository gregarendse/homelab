variable "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  type        = string
  default     = "~/.kube/config"

  validation {
    condition     = can(file(var.kubeconfig_path))
    error_message = "Kubeconfig file not found at the specified path"
  }
}
