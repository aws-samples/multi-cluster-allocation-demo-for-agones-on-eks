variable "cluster_name" {
  description = "A EKS cluster name you deploy this module to"
  type        = string
}

variable "gameserver_namespace" {
  description = "Kubernetes namespace gameserver pods are placed into"
  default     = "default"
  type        = string
}

variable "vpc" {
}

variable "cluster_security_group_id" {
  type = string
}

variable "node_security_group_id" {
  type = string
}

variable "load_balancer_controller_module" {
  description = "Load balancer controller module. We will use it for explict dependency."
  default     = ""
}

variable "eks_cluster_addons" {
  description = "Load balancer controller module. We will use it for explict dependency."
  default     = ""
}

variable "namespace" {
  description = "Kubernetes namespace Agones pods are placed into"
  default     = "agones-system"
  type        = string
}

variable "allocator_allowed_cidrs" {
  description = "CIDRs which can access Agones allocator service (e.g. [\"1.1.1.1/32\"])"
  default     = []
  type        = list(string)
}

variable "gameserver_allowed_cidrs" {
  description = "CIDRs which can access gameservers"
  default     = ["10.0.0.0/32"]
  type        = list(string)
}
