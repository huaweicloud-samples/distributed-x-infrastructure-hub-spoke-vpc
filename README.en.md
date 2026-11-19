# distributed-x-infrastructure-hub-spoke-vpc / Hub-and-Spoke 网络架构 + 共享服务 VPC 最佳实践

[![License](https://img.shields.io/badge/License-MIT%20No%20Attribution-blue.svg)](LICENSE)
[![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-IAM%20Auth-red.svg)](https://support.huaweicloud.com/intl/en-us/)
[![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen.svg)](#)

> Best practice for Huawei Cloud Hub-and-Spoke Network Architecture (Terraform)
> Huawei Cloud Hub-and-Spoke Network Architecture with Shared Services VPC

---

## 1. Overview

This practice provides a complete Terraform deployment plan for **Hub-and-Spoke network architecture + centralized shared services VPC** on Huawei Cloud, covering VPC interconnection, VPC Endpoints (VPCEP), VPC Flow Logs, private DNS resolution, and hybrid DNS (inbound and outbound). Targeted at network architects / cloud platform operators / backend engineers, it serves as a reference architecture for multi-VPC interconnection, a hybrid cloud access learning sample, and a production network template.

### Core Capabilities

- **Multi-VPC full interconnection**: Spoke VPCs connect to shared services VPC through Enterprise Router (ER)
- **Centralized VPCEP**: Expose Huawei Cloud native services (OBS / SMN / CES / DNS) as private endpoints within shared services VPC
- **Private DNS resolution**: Each VPCEP service has a dedicated Private Zone with A records pointing to the VPCEP internal IP
- **VPC Flow Logs**: Each VPC enables flow logs and uniformly sends them to an LTS log group
- **Hybrid DNS**: Outbound Resolver Rule forwards specific domain resolution requests to on-premises DNS servers; inbound is handled by self-built DNS instances
- **Security group conventions**: Four categories — instance / endpoint / DNS inbound / DNS outbound — with fine-grained access rules
- **IAM agency**: ECS instances bind an agency to automatically gain CES + OBS access permissions

---

## 2. Table of Contents

- [1. Overview](#1-overview)
- [2. Table of Contents](#2-table-of-contents)
- [3. Architecture Diagram](#3-architecture-diagram)
- [4. Solution Highlights](#4-solution-highlights)
- [5. Cloud Services Involved](#5-cloud-services-involved)
- [6. Prerequisites](#6-prerequisites-critical)
- [7. Quick Start](#7-quick-start-critical)
- [8. Step-by-Step Deployment](#8-step-by-step-deployment)
- [9. Usage / Verification](#9-usage--verification-critical)
- [10. Cleanup](#10-cleanup)
- [11. Detailed Description](#11-detailed-description)
- [12. Dependencies](#12-dependencies)
- [13. FAQ / Troubleshooting](#13-faq--troubleshooting)
- [14. Contribution Guide](#14-contribution-guide)
- [15. License](#15-license-critical)
- [16. Contact / Maintainers](#16-contact--maintainers-critical)

---

## 3. Architecture Diagram

> Build a hub-and-spoke network topology through Enterprise Router + Shared Services VPC + multiple Spoke VPCs

```
                On-Premises Data Center (on_premises_cidr)
                DNS Server: 192.168.x.x
                          │
                          │ (DNS query)
                          ▼
        ┌──────────────────────────────────────┐
        │   Shared Services VPC (10.129.0.0/24)│
        │  ┌────────────────────────────────┐  │
        │  │ VPCEP: OBS / SMN / CES / DNS  │  │
        │  │ DNS Private Zones × 4          │  │
        │  │ DNS Resolver Rule (outbound)   │  │
        │  │ LTS Log Group (VPC Flow target)│  │
        │  └────────────────────────────────┘  │
        └──────────────────┬───────────────────┘
                           │ (ER attachment)
                           ▼
            ┌──────────────────────────────┐
            │   Enterprise Router (ER)     │
            │   - Route Table rt-spoke     │
            │   - Route Table rt-shared-   │
            │     services                 │
            │   - Propagation (bidirectional│
            │     auto-learning)           │
            └──────────────┬───────────────┘
                           │ (ER attachment)
              ┌────────────┴────────────┐
              ▼                          ▼
    ┌─────────────────────┐    ┌─────────────────────┐
    │ Spoke VPC-1         │    │ Spoke VPC-2         │
    │ (10.0.0.0/24)       │    │ (10.0.1.0/24)       │
    │ ┌─────────────────┐ │    │ ┌─────────────────┐ │
    │ │ ECS × N (per AZ)│ │    │ │ ECS × N (per AZ)│ │
    │ └─────────────────┘ │    │ └─────────────────┘ │
    │ VPC Flow Log        │    │ VPC Flow Log        │
    └─────────────────────┘    └─────────────────────┘
```

**Key Component Description**:

- **Enterprise Router (ER)**: Transit connection for all VPCs, supporting bidirectional automatic route learning
- **Shared Services VPC**: Centralized exposure of VPCEP and DNS, the "destination" for all spokes
- **Spoke VPC**: Business workload VPC, each containing ECS and Flow Log
- **VPCEP**: Private endpoints for Huawei Cloud native services exposed from shared services VPC

---

## 4. Solution Highlights

- **Declarative orchestration**: All VPCs / subnets / ER attachments / route propagation / VPCEP / DNS are explicitly declared in Terraform, avoiding module-nested black boxes
- **Reusable modules**: `modules/compute` and `modules/dns_record` are independent modules that can be reused in new spokes
- **Multi-AZ default deployment**: By default each resource is deployed across 2 AZs for high availability
- **Fine-grained security groups**: Four categories — instance / endpoint / DNS inbound / DNS outbound — each with explicit rules
- **Hybrid DNS support**: Outbound DNS forwarding rules are declared as Terraform variables; pair with self-built DNS instances on the on-premises side to enable bidirectional resolution
- **Unified logging**: Flow Logs from all VPCs go to the same LTS log group for centralized query

---

## 5. Cloud Services Involved

| Service | Purpose | Notes |
|---|---|---|
| Virtual Private Cloud (VPC) | Network isolation | Multiple VPCs (shared services + spoke × N) |
| Subnet | VPC network segmentation | Workload / transit / endpoint three categories |
| Enterprise Router (ER) | Inter-VPC connectivity | Single instance across 2 AZs |
| Elastic Cloud Server (ECS) | Workload | One per spoke per AZ |
| Key Management Service (KMS) | Log encryption key | pending_days = 7 |
| Log Tank Service (LTS) | Flow Log target | log_group + log_stream |
| VPC Endpoint (VPCEP) | Private service exposure | OBS / SMN / CES / DNS |
| Domain Name Service (DNS) | Internal DNS + forwarding rules | private zone + recordset + resolver_rule |
| Identity and Access Management (IAM) | Agency authorization | ECS agency + project roles |

> All services can be created through this repository's Terraform in one go. For cleanup, see [Section 10 "Cleanup"](#10-cleanup).

---

## 6. Prerequisites [CRITICAL]

| Item | Requirement | Description |
|---|---|---|
| **Account** | Huawei Cloud account activated and verified | Personal or enterprise accounts |
| **Permissions** | IAM **Tenant Administrator** or equivalent | Required to create VPC / ER / ECS / KMS / IAM resources |
| **Region** | Recommended `cn-north-4` | Cross-region may have service availability differences |
| **Availability Zones** | At least 2 AZs in the region | Default uses `cn-north-4a`, `cn-north-4b` |
| **Terraform** | `>= 1.5.0` | IaC deployment tool |
| **huaweicloud Provider** | `~> 1.95` | Huawei Cloud Terraform Provider (filesystem_mirror configured locally) |
| **AK/SK** | Get Access Key ID and Secret Access Key from Huawei Cloud "My Credentials" page and pass to deployment script | **Do not** write credentials into any code or config file |

---

## 7. Quick Start [CRITICAL]

### One-Click Deployment (Recommended)

```bash
# 1. Clone this repository
git clone <this repository HTTPS URL> distributed-x-infrastructure-hub-spoke-vpc
cd distributed-x-infrastructure-hub-spoke-vpc

# 2. Configure credentials (see prerequisites)
export HW_ACCESS_KEY="<AK>"
export HW_SECRET_KEY="<SK>"

# 3. One-click deployment
cd infra
terraform init
terraform plan
terraform apply -auto-approve
```

> **Deployment Duration**: Approximately 5-15 minutes (depending on number of spoke VPCs and AZs)
> **Complete Steps and Expected Output**: See [Section 8 "Step-by-Step Deployment"](#8-step-by-step-deployment)

---

## 8. Step-by-Step Deployment

### Step 1: Initialize Working Directory

```bash
cd distributed-x-infrastructure-hub-spoke-vpc/infra
terraform init
```

**Expected Output**: `Terraform has been successfully initialized!`

### Step 2: Customize Variables (Optional)

Edit `infra/variables.tf`, modify as needed:

- `region`: Huawei Cloud region
- `identifier`: Project identifier
- `vpcs`: Spoke VPC definition (CIDR / workload subnets / ECS flavor etc.)
- `shared_services_vpc`: Shared services VPC configuration
- `on_premises_cidr`: On-premises CIDR
- `forwarding_rules`: Outbound DNS forwarding rules

### Step 3: Preview Resource Changes

```bash
terraform plan
```

**Expected Output**: `Plan: N to add, 0 to change, 0 to destroy.`

### Step 4: Execute Deployment

```bash
terraform apply -auto-approve
```

**Expected Output**: `Apply complete! Resources: N added, 0 changed, 0 destroyed.`

### Step 5: Record Key Outputs

```bash
terraform output
```

**Expected Output**: Lists all `output` field values (VPC ID, ER ID, ECS ID, VPCEP ID, Zone ID, KMS Key ID, LTS Group ID, ECS agency name). Please save them for subsequent verification.

---

## 9. Usage / Verification [CRITICAL]

> **Validation Note**: This practice has passed `terraform validate` and `terraform fmt -check`, confirming the configuration is valid and properly formatted. Please follow the steps in this section to verify yourself, and only consider the delivery complete after confirming business functionality works.

### Verification 1: Terraform Syntax Validation

```bash
cd distributed-x-infrastructure-hub-spoke-vpc/infra
terraform validate
```

**Expected Output**: `Success! The configuration is valid.`

### Verification 2: Terraform Formatting Validation

```bash
cd distributed-x-infrastructure-hub-spoke-vpc/infra
terraform fmt -check -recursive
```

**Expected Output**: No output, exit code 0

### Verification 3: View Resource Dependencies

```bash
cd distributed-x-infrastructure-hub-spoke-vpc/infra
terraform providers
```

**Expected Output**:

```
Providers required by configuration:
.
├── provider[registry.terraform.io/huaweicloud/huaweicloud] ~> 1.95
├── module.compute
│   └── provider[registry.terraform.io/huaweicloud/huaweicloud] ~> 1.95
└── module.endpoint_record
    └── provider[registry.terraform.io/huaweicloud/huaweicloud] ~> 1.95
```

### Verification 4: View Key Outputs

```bash
terraform output
```

**Expected Result**: Lists all output values, including VPC IDs, ER ID, ECS IDs, VPCEP IDs, private zone IDs etc.

### Verification 5: Business End-to-End (After Deployment)

```bash
# 1. Log in to spoke ECS via ECS console
# 2. Test OBS access within ECS (through VPCEP)
curl -I https://obs.cn-north-4.myhuaweicloud.com

# 3. Test CES agent reporting (agent is auto-configured through agency)
# 4. Test internal DNS resolution
nslookup obs.cn-north-4.myhuaweicloud.com <internal DNS IP>
```

**Expected Result**:

- `curl` returns 403 or 200 (indicating OBS domain is resolvable, OBS VPCEP works)
- `nslookup` returns the VPCEP internal IP (indicating internal DNS resolution works)

---

## 10. Cleanup

```bash
# Enter deployment directory
cd distributed-x-infrastructure-hub-spoke-vpc/infra

# Release all resources in one go
terraform destroy -auto-approve
```

**Expected Output**: `Destroy complete! Resources: N destroyed.`

> **Avoid Resource Residue**:
>
> - `terraform destroy` only releases resources tracked in Terraform state
> - If you created resources directly via API during deployment (e.g., manually uploaded OBS objects, manually created EIPs in console), you need to release them manually
> - KMS Key deletion has a 7-day waiting period (`pending_days = "7"`), during which it remains in "Pending deletion" state
> - Shared resources (NAT / VPC shared with other tasks in the account) are not affected

---

## 11. Detailed Description

### Workflow

The complete lifecycle from request to business completion in this practice:

1. **Network Construction**: Declare all VPCs / subnets / ER attachments / route propagations / route tables / static routes
2. **Security Group Orchestration**: Create instance security group for each spoke, associate VPCEP security group + DNS inbound/outbound security groups
3. **Centralized Service Exposure**: Create 4 VPCEP (OBS / SMN / CES / DNS) in shared services VPC
4. **Internal DNS Resolution**: Create private zone for each VPCEP service, associate all VPCs; A records point to VPCEP internal IP
5. **Hybrid DNS**: Outbound resolver_rule forwards domain resolution requests from `forwarding_rules` to on-premises DNS
6. **IAM Agency**: Create ECS agency with CES + OBS permissions
7. **ECS Deployment**: Create ECS instances in each spoke in each AZ, bind instance security group + ECS agency
8. **VPC Flow Log**: Enable Flow Log for each VPC, uniformly send to LTS log group

### Configuration Items

| Variable | Default | Description |
|---|---|---|
| `region` | `cn-north-4` | Huawei Cloud region |
| `identifier` | `hubspoke-shared-services` | Project identifier |
| `availability_zones` | `[cn-north-4a, cn-north-4b, cn-north-4c]` | Availability zone list |
| `vpcs` | 2 spoke VPCs | Spoke VPC definitions |
| `shared_services_vpc.cidr_block` | `10.129.0.0/24` | Shared services VPC CIDR |
| `shared_services_vpc.number_azs` | `2` | Number of AZs for shared services VPC |
| `on_premises_cidr` | `192.168.0.0/16` | On-premises CIDR |
| `forwarding_rules` | 2 forwarding rules | Outbound DNS forwarding rules |

### Interfaces / APIs

This practice exposes key resource IDs through the following outputs:

```bash
terraform output vpcs                # VPC ID collection
terraform output enterprise_router    # ER ID + route table IDs
terraform output compute_instances    # ECS ID collection
terraform output vpc_endpoints       # VPCEP ID collection
terraform output private_zones       # Private zone ID collection
terraform output kms_key_id          # KMS Key ID
terraform output lts_log_group       # LTS log group ID
terraform output ecs_agency_name     # ECS instance agency name
```

---

## 12. Dependencies

### Main Dependencies

| Name | Version | Purpose |
|---|---|---|
| Terraform | `>= 1.5.0` | IaC orchestration |
| huaweicloud Provider | `~> 1.95` | Huawei Cloud resources |
| Huawei Cloud IAM | — | Agency authorization |

### Module Dependencies

| Module | Path | Purpose |
|---|---|---|
| `modules/compute` | `./infra/modules/compute` | Create ECS instances (per spoke × per AZ × 1) |
| `modules/dns_record` | `./infra/modules/dns_record` | Create DNS recordsets for VPCEP services |

---

## 13. FAQ / Troubleshooting

### Q1: Deployment shows "Insufficient Permissions". What to do?

**A**: Confirm the account has IAM **Tenant Administrator** permission, or at least includes `VPC Administrator`, `ER Administrator`, `ECS Administrator`, `KMS Administrator`, `IAM Administrator`, `LTS Administrator`, `DNS Administrator`, `VPCEP Administrator` and other sub-service administrator permissions.

### Q2: terraform init fails, prompts unable to access registry?

**A**: This repository depends on a local filesystem_mirror (path `<local provider-mirror dir>/provider-mirror`), need to set environment variable `TF_CLI_CONFIG_FILE=<local provider-mirror dir>/tfcli.hcl`. If local mirror is not available, you need to configure network proxy or private registry yourself.

### Q3: terraform apply reports DNS resolver rule endpoint_id error?

**A**: Current code's `endpoint_id` points to secgroup (placeholder), needs to be replaced with the actual endpoint_id of the self-built DNS instance in shared services VPC. See `docs/deployment-guide.md` §3.4 for details.

### Q4: ECS creation fails, prompts image not found?

**A**: Default uses public image `CentOS 7.9 64bit`. If region doesn't support it, modify the `image_name` field in `infra/variables.tf` to an image name available in that region (e.g., `Ubuntu 22.04 server 64bit`).

### Q5: How does on-premises data center connect to Huawei Cloud DNS?

**A**: This practice does not include VPN / Direct Connect deployment. Deploy a DNS forwarder on the on-premises data center side, point Huawei Cloud domains to be resolved (e.g., `*.cn-north-4.myhuaweicloud.com`) to Huawei Cloud internal DNS (100.125.0.2 / 100.125.1.2), or use self-built DNS instances in shared services VPC after VPN/direct connection is established.

### Troubleshooting Checklist

| Symptom | Possible Cause | Troubleshooting |
|---|---|---|
| `terraform init` fails | Cannot access registry | Set `TF_CLI_CONFIG_FILE` pointing to filesystem_mirror |
| VPCEP service_id is null | Region has no corresponding VPCEP service | Check `data.huaweicloud_vpcep_services` output |
| ECS startup fails | Image ID / flavor does not exist | Use `data.huaweicloud_compute_flavors` to query available flavors |
| Flow Log has no data | LTS topic lacks permissions | Check whether IAM agency has LTS write permission |
| Hybrid DNS does not work | Self-built DNS instance not deployed / endpoint_id not replaced | See `docs/deployment-guide.md` §4 |

---

## 14. Contribution Guide

Issues and PRs are welcome. Please follow this workflow:

1. **Issue**: Describe problem / suggestion (including reproduction commands, expected / actual output, screenshots)
2. **PR**: Create a feature branch based on `main` branch; run `terraform validate` and `terraform fmt -check` before submission
3. **Code Review**: Merge after review approval by **[@dgc-git](https://github.com/dgc-git)** reviewer

---

## 15. License [CRITICAL]

This practice is published under the **MIT No Attribution** license. See repository root [`LICENSE`](LICENSE) file for details.

```
MIT No Attribution

Copyright (c) Huawei Cloud

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software... (no attribution required)
```

---

## 16. Contact / Maintainers [CRITICAL]

| Item | Content |
|---|---|
| **Creator** | [@dgc-git](https://github.com/dgc-git) |
| **Maintainer** | [@dgc-git](https://github.com/dgc-git) |
| **Contact** | GitHub Issues / PR (see [Section 14](#14-contribution-guide)) |
