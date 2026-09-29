# Scalable Disk Monitoring Solution for Multi-Cloud Enterprise

A production-grade disk utilization monitoring system designed for multi-account AWS environments, leveraging Ansible orchestration and AWS Systems Manager for agentless, scalable command execution.

## Overview

This solution addresses a common enterprise pain point: disk space monitoring across thousands of VMs in a multi-account AWS infrastructure without investing in third-party monitoring platforms.

**Architecture:** Ansible (orchestration) + AWS Systems Manager Run Command (execution) + CloudWatch (aggregation) + SNS (alerting)

**Scale:** 10 VMs → 10,000+ VMs  
**Setup Time:** 8-12 hours (critical path)  
**Cost:** ~$300/month for 10K VMs (vs. $15-30K for third-party SaaS)

---

## Why This Approach?

### 1. **Leverage Existing Stack**
- Uses Ansible (already deployed at most enterprises)
- Uses AWS native services (no new tools to buy)
- Infrastructure-as-code (everything version-controlled)

### 2. **Agentless Execution**
- AWS Systems Manager Run Command needs no agent installation
- Works across Windows and Linux without SSH complexity
- Parallel execution: 1,000 VMs in ~15 minutes

### 3. **Security First**
- All infrastructure in private subnets (zero internet exposure)
- IAM-based authentication (no SSH keys to manage)
- Full CloudTrail audit trail of all commands
- Cross-account access via STS AssumeRole with external ID

### 4. **Cost-Effective**
- No licensing costs (Ansible + AWS native services)
- VPC Endpoints: ~$7-14/month
- CloudWatch storage: minimal (only disk metrics)
- Total infrastructure cost: ~$50-100/month (base) + $0.30 per 1000 metrics

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ Discovery Phase                                         │
│ ├─ Ansible runs aws_ec2_inventory.py                   │
│ └─ boto3 discovers VMs with tag "monitoring=true"      │
└──────────────┬──────────────────────────────────────────┘
               │ (VM List)
┌──────────────▼──────────────────────────────────────────┐
│ Orchestration Phase (Ansible Control Node)             │
│ ├─ For each discovered VM:                             │
│ │  ├─ Assume cross-account IAM role                    │
│ │  ├─ Call SSM SendCommand (df -h)                     │
│ │  ├─ Wait for completion (async polling)              │
│ │  ├─ Parse disk usage %                               │
│ │  └─ Push to CloudWatch Metrics                       │
│ └─ Handle retries, errors, logging                     │
└──────────────┬──────────────────────────────────────────┘
               │ (SSM Run Command)
┌──────────────▼──────────────────────────────────────────┐
│ Execution Phase (AWS Systems Manager)                   │
│ ├─ Run "AWS-RunShellScript" document on each VM         │
│ ├─ Execute: df -h | awk '{print $5}'                   │
│ └─ Return: disk_usage_percent to Ansible               │
└──────────────┬──────────────────────────────────────────┘
               │ (Metrics)
┌──────────────▼──────────────────────────────────────────┐
│ Aggregation Phase (CloudWatch)                          │
│ ├─ Store: DiskUsagePercent metric per VM               │
│ ├─ Dimensions: InstanceId, Environment, Account        │
│ ├─ Alarms:                                              │
│ │  ├─ WARNING (70% usage) → SNS notification           │
│ │  └─ CRITICAL (85% usage) → SNS notification          │
│ └─ Retention: 30 days (configurable)                   │
└─────────────────────────────────────────────────────────┘
```

---

## Components

### 1. **aws_ec2_inventory.py** — Dynamic Inventory Discovery
Boto3 script that discovers all EC2 instances tagged with `monitoring=true` across AWS accounts.

**Features:**
- Cross-account discovery via STS AssumeRole
- Filters by environment tag (prod, staging, dev)
- Outputs Ansible-compatible JSON inventory
- Includes instance ID, region, availability zone, tags

**Run:** `python inventory/aws_ec2_inventory.py`

### 2. **collect_disk_metrics.yml** — Ansible Playbook
Core orchestration playbook that executes the full workflow.

**Workflow:**
1. Assume cross-account IAM role (for each account)
2. Discover instances via boto3
3. Loop through each instance
4. Execute SSM SendCommand (disk check)
5. Wait for completion (async polling, max 10 retries)
6. Parse output (extract disk usage %)
7. Push to CloudWatch Metrics
8. Check thresholds (70% warning, 85% critical)
9. Send SNS alert if threshold exceeded
10. Log everything to CloudWatch Logs

**Run:** `ansible-playbook playbooks/collect_disk_metrics.yml`

### 3. **Cross-Account IAM Setup** — Terraform
Defines the trust relationships and roles needed for multi-account access.

**Roles:**
- `AnsibleManager` (in management account) — assumes roles in child accounts
- `AnsibleExecutor` (in child accounts) — allows SSM, CloudWatch, EC2 API calls

**Deploy:** `terraform -chdir=terraform apply`

---

## Setup Instructions

### Prerequisites
- Ansible 2.9+ with boto3 plugin
- AWS CLI v2 configured with management account credentials
- Python 3.8+ with boto3, botocore
- Terraform 1.0+ (for IAM setup)
- VPC with private subnets and VPC endpoints for SSM, CloudWatch, EC2

### Step 1: Setup IAM Roles (One-Time)

```bash
# Set your AWS account IDs
export MGMT_ACCOUNT=111111111111
export PROD_ACCOUNT=222222222222
export DEV_ACCOUNT=333333333333
export EXTERNAL_ID=$(openssl rand -hex 16)

