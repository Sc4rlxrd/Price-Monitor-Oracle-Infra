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

variable "ssh_allowed_cidr" {
  description = "Endereço público autorizado a acessar a VM por SSH."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.ssh_allowed_cidr))
    error_message = "O ssh_allowed_cidr deve ser um CIDR válido, normalmente SEU_IP/32."
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