variable "aws_region" {
  description = "AWS region you deploy this sample to"
  default     = "us-west-2"
  type        = string
}

variable "gameserver_allowed_cidrs" {
  description = "CIDRs that can access gameservers"
  default     = ["0.0.0.0/0"]
  type        = list(string)
}

variable "cluster_endpoint_allowed_cidrs" {
  description = "CIDRs that can access EKS cluster endpoint"
  default     = ["0.0.0.0/0"]
  type        = list(string)
}

variable "agones_allocator_allowed_cidrs" {
  description = "CIDRs that can access Agones allocator service"
  default     = ["0.0.0.0/0"]
  type        = list(string)
}
