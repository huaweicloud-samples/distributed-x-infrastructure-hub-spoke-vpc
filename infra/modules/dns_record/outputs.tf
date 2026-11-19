# modules/dns_record/outputs.tf

output "recordset_ids" {
  value       = { for k, v in huaweicloud_dns_recordset.endpoint : k => v.id }
  description = "记录集 ID 集合"
}
