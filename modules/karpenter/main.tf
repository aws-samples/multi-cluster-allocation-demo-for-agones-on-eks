terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
  }
}

resource "aws_iam_instance_profile" "karpenter" {
  name = "KarpenterNodeInstanceProfile-${var.cluster_name}"
  role = var.iam_role_name
}

module "karpenter_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.0.0"

  role_name                          = "karpenter-controller-${var.cluster_name}"
  attach_karpenter_controller_policy = true

  karpenter_tag_key               = "karpenter.sh/discovery/${var.cluster_name}"
  karpenter_controller_cluster_id = var.cluster_id
  karpenter_controller_node_iam_role_arns = [
    var.iam_role_arn
  ]

  oidc_providers = {
    ex = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["karpenter:karpenter"]
    }
  }
}

resource "helm_release" "this" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "https://charts.karpenter.sh"
  chart      = "karpenter"
  version    = "v0.13.2"

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.karpenter_irsa.iam_role_arn
  }

  set {
    name  = "clusterName"
    value = var.cluster_id
  }

  set {
    name  = "clusterEndpoint"
    value = var.cluster_endpoint
  }

  set {
    name  = "aws.defaultInstanceProfile"
    value = aws_iam_instance_profile.karpenter.name
  }
}

data "kubectl_path_documents" "karpenter_provisioner" {
  pattern = "${path.module}/manifests/provisioner.yaml"
  vars = {
    cluster_id        = var.cluster_id
    public_subnet_ids = join(",", var.public_subnet_ids)
  }
}

resource "kubectl_manifest" "karpenter_provisioner" {
  depends_on = [helm_release.this]
  yaml_body = <<YAML
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
metadata:
  name: default
spec:
  requirements:
    - key: "kubernetes.io/arch"
      operator: In
      values: ["arm64"]
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["on-demand", "spot"]
  limits:
    resources:
      cpu: 100
  providerRef:
    name: default
  ttlSecondsAfterEmpty: 30
YAML
}

resource "kubectl_manifest" "karpenter_aws_node_template" {
  depends_on = [helm_release.this]
  yaml_body = <<YAML
apiVersion: karpenter.k8s.aws/v1alpha1
kind: AWSNodeTemplate
metadata:
  name: default
spec:
  subnetSelector:
    aws-ids: ${join(",", var.public_subnet_ids)}
  securityGroupSelector:
    karpenter.sh/discovery/${var.cluster_id}: ${var.cluster_id}
  tags:
    karpenter.sh/discovery/${var.cluster_id}: ${var.cluster_id}
YAML
}