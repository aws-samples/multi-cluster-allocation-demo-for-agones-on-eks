terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
  }
}

data "aws_region" "current" {}

locals {
  allocator_server_cert_name = "allocator-tls-org"
  allocator_client_cert_name = "allocator-client-tls"
  # CIDRs which can access allocator service
  # those related to its VPC are allowed by default
  allocator_allowed_cidrs = concat(
    [var.vpc.vpc_cidr_block],
    [for ip in var.vpc.nat_public_ips : "${ip}/32"],
    var.allocator_allowed_cidrs,
  )
}

resource "kubernetes_namespace" "this" {
  # Agones depends on load balancer controller's finalizer
  depends_on = [var.load_balancer_controller_module, var.eks_cluster_addons]
  metadata {
    annotations = {
      name = var.namespace
    }

    name = var.namespace
  }
}

# https://artifacthub.io/packages/helm/agones/agones
resource "helm_release" "this" {
  depends_on       = [module.agones_system_node_group]
  namespace        = var.namespace
  create_namespace = false

  repository    = "https://agones.dev/chart/stable"
  name          = "agones"
  chart         = "agones"
  version       = "1.23.0"
  wait_for_jobs = true

  # Use set block for certificates as yaml multiline string is bothering
  set {
    name  = "agones.allocator.tlsCert"
    value = data.kubernetes_secret.allocator_server_cert.data["tls.crt"]
  }

  set_sensitive {
    name  = "agones.allocator.tlsKey"
    value = data.kubernetes_secret.allocator_server_cert.data["tls.key"]
  }

  set {
    // Note that the suffix of name must be .crt or .pem
    // https://github.com/googleforgames/agones/blob/fbe538013a6ebd0eaa0933fd0bc5d862ab6b8d7c/cmd/allocator/main.go#L469
    name  = "agones.allocator.clientCAs.default\\.crt"
    value = data.kubernetes_secret.allocator_client_cert.data["tls.crt"]
  }

  # https://agones.dev/site/docs/installation/install-agones/helm/#configuration
  values = [
    templatefile("${path.module}/values.yaml", {
      allocator_allowed_cidrs = local.allocator_allowed_cidrs
      gameserver_namespace    = var.gameserver_namespace
    })
  ]
}

# Creating Agones dedicated node group is recommended here
# https://agones.dev/site/docs/installation/install-agones/helm/
module "agones_system_node_group" {
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"

  name         = var.namespace
  cluster_name = var.cluster_name

  min_size               = 1
  max_size               = 10
  desired_size           = 1
  instance_types         = ["t3.large"]
  subnet_ids             = var.vpc.private_subnets
  vpc_id                 = var.vpc.vpc_id
  vpc_security_group_ids = [var.node_security_group_id]

  security_group_rules = {
    ingress_cluster_agones = {
      description              = "allow access from EKS control plane to Agones controller"
      protocol                 = "TCP"
      from_port                = 8080
      to_port                  = 8081
      type                     = "ingress"
      source_security_group_id = var.cluster_security_group_id
    }
  }

  taints = [
    {
      key    = "agones.dev/agones-system"
      value  = "true"
      effect = "NO_EXECUTE"
    }
  ]

  labels = {
    "agones.dev/agones-system" = "true"
  }

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

module "agones_gameserver_node_group" {
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"

  name         = "gameserver"
  cluster_name = var.cluster_name

  min_size       = 0
  max_size       = 30
  desired_size   = 0
  instance_types = ["c5.large"]
  # To use Graviton2, uncomment lines below.
  # Note that currently Agones does not support ARM environment, so it won't launch pods.
  # https://github.com/googleforgames/agones/issues/2216
  # ami_type = "AL2_ARM_64"
  # instance_types = ["t4g.medium"]

  subnet_ids = var.vpc.public_subnets
  vpc_id     = var.vpc.vpc_id

  vpc_security_group_ids = [var.node_security_group_id]

  # Deny executing pods other than gameserver
  taints = [
    {
      key    = "gameserver"
      value  = "true"
      effect = "NO_EXECUTE"
    }
  ]

  block_device_mappings = {
    default = {
      device_name = "/dev/xvda"
      ebs = {
        volume_size = 20
        encrypted   = true
      }
    }
  }

  security_group_rules = {
    ingress_websocket_internet = {
      description = "Allow tcp/udp access from Internet to gameserver pods"
      from_port   = 7000
      to_port     = 8000
      protocol    = "-1"
      type        = "ingress"
      cidr_blocks = var.gameserver_allowed_cidrs
    }
  }

  labels = {
    "usage" = "gameserver"
  }
}

# Tag required for Scaling from zero and Node selector
# https://docs.aws.amazon.com/eks/latest/userguide/autoscaling.html#cluster-autoscaler
resource "aws_autoscaling_group_tag" "gameserver_autoscaler" {
  autoscaling_group_name = module.agones_gameserver_node_group.node_group_resources[0].autoscaling_groups[0].name

  tag {
    key                 = "k8s.io/cluster-autoscaler/node-template/label/usage"
    value               = "gameserver"
    propagate_at_launch = false
  }
}

data "kubernetes_service" "allocation_service" {
  depends_on = [helm_release.this]
  metadata {
    name      = "agones-allocator"
    namespace = var.namespace
  }
}

module "cert_manager" {
  source = "../cert_manager"
}

data "kubectl_path_documents" "cert" {
  pattern = "${path.module}/manifests/cert.yaml"
  vars = {
    aws_region                 = data.aws_region.current.name
    namespace                  = var.namespace
    allocator_server_cert_name = local.allocator_server_cert_name
    allocator_client_cert_name = local.allocator_client_cert_name
  }
}

resource "kubectl_manifest" "cert" {
  depends_on = [module.cert_manager, kubernetes_namespace.this]
  count      = 3 # To avoid this problem https://github.com/gavinbunney/terraform-provider-kubectl/issues/58
  yaml_body  = element(data.kubectl_path_documents.cert.documents, count.index)
}

# It takes a few seconds for cert-manager to actually create secret after Certificate CRD is created.
# We will get an error if we try to access the secret before it is created, so here we will wait for seconds.
resource "time_sleep" "wait_for_cert_creation" {
  depends_on = [kubectl_manifest.cert]

  create_duration = "10s"
}

data "kubernetes_secret" "allocator_server_cert" {
  depends_on = [time_sleep.wait_for_cert_creation]
  metadata {
    name      = local.allocator_server_cert_name
    namespace = var.namespace
  }
}

data "kubernetes_secret" "allocator_client_cert" {
  depends_on = [time_sleep.wait_for_cert_creation]
  metadata {
    name      = local.allocator_client_cert_name
    namespace = var.namespace
  }
}

# HPA for allocator service
data "kubectl_path_documents" "hpa" {
  pattern = "${path.module}/manifests/hpa.yaml"
  vars = {
    namespace = var.namespace
  }
}

resource "kubectl_manifest" "hpa" {
  depends_on = [helm_release.this]
  count      = 1
  yaml_body  = element(data.kubectl_path_documents.hpa.documents, count.index)
}
