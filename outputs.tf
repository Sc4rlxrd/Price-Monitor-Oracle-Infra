output "availability_domains" {
  description = "Domínios de disponibilidade acessíveis na região configurada."

  value = [
    for availability_domain in data.oci_identity_availability_domains.available.availability_domains :
    availability_domain.name
  ]
}