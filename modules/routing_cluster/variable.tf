variable "vpc" {
}

variable "cluster_name" {
  type = string
}

variable "namespace" {
  description = "Kubernetes namespace to place GameServerAllocationPolicy into"
  type        = string
  default     = "default"
}

variable "allocation_targets" {
  type = list(object({
    cluster_name         = string
    tls_crt              = string
    tls_key              = string
    ca_crt               = string
    endpoint             = string
    gameserver_namespace = string
  }))
}

variable "cluster_endpoint_public_access_cidrs" {
  default = ["0.0.0.0/0"]
  type    = list(string)
}

variable "allocator_allowed_cidrs" {
  default = []
  type    = list(string)
}
