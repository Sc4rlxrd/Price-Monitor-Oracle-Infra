variable "region" {
  description = "Região da Oracle Cloud onde os recursos serão criados."
  type        = string
}

variable "compartment_ocid" {
  description = "OCID do compartment que receberá os recursos."
  type        = string

  validation {
    condition     = startswith(var.compartment_ocid, "ocid1.compartment.")
    error_message = "O compartment_ocid deve começar com ocid1.compartment."
  }
}

variable "project_name" {
  description = "Nome usado como prefixo nos recursos."
  type        = string
  default     = "bookcommerce"
}

variable "environment" {
  description = "Ambiente da infraestrutura."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "O environment deve ser dev, staging ou prod."
  }
}
variable "vcn_cidr_block" {
  description = "Bloco CIDR usado pela VCN."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vcn_cidr_block))
    error_message = "O vcn_cidr_block deve ser um CIDR IPv4 válido."
  }
}

variable "public_subnet_cidr_block" {
  description = "Bloco CIDR usado pela subnet pública."
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrnetmask(var.public_subnet_cidr_block))
    error_message = "O public_subnet_cidr_block deve ser um CIDR IPv4 válido."
  }
}

variable "ssh_allowed_cidrs" {
  description = "Conjunto de IPv4 públicos permitidos para acesso SSH."
  type        = set(string)

  validation {
    condition = (
      length(var.ssh_allowed_cidrs) > 0 &&
      alltrue([
        for cidr in var.ssh_allowed_cidrs :
        can(cidrnetmask(cidr))
      ])
    )

    error_message = "Todos os itens de ssh_allowed_cidrs devem ser CIDRs IPv4 válidos, normalmente IP/32."
  }
}

variable "web_allowed_cidr" {
  description = "Rede autorizada a acessar HTTP e HTTPS."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrnetmask(var.web_allowed_cidr))
    error_message = "O web_allowed_cidr deve ser um CIDR válido."
  }
}

variable "instance_shape" {
  description = "Shape da instância Compute."
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "instance_ocpus" {
  description = "Quantidade de OCPUs da instância."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_ocpus > 0
    error_message = "instance_ocpus deve ser maior que zero."
  }
}

variable "instance_memory_in_gbs" {
  description = "Quantidade de memória RAM da instância em GB."
  type        = number
  default     = 12

  validation {
    condition     = var.instance_memory_in_gbs > 0
    error_message = "instance_memory_in_gbs deve ser maior que zero."
  }
}

variable "boot_volume_size_in_gbs" {
  description = "Tamanho do volume de inicialização da VM."
  type        = number
  default     = 100

  validation {
    condition     = var.boot_volume_size_in_gbs >= 47
    error_message = "O volume de inicialização deve ter pelo menos 47 GB."
  }
}

variable "ssh_public_key_path" {
  description = "Caminho local para a chave pública usada no acesso SSH."
  type        = string

  validation {
    condition     = fileexists(pathexpand(var.ssh_public_key_path))
    error_message = "O arquivo informado em ssh_public_key_path não existe."
  }
}

variable "fault_domain_index" {
  description = "Índice do Fault Domain usado para criar a instância."
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1, 2], var.fault_domain_index)
    error_message = "fault_domain_index deve ser 0, 1 ou 2."
  }
}

variable "letsencrypt_email" {
  description = "Email usado para registrar a conta no Let's Encrypt"
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.letsencrypt_email))
    error_message = "letsencrypt_email deve conter um email válido."
  }
}

variable "letsencrypt_staging" {
  description = "Usa o ambiente de testes do Let's Encrypt"
  type        = bool
  default     = true
}