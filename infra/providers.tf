# providers.tf — 华为云 Provider 配置

terraform {
  required_version = ">= 1.5"

  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = "~> 1.95"
    }
  }
}

provider "huaweicloud" {
  region = var.region
}
