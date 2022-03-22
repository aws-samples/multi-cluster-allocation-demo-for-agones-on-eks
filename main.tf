terraform {
  required_providers {
    aws = {
      source  = "aws"
      version = "~> 3.72.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {}

data "aws_caller_identity" "current" {}

module "vpc" {
  version = "3.12.0"
  source  = "terraform-aws-modules/vpc/aws"

  name = "agones-multi-cluster-demo"
  cidr = "10.0.0.0/16"
  azs  = data.aws_availability_zones.available.names

  public_subnets  = ["10.0.0.0/18", "10.0.64.0/18", "10.0.128.0/18"]
  private_subnets = ["10.0.192.0/20", "10.0.208.0/20", "10.0.224.0/20"]

  enable_flow_log           = true
  flow_log_destination_arn  = aws_s3_bucket.log_bucket.arn
  flow_log_destination_type = "s3"

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  manage_default_security_group = true

  # Enable these to use EKS private cluster endpoint
  # https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Add tags below for subnet discovery
  # https://aws.amazon.com/premiumsupport/knowledge-center/eks-vpc-subnet-discovery/
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_s3_bucket" "log_bucket" {
  bucket_prefix = "log-bucket"
  force_destroy = true

  versioning {
    enabled = true
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket_public_access_block" "log_bucket" {
  bucket = aws_s3_bucket.log_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Allow putting access log files from elb service
resource "aws_s3_bucket_policy" "allow_elb_access_log" {
  bucket = aws_s3_bucket.log_bucket.id
  policy = templatefile("./access_log_policy.json", {
    bucket_name = aws_s3_bucket.log_bucket.bucket
    account_id  = data.aws_caller_identity.current.account_id
  })
}

module "dgs01" {
  source       = "./modules/dgs_cluster"
  cluster_name = "dgs01"
  vpc          = module.vpc

  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_allowed_cidrs
  gameserver_allowed_cidrs             = var.gameserver_allowed_cidrs
}

# We cannot use for_each or count here due to provider problem
# https://www.terraform.io/language/modules/develop/providers#legacy-shared-modules-with-provider-configurations
# https://github.com/hashicorp/terraform/issues/24476
module "dgs02" {
  source       = "./modules/dgs_cluster"
  cluster_name = "dgs02"
  vpc          = module.vpc

  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_allowed_cidrs
  gameserver_allowed_cidrs             = var.gameserver_allowed_cidrs
}

locals {
  dgs_clusters = [module.dgs01, module.dgs02]
}

module "router" {
  source       = "./modules/routing_cluster"
  vpc          = module.vpc
  cluster_name = "router"

  allocation_targets = [for dgs in local.dgs_clusters :
    {
      cluster_name         = dgs.cluster_name
      tls_crt              = dgs.allocation_service_client_tls_crt
      tls_key              = dgs.allocation_service_client_tls_key
      ca_crt               = dgs.allocation_service_server_tls_crt
      endpoint             = dgs.allocation_service_hostname
      gameserver_namespace = dgs.gameserver_namespace
    }
  ]

  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_allowed_cidrs
  allocator_allowed_cidrs              = var.agones_allocator_allowed_cidrs
}
