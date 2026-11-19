# modules/dns_record/variables.tf

variable "zone_id" {
  type        = string
  description = "内网域名 Zone ID"
}

variable "zone_name" {
  type        = string
  description = "内网域名 FQDN（如 obs.cn-north-4.myhuaweicloud.com）"
}

variable "endpoint_ips" {
  type        = list(string)
  description = "VPCEP 内网解析地址列表（A 记录值）"
}

variable "record_names" {
  type        = list(string)
  description = "记录名称集合（空字符串代表 zone 根域）"
}
