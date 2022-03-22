variable "vpc" {
}

variable "cluster_name" {
  type = string
}

variable "gameserver_namespace" {
  default = "default"
  type    = string
}

variable "cluster_endpoint_public_access_cidrs" {
  default = ["0.0.0.0/0"]
  type    = list(string)
}

variable "gameserver_allowed_cidrs" {
  description = "CIDRs which can access Agones allocator service (e.g. [\"1.1.1.1/32\"])"
  default     = ["0.0.0.0/0"]
  type        = list(string)
}

variable "allocator_allowed_cidrs" {
  description = "CIDRs which can access gameservers"
  default     = []
  type        = list(string)
}
