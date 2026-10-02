terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.26.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3"
    }
  }
}

# This root manages OCI; never inherit a work-cluster current-context.
provider "helm" {
  kubernetes = {
    config_path    = var.kubeconfig_path
    config_context = "oci"
  }
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = "oci"
}
