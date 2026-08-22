terraform {
  backend "oci" {
    bucket    = "price-monitor-terraform-state"
    namespace = "gruflyzelnev"
    key       = "prod/terraform.tfstate"
    region    = "sa-saopaulo-1"
  }
}