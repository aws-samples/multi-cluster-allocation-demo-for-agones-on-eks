output "allocation_service_hostname" {
  value = data.kubernetes_service.allocation_service.status.0.load_balancer.0.ingress.0.hostname
}

output "allocation_service_client_tls_crt" {
  value = base64encode(data.kubernetes_secret.allocator_client_cert.data["tls.crt"])
}

output "allocation_service_client_tls_key" {
  value     = base64encode(data.kubernetes_secret.allocator_client_cert.data["tls.key"])
  sensitive = true
}

output "allocation_service_server_tls_crt" {
  value = base64encode(data.kubernetes_secret.allocator_server_cert.data["tls.crt"])
}

output "gameserver_iam_role_name" {
  value = module.agones_gameserver_node_group.iam_role_name
}
