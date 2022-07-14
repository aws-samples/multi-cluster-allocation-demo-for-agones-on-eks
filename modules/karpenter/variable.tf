variable "cluster_name" {
  type = string
}

variable "cluster_id" {
  type = string
}

variable "cluster_endpoint" {
  description = "Cluster endpoint"
  default     = ""
  type        = string
}

variable "iam_role_arn" {
  type = string
}

variable "iam_role_name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}