# modules/compute/outputs.tf

output "instances_created" {
  value       = huaweicloud_compute_instance.ecs[*].id
  description = "ECS 实例 ID 列表"
}
