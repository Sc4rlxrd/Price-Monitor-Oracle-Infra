data "oci_identity_availability_domains" "available" {
  compartment_id = var.compartment_ocid
}
data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = var.instance_shape

  sort_by    = "TIMECREATED"
  sort_order = "DESC"
}

data "oci_identity_fault_domains" "available" {
  availability_domain = data.oci_identity_availability_domains.available.availability_domains[0].name
  compartment_id      = var.compartment_ocid
}