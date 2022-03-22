output "allocation_service_hostname" {
  value = module.agones.allocation_service_hostname
}

output "allocation_service_client_tls_crt" {
  value = module.agones.allocation_service_client_tls_crt
}

output "allocation_service_client_tls_key" {
  value = module.agones.allocation_service_client_tls_key
}

output "allocation_service_server_tls_crt" {
  value = module.agones.allocation_service_server_tls_crt
}

output "namespace" {
  value = var.namespace
}
