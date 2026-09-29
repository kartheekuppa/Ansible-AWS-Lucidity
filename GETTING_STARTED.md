# Getting Started with Disk Monitoring Solution

This guide walks you through setting up the disk monitoring solution in your AWS environment.

## Quick Start (5 minutes)

### 1. Clone the Repository
```bash
git clone https://github.com/kartheekuppa/Ansible-AWS-Lucidity.git
cd Ansible-AWS-Lucidity
```

### 2. Install Dependencies
```bash
pip install -r requirements.txt
chmod +x inventory/aws_ec2_inventory.py
```

### 3. Set AWS Credentials
```bash
export AWS_PROFILE=your-management-account
export AWS_REGION=us-east-1
export AWS_EXTERNAL_ID=$(openssl rand -hex 16)  # Generate a secure external ID

# Save it for later
echo "AWS_EXTERNAL_ID=$AWS_EXTERNAL_ID" > .env.local
```

### 4. Deploy IAM Roles (Terraform)
```bash
cd terraform

# Initialize Terraform
terraform init

# Preview changes
terraform plan \
  -var="management_account=111111111111" \
  -var="child_accounts=[222222222222,333333333333]" \
  -var="external_id=$AWS_EXTERNAL_ID"

# Deploy
terraform apply \
  -var="management_account=111111111111" \
  -var="child_accounts=[222222222222,333333333333]" \
  -var="external_id=$AWS_EXTERNAL_ID" \
  -var="alert_email=your-email@example.com"

cd ..
```

### 5. Tag Your EC2 Instances
```bash
# Tag instances in each account
aws ec2 create-tags \
  --resources i-1234567890abcdef0 i-0987654321fedcba0 \
  --tags Key=monitoring,Value=true Key=environment,Value=prod \
  --region us-east-1
```

### 6. Test Discovery
```bash
python inventory/aws_ec2_inventory.py --list
```

### 7. Run the Playbook
```bash
# Dry run (check mode)
ansible-playbook playbooks/collect_disk_metrics.yml --check

# Full execution
ansible-playbook playbooks/collect_disk_metrics.yml -v
```

## Detailed Setup Guide

### Understanding the Components

| Component | Purpose |
|-----------|---------|
| **aws_ec2_inventory.py** | Discovers EC2 instances tagged with `monitoring=true` |
| **collect_disk_metrics.yml** | Orchestrates disk check, metrics push, and alerting |
| **Terraform IAM Setup** | Creates roles for cross-account access |

### Step-by-Step Setup

#### Step 1: Prerequisites
- AWS CLI v2 configured
- Ansible 2.9+ installed
- Python 3.8+ with boto3
- Terraform 1.0+
- Permissions to create IAM roles and EC2 instance tags

#### Step 2: IAM Role Setup (One-Time)

The Terraform code creates:
1. **AnsibleManager** role in your management account
   - Assumes roles in child accounts
   - Protected by external ID

2. **AnsibleExecutor** roles in child accounts
   - Allows SSM, CloudWatch, EC2 API calls
   - Trusts only AnsibleManager role

```bash
cd terraform
terraform apply -var-file=vars.tfvars
```

Save the output role ARNs for reference.

#### Step 3: Network Configuration

Ensure your Ansible control node (or your workstation) can reach AWS APIs:
- **Option A**: Run from EC2 in private subnet with VPC endpoints
- **Option B**: Run from on-premises with VPN/AWS PrivateLink
- **Option C**: Run from public internet (less secure)

For best security, use VPC endpoints:
```bash
# Create VPC endpoint for SSM
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-12345678 \
  --service-name com.amazonaws.us-east-1.ssm \
  --vpc-endpoint-type Interface \
  --subnet-ids subnet-12345678
```

#### Step 4: Inventory Configuration

The discovery script finds instances automatically using tags:

```bash
# Tag instances for monitoring
aws ec2 create-tags \
  --resources i-xxxxx i-yyyyy \
  --tags Key=monitoring,Value=true
```

Test discovery:
```bash
python inventory/aws_ec2_inventory.py --list
```

