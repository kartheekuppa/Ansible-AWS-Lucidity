# Lucidity Solutions Architect — Interview Prep Guide

## 1. The Case Study at a Glance

**Scenario:** Multi-cloud enterprise (AWS/Azure/GCP) with growth through acquisitions needs a scalable, secure disk monitoring solution to prevent downtime.

**Key Constraint:** Prefer leveraging existing Ansible stack; cloud-native services only if they provide *substantial benefits*.

**Your Task:** Design ONE cloud provider solution covering:
- Access management across multi-account environments
- Disk utilization data collection & aggregation
- Scalability for growth
- Minimal working code with architecture diagram

**Deliverables:**
1. High-level architectural diagram
2. Ansible playbooks/roles demonstrating key components
3. Documentation with GitHub repo link

---

## 2. Recommended Approach: AWS (Aligns with Your Strengths)

### Why AWS?
- **Ecosystem maturity:** CloudWatch, Systems Manager, IAM role delegation are production-grade
- **Cross-account access:** AWS resource-based policies and role chaining handle multi-account complexity elegantly
- **Ansible integration:** Well-established, native boto3 support
- **Scalability:** Tags-based auto-discovery fits enterprise growth patterns

---

## 3. Solution Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────┐
│                    Management Account (Central)              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Ansible Control Node                                │   │
│  │  - Inventory discovery script (boto3)                │   │
│  │  - Playbook execution engine                         │   │
│  │  - Aggregation & alerting logic                      │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Centralized Monitoring Stack                        │   │
│  │  - CloudWatch (metrics aggregation)                  │   │
│  │  - SNS (alerts)                                      │   │
│  │  - S3 (metrics history)                              │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                         ▲
         ┌───────────────┼───────────────┐
         │               │               │
    ┌─────────┐   ┌─────────┐   ┌─────────┐
    │ AWS Acc │   │ AWS Acc │   │ AWS Acc │
    │    1    │   │    2    │   │    3    │
    │  (Prod) │   │  (Dev)  │   │ (Staging)
    │         │   │         │   │         │
    │ ┌─────┐ │   │ ┌─────┐ │   │ ┌─────┐ │
    │ │ VM1 │ │   │ │ VM3 │ │   │ │ VM5 │ │
    │ ├─────┤ │   │ ├─────┤ │   │ ├─────┤ │
    │ │ VM2 │ │   │ │ VM4 │ │   │ │ VM6 │ │
    │ └─────┘ │   │ └─────┘ │   │ └─────┘ │
    └─────────┘   └─────────┘   └─────────┘
```

### Key Components

**1. Access Management**
- **Cross-account IAM roles** with external ID for security
  - Centralized role: `AnsibleCrossAccountDiskMonitor` in management account
  - Trust relationships from child accounts
  - Assume role via Ansible (boto3 sts:AssumeRole)
  
- **Principle of least privilege:**
  - `ec2:DescribeInstances`, `ec2:DescribeTags` (discovery)
  - `ssm:SendCommand`, `ssm:GetCommandInvocation` (metric collection)
  - `cloudwatch:PutMetricData` (data push)

**2. Data Collection Pipeline**
- **Discovery:** Boto3 dynamic inventory script → tags-based filtering
- **Collection:** AWS Systems Manager Session Manager + Run Command
  - Agentless on Windows (default)
  - SSM Agent on Linux (lightweight)
  - Execute `df -h` or `Get-Volume` via Run Command
  - Parse output, push to CloudWatch custom metrics
  
- **Aggregation:** CloudWatch dashboards + SNS alerts
  - Threshold alerts (>85% disk usage)
  - Historical trends stored in S3 for compliance

**3. Scalability**
- **Auto-enrollment:** New VMs tagged with `monitoring: true` auto-discovered
- **Distributed collection:** Run Command executes in parallel across all VMs
- **Modular playbooks:** Role-based structure allows easy expansion (add new cloud, add metrics)

---



---

## 4. Ansible Playbook Structure (What to Code)

### File Layout
```
lucidity-disk-monitoring/
├── README.md
├── ansible.cfg
├── inventories/
│   ├── aws_ec2.yml          # Dynamic inventory plugin
│   └── group_vars/
│       └── all.yml          # Common vars (regions, threshold)
├── roles/
│   ├── prerequisites/        # Install SSM agent (if needed)
│   ├── disk_collector/       # Main data collection logic
│   ├── metrics_aggregator/   # CloudWatch push
│   └── alerting/             # SNS notification setup
├── playbooks/
│   ├── discover_vms.yml      # Initial inventory scan
│   ├── collect_metrics.yml   # Run the collection job
│   └── setup_monitoring.yml  # Full setup
└── templates/
    ├── disk_check.sh         # Linux metric collection
    └── disk_check.ps1        # Windows metric collection
```

### Minimal Playbook Example to Demo

```yaml
---
- name: Collect Disk Metrics from AWS VMs
  hosts: all
  gather_facts: no
  
  tasks:
    - name: Use AWS Systems Manager to collect disk data
      amazon.aws.ssm_send_command:
        document_name: "AWS-RunShellScript"
        instance_ids: "{{ ansible_host }}"
        parameters:
          command:
            - "df -h | tail -n +2 | awk '{print $5}' | sed 's/%//' | sort -rn | head -1"
      register: disk_output
      
    - name: Parse and push to CloudWatch
      amazon.aws.cloudwatch_metric_alarm:
        metric_name: "DiskUsagePercent"
        namespace: "CustomMonitoring"
        dimensions:
          InstanceId: "{{ ansible_host }}"
        value: "{{ disk_output.stdout | int }}"
        unit: "Percent"
      when: disk_output.stdout | int > 85
```

---



## 9. Why This Solution Fits Lucidity's Philosophy

Lucidity is about **autonomous optimization without disruption**. Your solution demonstrates:
- **Minimal touch:** Ansible + existing infrastructure
- **Autonomous discovery:** VM discovery via tags (self-healing)
- **Non-disruptive:** SSM Run Command requires no reboots, no downtime
- **Cost-conscious:** Leverages existing services (no licensing cost)
- **Enterprise-grade:** Security, audit trails, multi-account support

This mirrors how Lucidity sells its own product—as an intelligent, hands-off layer on top of existing infrastructure.

---

