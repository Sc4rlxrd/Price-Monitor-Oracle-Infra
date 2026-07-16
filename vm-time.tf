resource "terraform_data" "configure_vm_time" {
  triggers_replace = [
    oci_core_instance.bookcommerce.id,
    oci_core_instance.bookcommerce.public_ip,
    "america-sao-paulo-v1",
  ]

  provisioner "local-exec" {
    interpreter = ["/usr/bin/env", "bash", "-c"]

    environment = {
      VM_PUBLIC_IP = oci_core_instance.bookcommerce.public_ip
    }

    command = <<-EOT
      set -Eeuo pipefail

      if [[ -z "$${SSH_AUTH_SOCK:-}" ]]; then
        echo "Erro: SSH_AUTH_SOCK não está disponível."
        echo "Execute: ssh-add ~/.ssh/bookcommerce_oracle"
        exit 1
      fi

      echo "Configurando timezone e NTP na VM $VM_PUBLIC_IP..."

      ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=20 \
        -o StrictHostKeyChecking=accept-new \
        "ubuntu@$VM_PUBLIC_IP" \
        'sudo -n timedatectl set-timezone America/Sao_Paulo &&
         sudo -n timedatectl set-ntp true &&
         echo &&
         timedatectl &&
         echo &&
         date'

      echo "Configuração de horário concluída."
    EOT

    on_failure = fail
  }
}