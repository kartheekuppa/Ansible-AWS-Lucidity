# Lucidity Solutions Architect Interview — Quick Q&A Guide

Use this as a reference during prep. Each answer should take 1-2 minutes to deliver verbally.

---

## Technical Questions

### Q: "Walk us through your solution architecture"

**30-second answer:**
"I'd choose AWS for this use case. The architecture has three layers:

1. **Discovery Layer** — Python script using boto3 discovers EC2 instances across accounts via tags (`monitoring: true`). Cross-account access via IAM role assumption with external ID for security.

2. **Collection Layer** — Ansible orchestrates data collection using AWS Systems Manager Run Command (agentless, auditable, no SSH keys). Executes `df -h` on each VM, parses disk utilization percentages.

3. **Aggregation Layer** — Metrics pushed to CloudWatch custom metrics with dimensions (InstanceId, Environment, Account). SNS alerts trigger when usage exceeds thresholds (70% warning, 85% critical)."

**Diagram (verbal):**
"Ansible in the management account → assumes roles in child accounts → SSM Run Command executes on VMs in parallel → metrics pushed back to CloudWatch → dashboard + alerts."

---

### Q: "Why AWS Systems Manager instead of SSH/Ansible direct?"

**60-second answer:**
"Three main reasons:

1. **Agentless on Windows** — Run Command works natively on Windows without additional software. SSH would require OpenSSH setup and key management.

2. **IAM-based authentication** — No SSH keys to manage, rotate, or leak. Authentication is IAM-native, audit logged in CloudTrail automatically.

3. **Security at scale** — No open SSH ports (22/2222) in security groups. Works through HTTPS only. For multi-account, this dramatically reduces attack surface.

Trade-off: SSM is slightly slower than direct SSH (1-2 second latency per command), but at scale with 100+ VMs, the security/operational benefit far outweighs the 30-second difference in total collection time."

---

### Q: "How do you handle cross-account access securely?"

**60-second answer:**
"IAM role chaining with external ID:

1. **Management account** has role `AnsibleCrossAccountDiskMonitor` that Ansible assumes.

2. **Child accounts** have identical role name with trust relationship pointing to management account + External ID requirement (e.g., a random UUID).

3. **External ID** protects against confused deputy problem — even if someone gets management account credentials, they can't assume child account roles without the external ID.

Code:
```json
{
  \"Effect\": \"Allow\",
  \"Principal\": {
    \"AWS\": \"arn:aws:iam::MGMT_ACCOUNT:role/AnsibleCrossAccountDiskMonitor\"
  },
  \"Action\": \"sts:AssumeRole\",
  \"Condition\": {
    \"StringEquals\": {
      \"sts:ExternalId\": \"YOUR_EXTERNAL_ID_UUID\"
    }
  }
}
```

Least privilege: Role policies grant only ec2:DescribeInstances, ssm:SendCommand, cloudwatch:PutMetricData—nothing else."

---

### Q: "How does your solution scale to 10,000 VMs?"

**60-second answer:**
"Three layers:

1. **Discovery scales via tagging** — boto3 pagination handles thousands of instances. Tag-based filtering is O(1) at AWS API level.

2. **Collection scales via parallel execution** — SSM Run Command can execute on 1,000+ instances simultaneously. Ansible doesn't need to iterate sequentially.

3. **Aggregation scales via CloudWatch** — Designed for millions of metrics. We use efficient naming (e.g., DiskUsagePercent + dimensions) rather than individual metric names.

Example performance:
- 100 VMs: ~2 minutes
- 1,000 VMs: ~10 minutes (limited by SSM API rate limits, not processing)
- 10,000 VMs: Batching collection into chunks of 500 via Ansible loops

No architectural change needed — just operational scaling (more Ansible control nodes if running locally, or move to AWS Lambda for serverless execution)."

---

### Q: "What are the limitations of this approach?"

**Honest 90-second answer:**
"Several:

1. **Collection frequency** — Every 1–2 hours is realistic. Real-time (sub-minute) would require CloudWatch agent on every VM or third-party tool.

2. **Predictive alerting** — This is reactive monitoring. We alert *after* disk is 85% full. Lucidity's autonomous optimization would *prevent* that scenario.

3. **Other metrics** — Focused on disk only. Full observability would need CPU, memory, I/O — that's where CloudWatch Agent or Prometheus comes in.

4. **Windows support** — SSM Run Command works, but parsing PowerShell output is less reliable than Linux `df`. Might need custom logic per OS.

5. **Cost at extreme scale** — CloudWatch custom metrics cost ~$0.30/month per metric. At 10,000 instances, that's ~$30/month—still cheaper than third-party tools, but worth considering.

