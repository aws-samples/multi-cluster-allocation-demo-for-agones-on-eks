# Install AWS Distro for OpenTelemetry
# used for ingesting metrics including Agones to CloudWatch Metrics
# https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-EKS-otel.html

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
  service_account_name = "aws-otel-sa"
}

data "aws_iam_policy" "CloudWatchAgentServerPolicy" {
  arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

module "iam_assumable_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "4.13.2"

  create_role      = true
  role_name_prefix = "aws-otel-"
  role_description = "IRSA role for AWS Distro for OpenTelemetry"

  provider_url                   = var.oidc_provider
  role_policy_arns               = [data.aws_iam_policy.CloudWatchAgentServerPolicy.arn]
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
    role_arn             = module.iam_assumable_role.iam_role_arn
    namespace            = var.namespace
    service_account_name = local.service_account_name
    cluster_name         = var.cluster_name
    hash                 = filesha256("${path.module}/manifests/otel.yaml")
  }
}

# https://github.com/gavinbunney/terraform-provider-kubectl/issues/58
data "kubectl_path_documents" "dummy" {
  pattern = "${path.module}/manifests/*.yaml"
  vars = {
    role_arn             = ""
    namespace            = ""
    service_account_name = ""
    cluster_name         = ""
    hash                 = ""
  }
}

resource "kubectl_manifest" "this" {
  depends_on = [kubernetes_namespace.this]
  count      = length(data.kubectl_path_documents.dummy.documents)
  yaml_body  = element(data.kubectl_path_documents.this.documents, count.index)
}
