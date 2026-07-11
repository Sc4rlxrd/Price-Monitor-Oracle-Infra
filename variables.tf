variable "region" {
  description = "Região da Oracle Cloud onde os recursos serão criados."
  type        = string
}

variable "compartment_ocid" {
  description = "OCID do compartment que receberá os recursos."
  type        = string
  sensitive   = true

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