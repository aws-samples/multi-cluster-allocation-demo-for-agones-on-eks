terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.eks.token
  }
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
  load_config_file       = false
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_cluster_auth
data "aws_eks_cluster" "eks" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "eks" {
  name = module.eks.cluster_id
}

resource "aws_kms_key" "this" {
  description         = "KMS key for cluster encryption: ${var.cluster_name}"
  enable_key_rotation = true
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "18.8.1"

  cluster_version = "1.22"
  cluster_name    = var.cluster_name
  vpc_id          = var.vpc.vpc_id
  subnet_ids      = var.vpc.private_subnets
  enable_irsa     = true

  cluster_endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs
  cluster_endpoint_private_access      = true

  cluster_encryption_config = [{
    provider_key_arn = aws_kms_key.this.arn
    resources        = ["secrets"]
  }]

  # contro plane logging https://docs.aws.amazon.com/eks/latest/userguide/control-plane-logs.html
  cluster_enabled_log_types = ["audit", "api", "authenticator", "controllerManager", "scheduler"]

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  eks_managed_node_group_defaults = {
    block_device_mappings = {
      default = {
        device_name = "/dev/xvda"
        ebs = {
          volume_size = 20
          encrypted   = true
        }
      }
    }
  }

  node_security_group_additional_rules = {
    "ingress_all" = {
      type      = "ingress"
      from_port = 0
      to_port   = 65535
      protocol  = "-1"
      self      = true
    }

    "egress_all" = {
      type      = "egress"
      from_port = 0
      to_port   = 65535
      protocol  = "-1"
      self      = true
    }
  }

  eks_managed_node_groups = {
    default = {
      desired_size = 1
      # ami_type       = "AL2_ARM_64"
      # instance_types = ["t4g.medium"]
      instance_types = ["t3.medium"]
      subnet_ids     = var.vpc.private_subnets
    }
  }
}

module "cluster_autoscaler" {
  source = "../cluster_autoscaler"

  oidc_provider = module.eks.oidc_provider
  cluster_name  = module.eks.cluster_id
}

module "fluent_bit" {
  source = "../fluent_bit"

  oidc_provider = module.eks.oidc_provider
  cluster_name  = module.eks.cluster_id
}

module "aws_otel" {
  source = "../aws_otel"

  oidc_provider = module.eks.oidc_provider
  cluster_name  = module.eks.cluster_id
}

module "load_balancer_controller" {
  source     = "../load_balancer_controller"
  depends_on = [module.eks.eks_managed_node_groups]

  oidc_provider             = module.eks.oidc_provider
  cluster_name              = module.eks.cluster_id
  vpc_id                    = var.vpc.vpc_id
  node_security_group_id    = module.eks.node_security_group_id
  cluster_security_group_id = module.eks.cluster_security_group_id
}

module "kubernetes_dashboard" {
  source                    = "../kubernetes_dashboard"
  node_security_group_id    = module.eks.node_security_group_id
  cluster_security_group_id = module.eks.cluster_security_group_id
}

module "agones" {
  source = "../agones"

  cluster_name                    = module.eks.cluster_id
  vpc                             = var.vpc
  node_security_group_id          = module.eks.node_security_group_id
  cluster_security_group_id       = module.eks.cluster_security_group_id
  load_balancer_controller_module = module.load_balancer_controller
  eks_cluster_addons              = module.eks.cluster_addons
  allocator_allowed_cidrs         = var.allocator_allowed_cidrs
}

data "kubectl_file_documents" "this" {
  content = templatefile("${path.module}/manifests/routing.yaml", {
    allocation_targets = var.allocation_targets
    namespace          = var.namespace
  })
}

resource "kubectl_manifest" "this" {
  depends_on = [module.agones]
  count      = length(var.allocation_targets) * 2
  yaml_body  = element(data.kubectl_file_documents.this.documents, count.index)
}
