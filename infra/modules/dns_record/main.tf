# modules/dns_record/main.tf — 针对单个 VPCEP 内网域名的多条 A 记录集

terraform {
  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = "~> 1.95"
    }
  }
}


resource "huaweicloud_dns_recordset" "endpoint" {
  for_each = toset(var.record_names)

  zone_id     = var.zone_id
  name        = each.value == "" ? var.zone_name : "${each.value}.${var.zone_name}."
  type        = "A"
  ttl         = 300
  description = "A record pointing to shared services VPC endpoint"

  records = var.endpoint_ips
}