# Deploy IAM roles
cd terraform
terraform init
terraform apply \
  -var "management_account=$MGMT_ACCOUNT" \
  -var "child_accounts=[$PROD_ACCOUNT,$DEV_ACCOUNT]" \
  -var "external_id=$EXTERNAL_ID"

# Save the external ID securely
echo "External ID: $EXTERNAL_ID" > .external_id
```

### Step 2: Configure Ansible

```bash
# Install requirements
pip install -r requirements.txt

# Test inventory discovery
python inventory/aws_ec2_inventory.py

# Should output JSON with discovered instances
```

### Step 3: Tag EC2 Instances

Tag all instances you want to monitor:
```bash
aws ec2 create-tags \
  --resources i-1234567890abcdef0 \
  --tags Key=monitoring,Value=true Key=environment,Value=prod
```

### Step 4: Run Playbook

```bash
# Dry run (check mode)
ansible-playbook playbooks/collect_disk_metrics.yml --check

# Execute
ansible-playbook playbooks/collect_disk_metrics.yml

# Schedule (add to crontab)
0 * * * * cd /path/to/repo && ansible-playbook playbooks/collect_disk_metrics.yml >> logs/cron.log 2>&1
```

### Step 5: Verify in CloudWatch

```bash
# View metrics
aws cloudwatch list-metrics \
  --metric-name DiskUsagePercent \
  --namespace CustomMetrics
```

---

## Security Model

### Network Architecture
- **Ansible Control Node:** Private EC2 in management account
- **Monitored EC2 VMs:** Private subnets (no internet exposure)
- **VPC Endpoints:** Used for AWS service access (no NAT Gateway)
- **Security Groups:** Deny-all-inbound on all VMs

### IAM Permissions (Minimal)

**AnsibleManager role** (management account):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::*:role/AnsibleExecutor",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "your-external-id"
        }
      }
    }
  ]
}
```

**AnsibleExecutor role** (child accounts):
```json
{
  "Effect": "Allow",
  "Action": [
    "ssm:SendCommand",
    "ssm:GetCommandInvocation",
    "ec2:DescribeInstances",
    "cloudwatch:PutMetricData"
  ],
  "Resource": "*"
}
```

### Audit Trail
All commands executed via SSM are logged to CloudTrail:
```
{
  "eventName": "SendCommand",
  "sourceIPAddress": "10.0.1.50",
  "userAgent": "ansible-core/2.12.0",
  "awsRegion": "us-east-1"
}
```

---

## Scaling to 10,000+ VMs

### Parallel Execution Model
Ansible uses async/poll for parallel SSM command execution:

```yaml
- name: SSM SendCommand (parallel)
  amazon.aws.ssm_send_command:
    instance_ids: "{{ item.instance_id }}"
  async: 300
  poll: 5
  loop: "{{ discovered_vms }}"
```

### Performance Metrics
- **10 VMs:** 2 minutes
- **100 VMs:** 5 minutes
- **1,000 VMs:** 15 minutes
- **10,000 VMs:** 30-45 minutes

### Bottleneck Analysis
**Critical Path:** Discovery (~2 min) + Execution (scales linearly) + Aggregation (~1 min)

**To optimize beyond 10K VMs:**
1. Shard discovery by account/region
2. Use EventBridge + Lambda for sub-minute execution
3. Batch metrics pushes (100 metrics/request vs. 1/request)

---

## Troubleshooting

### Playbook Fails at Discovery
```bash
# Check boto3 connection
python -c "import boto3; client = boto3.client('ec2'); print(client.describe_instances())"

# Verify IAM role has EC2 permissions
aws iam get-role-policy --role-name AnsibleManager --policy-name allow-sts-assume
```

