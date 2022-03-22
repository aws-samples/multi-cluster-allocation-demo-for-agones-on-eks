variable "oidc_provider" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "node_security_group_id" {
  type = string
}

variable "cluster_security_group_id" {
  type = string
}
