output "allocation_service_hostname" {
  value = module.router.allocation_service_hostname
}

output "allocation_service_client_tls_crt" {
  value     = module.router.allocation_service_client_tls_crt
  sensitive = true
}

output "allocation_service_client_tls_key" {
  value     = module.router.allocation_service_client_tls_key
  sensitive = true
}

output "allocation_service_server_tls_crt" {
  value     = module.router.allocation_service_server_tls_crt
  sensitive = true
}
