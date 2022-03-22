# Install Fluent Bit
# https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-setup-logs-FluentBit.html

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
  service_account_name = "fluent-bit"
}

# https://github.com/aws/amazon-cloudwatch-logs-for-fluent-bit#permissions
data "aws_iam_policy_document" "this" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
      "logs:PutRetentionPolicy",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "this" {
  policy = data.aws_iam_policy_document.this.json
}

module "iam_assumable_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "4.13.2"

  create_role      = true
  role_name_prefix = "fluent-bit-"
  role_description = "IRSA role for fluentBit"

  provider_url                   = var.oidc_provider
  role_policy_arns               = [aws_iam_policy.this.arn]
  oidc_fully_qualified_subjects  = ["system:serviceaccount:${var.namespace}:${local.service_account_name}"]
  oidc_fully_qualified_audiences = ["sts.amazonaws.com"]
}

resource "kubernetes_namespace" "this" {
  metadata {
    annotations = {
      name = var.namespace
    }

    name = var.namespace
  }
}

data "kubectl_path_documents" "this" {
  pattern = "${path.module}/manifests/*.yaml"
  vars = {
    cluster_name         = var.cluster_name
    aws_region           = data.aws_region.current.name
    role_arn             = module.iam_assumable_role.iam_role_arn
    namespace            = var.namespace
    service_account_name = local.service_account_name
    hash                 = filesha256("${path.module}/manifests/fluent_bit.yaml")
  }
}

# https://github.com/gavinbunney/terraform-provider-kubectl/issues/58
data "kubectl_path_documents" "dummy" {
  pattern = "${path.module}/manifests/*.yaml"
  vars = {
    cluster_name         = "dummy"
    aws_region           = "dummy"
    role_arn             = "dummy"
    namespace            = "dummy"
    service_account_name = "dummy"
    hash                 = "dummy"
  }
}

resource "kubectl_manifest" "this" {
  depends_on = [kubernetes_namespace.this]
  count      = length(data.kubectl_path_documents.dummy.documents)
  yaml_body  = element(data.kubectl_path_documents.this.documents, count.index)
}
