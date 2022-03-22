variable "cluster_name" {
  type = string
}

variable "oidc_provider" {
  type = string
}

variable "namespace" {
  type    = string
  default = "aws-otel"
}
