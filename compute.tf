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

    # Mantido como "bookcommerce" para preservar o hostname/DNS privado
    # da VNIC existente e evitar risco de substituição da VM ou da interface.
    # Alterar somente após revisar cuidadosamente o terraform plan.
    hostname_label = "bookcommerce"
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

    user_data = base64gzip(
      templatefile(
        "${path.module}/cloud-init/price-monitor.yaml.tftpl",
        {
          bootstrap_script_b64 = filebase64(
            "${path.module}/scripts/bootstrap-price-monitor.sh"
          )

          deploy_price_monitor_script_b64 = filebase64(
            "${path.module}/scripts/deploy-price-monitor.sh"
          )

          check_price_monitor_update_script_b64 = filebase64(
            "${path.module}/scripts/check-price-monitor-update.sh"
          )

          compose_yaml_b64 = filebase64(
            "${path.module}/docker/price-monitor-compose.yaml"
          )

          collector_urls_b64 = filebase64(
            "${path.module}/config/urls.txt"
          )

          nginx_bootstrap_conf_b64 = filebase64(
            "${path.module}/docker/nginx/bootstrap.conf.tftpl"
          )

          nginx_default_conf_b64 = filebase64(
            "${path.module}/docker/nginx/default.conf.tftpl"
          )

          configure_https_script_b64 = filebase64(
            "${path.module}/scripts/configure-https.sh"
          )

          reload_nginx_script_b64 = filebase64(
            "${path.module}/scripts/reload-price-monitor-nginx.sh"
          )

          run_collector_script_b64 = filebase64(
            "${path.module}/scripts/run-price-collector.sh"
          )

          collector_service_b64 = filebase64(
            "${path.module}/systemd/price-monitor-collector.service"
          )

          collector_timer_b64 = filebase64(
            "${path.module}/systemd/price-monitor-collector.timer"
          )

          update_service_b64 = filebase64(
            "${path.module}/systemd/price-monitor-update.service"
          )

          update_timer_b64 = filebase64(
            "${path.module}/systemd/price-monitor-update.timer"
          )

          monitor_script_b64 = filebase64(
            "${path.module}/monitoring/vm-monitor-telegram.sh"
          )

          monitor_service_b64 = filebase64(
            "${path.module}/monitoring/vm-monitor-telegram.service"
          )

          monitor_timer_b64 = filebase64(
            "${path.module}/monitoring/vm-monitor-telegram.timer"
          )

          dashboard_auth_username = var.dashboard_auth_username
          letsencrypt_email       = var.letsencrypt_email
          letsencrypt_staging     = var.letsencrypt_staging
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