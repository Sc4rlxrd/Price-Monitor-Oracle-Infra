resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.bookcommerce.id

  display_name = "${local.name_prefix}-public-security-list"

  # Permite que a VM acesse internet, registries, atualizações,
  # GitHub Container Registry e demais serviços externos.
  egress_security_rules {
    protocol         = "all"
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    stateless        = false

    description = "Allow all outbound IPv4 traffic"
  }

  # SSH disponível somente pelo IP definido no terraform.tfvars.
  ingress_security_rules {
    protocol    = "6"
    source      = var.ssh_allowed_cidr
    source_type = "CIDR_BLOCK"
    stateless   = false

    description = "Allow SSH from the administrator public IP"

    tcp_options {
      min = 22
      max = 22
    }
  }

  # HTTP público para o Traefik/K3s.
  ingress_security_rules {
    protocol    = "6"
    source      = var.web_allowed_cidr
    source_type = "CIDR_BLOCK"
    stateless   = false

    description = "Allow public HTTP traffic"

    tcp_options {
      min = 80
      max = 80
    }
  }

  # HTTPS público para TLS futuro.
  ingress_security_rules {
    protocol    = "6"
    source      = var.web_allowed_cidr
    source_type = "CIDR_BLOCK"
    stateless   = false

    description = "Allow public HTTPS traffic"

    tcp_options {
      min = 443
      max = 443
    }
  }

  ingress_security_rules {
    protocol    = "1"
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    stateless   = false

    description = "Allow ICMP fragmentation needed messages"

    icmp_options {
      type = 3
      code = 4
    }
  }

  # Permite mensagens de erro de conectividade dentro da VCN.
  ingress_security_rules {
    protocol    = "1"
    source      = var.vcn_cidr_block
    source_type = "CIDR_BLOCK"
    stateless   = false

    description = "Allow ICMP destination unreachable inside the VCN"

    icmp_options {
      type = 3
    }
  }
  freeform_tags = local.common_tags
}