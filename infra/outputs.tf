# outputs.tf — 关键输出

output "vpcs" {
  description = "VPC ID 集合"
  value = {
    shared_services = huaweicloud_vpc.shared_services.id
    spoke           = { for k, v in huaweicloud_vpc.spoke : k => v.id }
  }
}

output "enterprise_router" {
  description = "企业路由器信息"
  value = {
    id = huaweicloud_er_instance.main.id
    route_tables = {
      spoke           = huaweicloud_er_route_table.spoke.id
      shared_services = huaweicloud_er_route_table.shared_services.id
    }
  }
}

output "compute_instances" {
  description = "ECS 实例 ID 集合"
  value = {
    for k, m in module.compute : k => m.instances_created
  }
}

output "vpc_endpoints" {
  description = "VPC 终端节点 ID 集合"
  value       = { for k, v in huaweicloud_vpcep_endpoint.shared : k => v.id }
}

output "private_zones" {
  description = "内网 DNS 域名 ID 集合"
  value       = { for k, z in huaweicloud_dns_zone.endpoint : k => z.id }
}

output "kms_key_id" {
  description = "日志加密 KMS 密钥 ID"
  value       = huaweicloud_kms_key.log_key.id
}

output "lts_log_group" {
  description = "VPC Flow Log LTS 日志组 ID"
  value       = huaweicloud_lts_group.flow_log.id
}

output "ecs_agency_name" {
  description = "ECS 实例委托名称"
  value       = huaweicloud_identity_agency.ecs.name
}
