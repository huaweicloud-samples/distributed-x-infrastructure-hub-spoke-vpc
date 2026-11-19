# modules/compute/main.tf — 每个 spoke VPC 内创建 N 个 ECS 实例（按 AZ 分布）

terraform {
  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = "~> 1.95"
    }
  }
}

resource "huaweicloud_compute_instance" "ecs" {
  count = var.number_azs

  name               = "${var.vpc_name}-ecs-${count.index + 1}-${var.identifier}"
  flavor_id          = var.flavor_id
  image_id           = var.image_id
  security_group_ids = [var.security_group_id]
  agency_name        = var.agency_name

  system_disk_type = "GPSSD"
  system_disk_size = 40

  network {
    uuid = var.workload_subnets[count.index]
  }

  metadata = {
    agency_name = var.agency_name
  }

  delete_disks_on_termination = true

  tags = {
    vpc       = var.vpc_name
    spoke     = var.vpc_name
    managedBy = "terraform"
  }
}