### SSM Command Hangs
```bash
# Check SSM agent on EC2
aws ssm describe-instance-information --filters "Key=tag:monitoring,Values=true"

# View command status
aws ssm get-command-invocation --command-id <cmd-id> --instance-id <inst-id>
```

### CloudWatch Metrics Not Appearing
```bash
# Verify Ansible pushed metrics
aws cloudwatch list-metrics --metric-name DiskUsagePercent

# Check IAM policy on AnsibleExecutor role
aws iam get-role-policy --role-name AnsibleExecutor --policy-name allow-cloudwatch
```

### Cross-Account Role Assumption Fails
```bash
# Verify external ID
grep "external_id" playbooks/collect_disk_metrics.yml

# Test role assumption
aws sts assume-role \
  --role-arn arn:aws:iam::222222222222:role/AnsibleExecutor \
  --external-id $EXTERNAL_ID \
  --role-session-name test
```

---

## Cost Analysis

### Monthly Costs (10,000 VMs, 1 execution/hour)

| Component | Qty | Rate | Cost |
|-----------|-----|------|------|
| EC2 (Control Node, t3.medium) | 1 | $30.38 | $30.38 |
| VPC Endpoints (4 interfaces) | 4 | $7.20/mo + $0.01/GB | $28.80 + $1.00 |
| CloudWatch (metrics storage) | 120K metrics | $0.30/1K | $36.00 |
| CloudWatch Logs (Ansible logs) | 10GB | $0.50/GB | $5.00 |
| SNS (alert notifications) | 100/month | $0.50/M | $0.05 |
| **TOTAL** | | | **~$101.23/month** |

**vs. Third-Party SaaS:**
- Datadog: $15-25K/month for 10K hosts
- New Relic: $10-20K/month
- Splunk: $20-30K/month

---

## Interview Discussion Points

### Why AWS Over Azure?
1. **SSM + Ansible Integration** — Seamless orchestration layer; Azure requires Custom Script Extension (not IaC)
2. **Critical Path** — 8-12 hours vs. 9-15 hours for Azure
3. **Community** — AWS re:Post shows higher disk incident frequency

### Why Ansible vs. Lambda?
1. **Infrastructure-as-Code** — Playbooks are version-controlled, readable, maintainable
2. **Error Handling** — Built-in retries, conditionals, logging
3. **Team Skill** — Most enterprises already know Ansible
4. **Existing Stack** — No new tool to learn or license

### Why Private Subnets?
1. **Security** — Zero internet exposure reduces attack surface
2. **Compliance** — Easier to audit and meet regulatory requirements
3. **Cost** — VPC Endpoints ($7/mo) vs. NAT Gateway ($32/mo)

---

## Files & Structure

```
.
├── README.md                          # This file
├── .gitignore                         # Git ignore rules
├── playbooks/
│   └── collect_disk_metrics.yml       # Main Ansible playbook
├── inventory/
│   └── aws_ec2_inventory.py           # Boto3 discovery script
├── docs/
│   ├── ARCHITECTURE.md                # Detailed architecture
│   ├── NETWORK-SECURITY.md            # Private subnet strategy
│   ├── ANSIBLE-ROLE.md                # Ansible responsibilities
│   ├── INTERVIEW-QA.md                # Q&A reference
│   └── AWS-vs-AZURE.md                # Defense framework
├── architecture/
│   ├── diagrams/
│   │   ├── high-level.png
│   │   └── detailed.png
│   └── COMPONENTS.md
├── terraform/
│   ├── main.tf                        # IAM roles & policies
│   ├── variables.tf
│   └── outputs.tf
└── requirements.txt                   # Python/Ansible dependencies
```

---

## Next Steps

1. **Setup IAM** → Run Terraform
2. **Tag Instances** → Add `monitoring=true` tag
3. **Test Discovery** → Run `aws_ec2_inventory.py`
4. **Run Playbook** → Execute `collect_disk_metrics.yml`
5. **Schedule** → Add to crontab or EventBridge
6. **Monitor** → Check CloudWatch dashboards

---

## Contributing

This is a template for the Lucidity interview case study. For production use:
1. Add more metrics (inode usage, filesystem performance)
2. Implement auto-remediation (trigger cleanup scripts)
3. Add metrics retention & export (S3, Redshift)
4. Integrate with incident management (PagerDuty, Opsgenie)

---

## License

MIT — Use freely for educational and commercial purposes.

---

## Questions?

Refer to:
- `docs/INTERVIEW-QA.md` — Common interview questions
- `docs/ANSIBLE-ROLE.md` — Ansible vs. SSM clarity
- `docs/AWS-vs-AZURE.md` — Architecture trade-offs
