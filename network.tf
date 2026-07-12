resource "oci_core_vcn" "bookcommerce" {
  compartment_id = var.compartment_ocid

  cidr_blocks = [
    var.vcn_cidr_block
  ]

  display_name = "${local.name_prefix}-vcn"
  dns_label    = "bookcommerce"

  freeform_tags = local.common_tags
}

resource "oci_core_internet_gateway" "bookcommerce" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.bookcommerce.id

  display_name = "${local.name_prefix}-internet-gateway"
  enabled      = true

  freeform_tags = local.common_tags
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.bookcommerce.id

  display_name = "${local.name_prefix}-public-route-table"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.bookcommerce.id
    description       = "Route public traffic through the Internet Gateway"
  }

  freeform_tags = local.common_tags
}

resource "oci_core_subnet" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.bookcommerce.id

  cidr_block   = var.public_subnet_cidr_block
  display_name = "${local.name_prefix}-public-subnet"
  dns_label    = "public"

  route_table_id = oci_core_route_table.public.id

  security_list_ids = [
    oci_core_security_list.public.id
  ]

  prohibit_public_ip_on_vnic = false

  freeform_tags = local.common_tags
}