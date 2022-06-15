# Installs Cluster autoscaler
# https://docs.aws.amazon.com/eks/latest/userguide/autoscaling.html

data "aws_region" "current" {}

locals {
  service_account_name = "cluster-autoscaler-aws"
}

# https://artifacthub.io/packages/helm/cluster-autoscaler/cluster-autoscaler
resource "helm_release" "this" {
  name       = "cluster-autoscaler"
  namespace  = "kube-system"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"

  # Note that supecific kubernetes version is supported on each helm version
  # https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler#releases
  version          = "9.19.1"
  create_namespace = false

  set {
    name  = "awsRegion"
    value = data.aws_region.current.name
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = local.service_account_name
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.iam_assumable_role.iam_role_arn
  }

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }
}

data "aws_iam_policy_document" "this" {
  statement {
    sid = "clusterAutoscalerAll"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeInstanceTypes",
    ]
    resources = ["*"]
  }

  statement {
    sid = "clusterAutoscalerOwn"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeInstanceTypes",
      "autoscaling:UpdateAutoScalingGroup",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}"
      values   = ["owned"]
    }

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled"
      values   = ["true"]
    }
  }
}

resource "aws_iam_policy" "this" {
  policy = data.aws_iam_policy_document.this.json
}

module "iam_assumable_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "4.13.2"

  create_role      = true
  role_name_prefix = "cluster-autoscaler"
  role_description = "IRSA role for cluster autoscaler"

  provider_url                   = var.oidc_provider
  role_policy_arns               = [aws_iam_policy.this.arn]
  oidc_fully_qualified_subjects  = ["system:serviceaccount:kube-system:${local.service_account_name}"]
  oidc_fully_qualified_audiences = ["sts.amazonaws.com"]
}
