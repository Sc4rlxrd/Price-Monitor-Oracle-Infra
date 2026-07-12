resource "oci_core_instance" "bookcommerce" {
  availability_domain = data.oci_identity_availability_domains.available.availability_domains[0].name
  compartment_id      = var.compartment_ocid

  display_name = "${local.name_prefix}-vm"
  shape        = var.instance_shape

  # Shapes Flex permitem configurar OCPUs e memória.
  # Shapes fixas, como a E2.1.Micro, não recebem este bloco.
  dynamic "shape_config" {
    for_each = endswith(var.instance_shape, ".Flex") ? [1] : []

    content {
      ocpus         = var.instance_ocpus
      memory_in_gbs = var.instance_memory_in_gbs
    }
  }

  create_vnic_details {
    subnet_id = oci_core_subnet.public.id

    assign_public_ip = true
    display_name     = "${local.name_prefix}-vnic"
    hostname_label   = "bookcommerce"
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id

    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  metadata = {
    ssh_authorized_keys = file(
      pathexpand(var.ssh_public_key_path)
    )

    user_data = base64encode(
      templatefile(
        "${path.module}/cloud-init/wordpress.yaml.tftpl",
        {
          bootstrap_script_b64 = filebase64(
            "${path.module}/scripts/bootstrap-wordpress.sh"
          )

          compose_yaml_b64 = filebase64(
            "${path.module}/docker/wordpress-compose.yaml"
          )
        }
      )
    )
  }
  lifecycle {
    ignore_changes = [
      metadata["user_data"]
    ]
  }

  preserve_boot_volume = false

  freeform_tags = local.common_tags
}