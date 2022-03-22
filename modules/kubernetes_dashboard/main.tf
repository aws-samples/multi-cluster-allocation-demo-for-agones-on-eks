terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
  }
}

# https://artifacthub.io/packages/helm/k8s-dashboard/kubernetes-dashboard
resource "helm_release" "this" {
  name             = "kubernetes-dashboard"
  namespace        = "kubernetes-dashboard"
  repository       = "https://kubernetes.github.io/dashboard/"
  chart            = "kubernetes-dashboard"
  version          = "5.2.0"
  create_namespace = true

  set {
    name  = "fullnameOverride"
    value = "kubernetes-dashboard"
  }

  set {
    name  = "metricsScraper.enabled"
    value = "true"
  }
}


data "kubectl_path_documents" "this" {
  pattern = "${path.module}/manifests/*.yaml"
}

resource "kubectl_manifest" "this" {
  depends_on = [helm_release.this]
  count      = length(data.kubectl_path_documents.this.documents)
  yaml_body  = element(data.kubectl_path_documents.this.documents, count.index)
}

# https://artifacthub.io/packages/helm/metrics-server/metrics-server
resource "helm_release" "metrics_server" {
  name             = "metrics-server"
  namespace        = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = "3.8.1"
  create_namespace = true
}

resource "aws_security_group_rule" "dashboard" {
  type                     = "ingress"
  from_port                = 8443
  to_port                  = 8443
  protocol                 = "tcp"
  security_group_id        = var.node_security_group_id
  source_security_group_id = var.cluster_security_group_id
}

resource "aws_security_group_rule" "metrics_server" {
  type                     = "ingress"
  from_port                = 4443
  to_port                  = 4443
  protocol                 = "tcp"
  security_group_id        = var.node_security_group_id
  source_security_group_id = var.cluster_security_group_id
}
