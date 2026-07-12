output "availability_domains" {
  description = "Domínios de disponibilidade acessíveis na região configurada."

  value = [
    for availability_domain in data.oci_identity_availability_domains.available.availability_domains :
    availability_domain.name
  ]
}

output "vcn_id" {
  description = "OCID da VCN do BookCommerce."
  value       = oci_core_vcn.bookcommerce.id
}

output "public_subnet_id" {
  description = "OCID da subnet pública."
  value       = oci_core_subnet.public.id
}

output "internet_gateway_id" {
  description = "OCID do Internet Gateway."
  value       = oci_core_internet_gateway.bookcommerce.id
}

output "public_route_table_id" {
  description = "OCID da route table pública."
  value       = oci_core_route_table.public.id
}

output "public_security_list_id" {
  description = "OCID da Security List da subnet pública."
  value       = oci_core_security_list.public.id
}

output "instance_id" {
  description = "OCID da instância do BookCommerce."
  value       = oci_core_instance.bookcommerce.id
}

output "instance_public_ip" {
  description = "Endereço IPv4 público da instância."
  value       = oci_core_instance.bookcommerce.public_ip
}

output "instance_private_ip" {
  description = "Endereço IPv4 privado da instância."
  value       = oci_core_instance.bookcommerce.private_ip
}

output "instance_name" {
  description = "Nome da instância."
  value       = oci_core_instance.bookcommerce.display_name
}

output "instance_image_name" {
  description = "Nome da imagem utilizada na instância."
  value       = data.oci_core_images.ubuntu.images[0].display_name
}

output "available_fault_domains" {
  description = "Fault Domains disponíveis."

  value = [
    for fault_domain in data.oci_identity_fault_domains.available.fault_domains :
    fault_domain.name
  ]
}