**Why these are acceptable for v1:**
This is a *foundational* solution. Once disk issues are solved, the team can add Lucidity for *optimizing* storage (the proactive layer we can't do)."

---

### Q: "How would Lucidity fit into this architecture?"

**60-second answer:**
"Perfect question — they're complementary, not competing:

This solution = *Visibility Layer* — alerts when disk hits 85%, gives ops team time to act.

Lucidity = *Optimization Layer* — autonomously cleans orphaned disks, tiering, resizing BEFORE the alert fires.

Integration:
1. This solution detects anomalies (rapid growth → growth_rate metric)
2. Lucidity's API reads the same CloudWatch metrics
3. Lucidity auto-remediates the issue (deletes old snapshots, tiers cold data)
4. Alert never fires because Lucidity already fixed it

Real-world: Customer gets both without conflict. Lucidity handles the 90% of optimization. This solution handles the edge cases Lucidity can't predict (sudden app deployment, data import)."

---

## Behavioral Questions

### Q: "Tell us about a time you managed a complex infrastructure project"

**90-second story:**
"At Kearney, I led the ADEO Data Readiness Programme — multi-cloud data governance deployment across Abu Dhabi entities. Similar complexity:

**Challenge:** Multiple teams (DCT, ADSC, KF squads), different cloud regions (AWS/Azure), tight timeline.

**My approach:**
- Broke it into phases: Foundation → Delivery → Scaling
- Created reusable playbooks (like this disk monitoring) — one solution, deployed to all entities
- Established clear ownership (each squad had designated engineers)
- Weekly syncs on blockers, not status reports

**Outcome:** Delivered 6 months ahead of initial plan. Now handles 50+ data pipelines, 100+ metrics in production.

**Relevant here:** This disk monitoring follows the same playbook-first approach — build once, scale everywhere."

---

### Q: "How do you approach learning new technologies?"

**60-second answer:**
"Hands-on depth, then breadth:

1. **Build something real** — When I switched to cloud (2019), I didn't just read AWS docs. I deployed a three-tier app (RDS + ALB + ASG) in my own AWS account. Broke it, fixed it.

2. **Connect to existing knowledge** — I come from systems administration (Linux, VMware, storage). Cloud is the same patterns at scale. So I map: VMs → EC2, storage pools → S3/EBS, networks → VPCs.

3. **Depth in one area** — I focused on DevOps/IAC first (Terraform, Ansible, CloudFormation), then broadened to security (IAM, KMS, VPC design).

**For this role:** I'd do the same with Lucidity's platform. First: understand the storage optimization engine (how does auto-tiering work?). Then: design integrations (how does the API connect to CloudWatch?). Finally: implement customer solutions."

---

### Q: "Why are you leaving Kearney / interested in Lucidity?"

**90-second answer:**
"Kearney has been excellent — I grew from DevOps Manager to Technical Delivery Manager leading a 50-person programme. But I'm looking for a step change:

**At Kearney:** I solve problems FOR customers (we deliver their projects).

**At Lucidity:** I'd solve problems WITH customers, building products that scale to thousands of them. That's more leveraged impact.

**Why Lucidity specifically:**
- Cloud economics is the next frontier (storage optimization, unit economics)
- Your approach (autonomous, hands-off) aligns with my philosophy (automation reduces human error)
- Customer testimonials show real ROI (52% cost reduction) — not just nice-to-have
- Your technical depth (autonomous optimization, multi-cloud support) is sophisticated

I want to go deeper on cloud architecture and help shape Lucidity's product roadmap. This Solutions Architect role is the perfect intersection."

---

### Q: "What would you want to learn in this role?"

**60-second answer:**
"Three areas:

1. **Lucidity's internals** — How does autonomous optimization work at scale? What's the hardest problem you solve?

2. **Customer deployment patterns** — How do enterprise customers adopt autonomous tools? What's their biggest objection?

3. **Platform development** — I come from delivery/operations. I want to learn how to think about product (roadmap, feature prioritization, customer feedback → engineering).

Longer term: Grow into a technical/product leadership role where I shape how Lucidity approaches new markets (e.g., multi-cloud support, new verticals)."

---

## Questions to Ask Them

### Q1: "What does a customer success look like in the first 90 days?"
Tells you if they're focused on adoption vs. installation.

### Q2: "How do you handle customers with complex hybrid environments?"
Tests their multi-cloud maturity.

### Q3: "What's the hardest problem you solve that competitors miss?"
Uncovers product differentiation.

### Q4: "Who do I report to, and what does the career ladder look like?"
Clarifies structure and growth.

### Q5: "Can you tell me about a difficult customer situation and how we resolved it?"
Reveals company culture (blame vs. learning).

---

## Final Tips

1. **Use their language** — They talk about "autonomous optimization," "zero-touch," "cost reduction." Use those terms.

2. **Acknowledge their product** — Reference how your solution pairs with Lucidity (not competes).

3. **Show honest constraints** — It signals maturity. ("This is reactive, not predictive. Lucidity is the predictive layer.")

4. **Ask clarifying questions** — "Are you asking about Windows or Linux?" shows you think deeply.

5. **Prepare to code** — If they ask for live coding, be ready to write a simple boto3 script or Ansible snippet. Don't memorize—explain your thinking.

6. **End on enthusiasm** — "I'm excited to help Lucidity expand into multi-account environments. This solution is a foundation for that."

---

## Interview Timeline

**If offered:**
- Ask about start date, team composition, first 30-60-day plan
- Negotiate onboarding (do they have onboarding buddy? mentorship?)
- Clarify scope: Is this pre-sales, post-sales, or internal innovation?

Good luck! You've got this.