Expected output:
```json
{
  "all": {
    "hosts": {
      "i-12345678.prod": {
        "ansible_host": "i-12345678",
        "ansible_connection": "aws_ssm"
      }
    }
  },
  "_meta": {
    "hostvars": {
      "i-12345678.prod": {
        "instance_id": "i-12345678",
        "environment": "prod",
        "account_id": "222222222222"
      }
    }
  }
}
```

#### Step 5: Run the Playbook

**Dry Run (Test Mode)**
```bash
ansible-playbook playbooks/collect_disk_metrics.yml --check
```

**Full Execution**
```bash
ansible-playbook playbooks/collect_disk_metrics.yml -v
```

**With Specific Hosts**
```bash
ansible-playbook playbooks/collect_disk_metrics.yml -i hosts.ini
```

#### Step 6: Verify Results

Check CloudWatch metrics:
```bash
aws cloudwatch list-metrics \
  --metric-name DiskUsagePercent \
  --namespace CustomMetrics
```

View a specific metric:
```bash
aws cloudwatch get-metric-statistics \
  --metric-name DiskUsagePercent \
  --namespace CustomMetrics \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-02T00:00:00Z \
  --period 3600 \
  --statistics Average
```

Check SNS alerts:
```bash
aws sns list-subscriptions-by-topic --topic-arn arn:aws:sns:us-east-1:111111111111:DiskUsageAlerts
```

#### Step 7: Schedule with Cron or EventBridge

**Option A: Cron (Simple)**
```bash
# Add to crontab
0 * * * * cd /path/to/repo && ansible-playbook playbooks/collect_disk_metrics.yml >> logs/cron.log 2>&1
```

**Option B: EventBridge (Recommended)**
```bash
# Create EventBridge rule
aws events put-rule \
  --name disk-metrics-hourly \
  --schedule-expression "rate(1 hour)" \
  --state ENABLED

# Target Lambda that runs the playbook
aws events put-targets \
  --rule disk-metrics-hourly \
  --targets "Id"="1","Arn"="arn:aws:lambda:us-east-1:111111111111:function:RunAnsiblePlaybook"
```

## Troubleshooting

### Discovery returns no instances
```bash
# Check if instances are properly tagged
aws ec2 describe-instances --filters "Name=tag:monitoring,Values=true"

# Verify IAM permissions
aws iam get-role-policy --role-name AnsibleManager --policy-name AnsibleManagerPolicy
```

### SSM commands fail
```bash
# Check SSM agent on instance
aws ssm describe-instance-information --filters "Key=tag:monitoring,Values=true"

# View command details
aws ssm get-command-invocation --command-id cmd-xxxxx --instance-id i-xxxxx
```

### CloudWatch metrics not appearing
```bash
# Verify the metric exists
aws cloudwatch describe-alarms --alarm-names DiskUsageAlerts

# Check CloudWatch Logs
aws logs tail /ansible/disk-metrics --follow
```

### Cross-account role assumption fails
```bash
# Verify trust relationship
aws iam get-role --role-name AnsibleExecutor

# Test role assumption manually
aws sts assume-role \
  --role-arn arn:aws:iam::222222222222:role/AnsibleExecutor \
  --external-id $AWS_EXTERNAL_ID \
  --role-session-name test
```

## Next Steps

1. **Read the full documentation**
   - `docs/ARCHITECTURE.md` - System design
   - `docs/ANSIBLE-ROLE.md` - Ansible responsibilities
   - `docs/NETWORK-SECURITY.md` - Security architecture

2. **Customize for your environment**
   - Adjust disk thresholds in playbook
   - Add more metrics (inode, filesystem types)
   - Integrate with your monitoring dashboard

3. **Scale to all instances**
   - Tag all production instances
   - Monitor the playbook execution time
   - Optimize parallel execution

4. **Production hardening**
   - Add auto-remediation (cleanup scripts)
   - Implement metrics retention policies
   - Set up dashboard in CloudWatch
   - Configure alerting thresholds

## Support & Questions

Refer to:
- **Architecture questions** → `docs/ARCHITECTURE.md`
- **Interview prep** → `docs/INTERVIEW-QA.md`
- **AWS vs Azure** → `docs/AWS-vs-AZURE.md`
- **GitHub issues** → Open an issue in the repo

---

**Ready to deploy?** Start with Step 1 above or jump to the README for full details.
