# Ansible's Role & Expectations (From Assignment)

## What the Assignment Says About Ansible

From the case study:
> "The company currently uses Ansible as its configuration management tool. Before investing in third-party monitoring platforms, leadership prefers to **leverage the existing stack** or incorporate any cloud-native services only if they provide substantial benefits."

**Translation:** Don't buy a new tool if Ansible can do it.

---

## Ansible's Role in This Solution

### 1. **ORCHESTRATION** (Primary Role)
Ansible is the **conductor** — it defines the workflow and coordinates all steps.

**What Ansible does:**
- Defines the discovery process (run boto3 script)
- Loops through discovered VMs
- Orchestrates the execution flow (call SSM for each VM)
- Parses the output
- Pushes metrics to CloudWatch
- Handles retries and error cases

**Why Ansible?** Because it's infrastructure-as-code, idempotent, repeatable, and the team already knows it.

### 2. **NOT THE EXECUTOR** (Important Distinction)
Ansible does NOT directly SSH into VMs and run commands.

**Why not?**
- SSH key management across accounts is a nightmare
- No audit trail (CloudTrail can't see SSH)
- Slower (one connection per VM, not parallel)
- Requires open ports (security risk)

**Who executes?** AWS Systems Manager Run Command (via SSM)
- Agentless (on Windows)
- IAM-based (no keys)
- Parallel (thousands of VMs simultaneously)
- Audited (CloudTrail logs everything)

---

## Ansible's Exact Responsibilities

### Discovery Phase
```yaml
- name: Run AWS EC2 inventory discovery
  command: python aws_ec2_inventory.py
  register: discovered_vms
  # Output: List of VMs to monitor
```
**Ansible does:** Execute the discovery script, capture inventory

### Orchestration Phase
```yaml
- name: For each discovered VM
  loop: "{{ discovered_vms }}"
  block:
    # 1. Assume cross-account role
    - name: STS AssumeRole
      command: aws sts assume-role ...
      
    # 2. Call SSM API (don't execute directly, call the service)
    - name: SSM SendCommand
      amazon.aws.ssm_send_command:
        instance_ids: "{{ vm_id }}"
        document: "AWS-RunShellScript"
        command: "df -h | awk '{print $5}'"
      register: command_result
      
    # 3. Wait for completion
    - name: Wait for SSM Command
      amazon.aws.ssm_send_command:
        command_id: "{{ command_result.command_id }}"
      until: result.status == "Success"
      retries: 10
      delay: 5
      
    # 4. Parse output
    - name: Extract disk usage
      set_fact:
        disk_usage: "{{ command_result.stdout | int }}"
        
    # 5. Push to CloudWatch
    - name: Put CloudWatch metric
      amazon.aws.cloudwatch:
        metric_name: DiskUsagePercent
        value: "{{ disk_usage }}"
        
    # 6. Check thresholds
    - name: Trigger alarm if needed
      amazon.aws.sns:
        msg: "Disk usage {{ disk_usage }}% on {{ vm_id }}"
```

**Ansible does:** Orchestrate all 6 steps, handle errors, manage flow

---

## Why NOT Just Use SSM Directly?

**Question from interviewer:** "Why use Ansible at all? Can't SSM do this alone?"

**Your answer:**
"Yes, SSM can execute commands on VMs. But Ansible adds orchestration value:

1. **Infrastructure-as-Code** — Playbooks are version-controlled, repeatable, auditable
2. **Multi-step workflows** — Discover → Orchestrate → Aggregate → Alert in one reproducible flow
3. **Error handling** — Retries, conditional logic, failure notifications built-in
4. **Idempotency** — Safe to run repeatedly without side effects
5. **Existing skill** — Team already knows Ansible, no new tool to learn

Ansible is the **conductor**, SSM is the **executor**. Ansible handles the score (workflow), SSM handles the notes (actual command execution)."

---

## Ansible's Constraints (From Assignment)

The assignment says:
> "Before investing in third-party monitoring platforms, leadership prefers to leverage the existing stack"

### What This Means
✅ **Use Ansible** (it's already paid for)
❌ **Don't add** Datadog, New Relic, Splunk, etc. (licensing cost)
✅ **Use AWS services** (CloudWatch, SSM) if they're cheaper/better than third-party

### Ansible's Scope Boundary
Ansible is responsible for **orchestration only**.

What Ansible DOES manage:
- Workflow definition
- Error handling
- Scheduling/triggering
- Multi-account coordination
- Infrastructure-as-code

What Ansible DOESN'T do:
- Store credentials (IAM roles do)
- Execute SSH (SSM does)
- Aggregate metrics (CloudWatch does)
- Trigger alerts (CloudWatch alarms + SNS do)

---

## Ansible's Expectations (From Your Interview Perspective)

### What They'll Ask About Ansible

**Q: "How does Ansible fit into this?"**
A: "Ansible is the orchestration layer. It defines the workflow — discover VMs, coordinate SSM commands, parse results, push to CloudWatch. It's infrastructure-as-code, so the entire process is repeatable, auditable, and version-controlled."

**Q: "Why not use Ansible's SSH module?"**
A: "SSH would require key management across accounts, no CloudTrail audit trail, and slower execution (serial vs. parallel). SSM Run Command is better: IAM-based, parallelized, and fully audited."

**Q: "Why leverage existing Ansible instead of building a custom solution?"**
A: "Leadership directive: use existing tools before buying new ones. Ansible is already deployed, the team knows it, and it's perfect for orchestration. No need to reinvent."

**Q: "Can Ansible scale to 10,000 VMs?"**
A: "Absolutely. Ansible doesn't execute directly — it calls SSM Run Command, which parallelizes across all VMs. Ansible's job is to orchestrate the workflow, which scales linearly with the number of commands sent."

---

## What Ansible Owns vs. What It Delegates

### Ansible Owns ✅
```
├── Playbook Definition (workflow)
├── Dynamic Inventory (VM discovery)
├── Error Handling (retries, logging)
├── Cross-Account Coordination (IAM role assumption)
├── Output Parsing (metrics extraction)
├── Scheduling Integration (cron → playbook)
└── Infrastructure-as-Code (version control)
```

### Ansible Delegates ✅
```
├── Command Execution → SSM Run Command
├── Metrics Aggregation → CloudWatch
├── Alert Triggering → CloudWatch Alarms + SNS
├── Audit Logging → CloudTrail
├── Authentication → IAM Roles
└── Data Storage → CloudWatch Metrics
```

---

## Ansible's Deployment Model

### Control Node (Where Ansible Runs)
- **Location:** Private EC2 in management account
- **Runtime:** Python 3.9+ with ansible, boto3
- **Execution:** Cron job (every hour) or EventBridge trigger
- **IAM Role:** AnsibleManager (assumes cross-account roles)
- **No SSH keys:** Uses IAM for authentication

### Playbooks (What Ansible Runs)
- **Location:** GitHub (version controlled)
- **Idempotent:** Safe to run repeatedly
- **Logging:** CloudWatch Logs (from Ansible control node)
- **Error Handling:** Retries, alerts on failure
- **Parallel:** Uses Ansible's async/poll for parallel SSM commands

### Inventory (What Ansible Knows About)
- **Source:** aws_ec2_inventory.py (boto3 script)
- **Dynamic:** Discovers VMs with tag `monitoring=true`
- **Multi-account:** Cross-account role assumption per account
- **Metadata:** Instance ID, IP, region, environment, tags

---

## Interview Talking Points About Ansible

### "Ansible is the orchestration layer"
- Defines the workflow (not the execution)
- Infrastructure-as-code (version-controlled, auditable)
- Idempotent (safe to run on schedule)
- Team already knows it (no learning curve)

### "Ansible doesn't SSH into VMs"
- Uses SSM Run Command instead (more secure)
- Parallel execution (scales to 10K+ VMs)
- Full CloudTrail audit trail
- No key management complexity

### "Ansible is a force multiplier"
- Without Ansible: Write custom scripts in Lambda/Step Functions
- With Ansible: Reuse existing playbooks, leverage Ansible ecosystem
- Leadership requirement: "Use existing stack first"

### "Ansible handles the hard parts"
- Multi-account coordination (assumes roles)
- Error handling (retries, conditional logic)
- Scheduling (cron runs it hourly)
- Logging (CloudWatch Logs from control node)
- Infrastructure-as-code (GitHub integration)

---

## Ansible in the Diagram

**Add this to your architecture diagrams:**

```
┌─────────────────────────────────────────┐
│ ORCHESTRATION LAYER (Ansible)           │
│                                          │
│ Responsibilities:                       │
│ • Workflow definition                   │
│ • VM discovery coordination             │
│ • Cross-account role assumption         │
│ • Error handling & retries              │
│ • Multi-step orchestration              │
│ • Infrastructure-as-code (GitHub)       │
│                                          │
│ What it DOES:                           │
│ → Runs discovery script (boto3)         │
│ → Loops through discovered VMs          │
│ → Calls SSM API for each VM             │
│ → Parses output                         │
│ → Pushes to CloudWatch                  │
│                                          │
│ What it DOESN'T do:                     │
│ → Execute SSH commands                  │
│ → Store credentials                     │
│ → Aggregate metrics                     │
│ → Trigger alarms                        │
└─────────────────────────────────────────┘
                    ↓
         ┌─────────────────────┐
         │ SSM Run Command     │
         │ (Execution Layer)   │
         └─────────────────────┘
```

---

## Summary: Ansible's Role

| Aspect | Role |
|--------|------|
| **What It Is** | Orchestration layer (conductor, not executor) |
| **Why Use It** | Leadership constraint: "leverage existing stack" |
| **Main Job** | Define workflow, coordinate steps, handle errors |
| **Scale** | Orchestrates parallel SSM execution (10K+ VMs) |
| **Security** | IAM-based (no SSH keys), infrastructure-as-code |
| **Audit Trail** | CloudTrail logs all API calls (Ansible → SSM → EC2) |
| **Idempotency** | Safe to run repeatedly on schedule (cron/EventBridge) |
| **Team Benefit** | Leverage existing Ansible skills, no new tool learning |

---

## What to Emphasize in Interview

**"Ansible is not the star of this architecture — it's the stage manager.**

It doesn't execute commands on VMs (SSM does). It doesn't store metrics (CloudWatch does). It doesn't trigger alerts (SNS does).

What Ansible does is **orchestrate the entire workflow** — discover VMs, coordinate parallel command execution, parse results, push metrics, handle errors, retry on failure, log everything.

This is why we use it: leadership says 'use what you have,' we already have Ansible, and it's perfect for orchestration. We delegate the hard stuff (execution, storage, alerting) to AWS services that specialize in it."

That's enterprise architecture thinking.
