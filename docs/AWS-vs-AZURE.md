# AWS vs. Azure: Defensive Interview Guide

## The Question You'll Get

**Interviewer:** "You chose AWS. Why not Azure? What are the tradeoffs?"

This is a **softball question designed to test your judgment**, not trap you. They want to see:
- Can you acknowledge tradeoffs honestly?
- Do you understand cloud architecture deeply?
- Are you customer-centric or just picking your favorite?

---

## Your Answer Structure (90 seconds)

**Opening (10 sec):**
"Great question. Azure is absolutely viable. Here's my thinking..."

**Body (60 sec):** [Choose one of the frameworks below]

**Close (20 sec):**
"For this specific scenario—enterprise disk monitoring at scale—AWS gives the shortest critical path. But if the customer is Microsoft-heavy, Azure would be the right choice."

---

## Framework 1: Technical Reasoning (Recommended)

### "I chose AWS because Ansible + SSM integration is cleaner than Azure alternatives."

**Full answer:**
"Both clouds work, but the execution layer differs significantly.

On AWS, Ansible + SSM is integrated: Ansible orchestrates the workflow (discovery, collection, aggregation), and SSM Run Command executes commands on VMs via IAM roles. One unified approach, infrastructure-as-code all the way.

On Azure, I'd have three options, none ideal:
1. **Custom Script Extension** — Not infrastructure-as-code; requires portal config
2. **Azure Automation Runbooks** — Now you have two orchestration tools (Ansible + Runbooks)
3. **SSH/WinRM** — Back to credential management across subscriptions

So AWS gives me a cleaner, more maintainable solution. Less operational friction, one source of truth (playbooks).

That said, if the customer is Microsoft-heavy (Office 365 → Azure migration), I'd revisit this. Azure Automation Runbooks would be the natural fit."

**Why this works:**
- Shows deep understanding (execution layer ≠ discovery layer)
- Honest about tradeoffs
- Acknowledges customer context matters
- Technically defensible

---

## Framework 2: Market/Data Reasoning

### "I chose AWS because market research shows it has higher disk space incident frequency."

**Full answer:**
"I researched which platform customers actually experience this problem on.

AWS re:Post has more frequent disk space incidents (inode exhaustion, rapid log growth) than Azure communities. When incidents do occur on Azure, they're often preventable through better native monitoring setup—less urgent.

AWS customers face acute, unplanned disk issues. Azure customers face operational complexity in setting up monitoring. The critical problem is more acute on AWS.

So AWS is where this solution has the highest impact. But if I were deploying to an Azure-dominant customer, I'd flip the decision immediately."

**Why this works:**
- Data-driven (not just preference)
- Shows you did your homework
- Customer-centric framing
- Humility (willing to flip for customer context)

---

## Framework 3: Critical Path Reasoning

### "I chose AWS because it's the fastest path to production."

**Full answer:**
"Both clouds can solve this, but deployment time differs.

AWS + Ansible + SSM: 8–12 hours to production
- IAM role setup (2–3h) → Run Command testing (2–3h) → Playbook deployment (2–3h)
- Straightforward: one integrated flow

Azure + Ansible + Custom Script Extension: 9–15 hours to production
- Azure Automation setup (2–3h) → Custom Script Extension config (3–5h) → Integration testing (2–3h)
- More moving parts, more troubleshooting

For a case study interview, I want to show I can move fast. AWS is the faster option. In a real customer engagement, I'd let the customer's existing cloud preference drive the choice."

**Why this works:**
- Pragmatic (time-to-value matters)
- Shows operational thinking
- Acknowledges context matters
- Realistic about deployment

---

## Specific Pitfalls to Mention (If Pressed)

If the interviewer digs deeper: "What are the actual pitfalls with Azure?"

### Pitfall #1: Fragmented Orchestration
"On Azure, you'd likely end up using two orchestration tools:
- Ansible for multi-subscription discovery and looping
- Azure Automation Runbooks for the actual execution

Now you have two tools, two languages (YAML + PowerShell), two places to maintain code. That's where complexity creeps in."

### Pitfall #2: Custom Script Extension Friction
"Custom Script Extensions work, but they're imperative, not declarative.

You can't run an extension twice on the same VM and guarantee the same state (unlike Ansible's idempotency). For operational reliability, that matters."

### Pitfall #3: Credential Sprawl Risk
"If you use SSH/WinRM for execution (to avoid Custom Script Extensions), you now manage SSH keys or certificates across multiple Azure subscriptions. That's a security burden and audit nightmare."

### Pitfall #4: Less Mature Ansible Collection
"Ansible's Azure collection (`azure.azcollection`) is good, but it's not as battle-tested as the AWS collection. You'll run into edge cases."

### Pitfall #5: Hybrid Complexity (If Mentioned)
"Azure is better for hybrid on-prem + cloud scenarios. But if the brief is *cloud-only* (which this is), that advantage disappears. And hybrid adds complexity."

---

## When to Concede: Honest Scenarios Where Azure Wins

If pressed, be honest:

### "Azure would be better if..."

1. **Customer is Microsoft-heavy**
   - "If they're already running Office 365, SQL Server, SharePoint, they've bet on Microsoft. Azure Automation Runbooks would feel more natural than Ansible."

2. **Hybrid on-prem + cloud**
   - "Azure Arc integrates on-prem + cloud more seamlessly. Ansible + SSM is AWS-cloud-only."

3. **Windows-first environment**
   - "Azure has better Windows integration. Custom Script Extension works fine if you're 80% Windows. AWS SSM is agnostic, but Azure native tooling is more elegant for Windows shops."

4. **Existing Azure Automation investment**
   - "If they already use Azure Automation for other tasks, extending it to disk monitoring is simpler than adding Ansible."

**The key:** Say these *genuinely*. It shows you're not ideological, you're pragmatic.

---

## Red Flags to Avoid

❌ **"Azure is worse"** (too dismissive)
❌ **"I hate Azure Automation"** (personal preference, not architecture)
❌ **"AWS is obviously better"** (arrogant, closes conversation)
❌ **"Azure doesn't work"** (false, makes you look uninformed)

---

## Perfect Answer Template

**Interviewer:** "Why AWS and not Azure?"

**You:**
"Both are viable. Here's why I chose AWS for this specific case study:

**#1 — Cleaner execution layer.** Ansible + SSM is integrated. Azure would require either Custom Script Extensions (not infrastructure-as-code) or a separate Azure Automation layer (two tools). AWS is simpler operationally.

**#2 — Faster critical path.** AWS deployment is 8–12 hours; Azure is 9–15 hours due to the fragmentation I mentioned.

**#3 — Market context.** AWS customers report more frequent disk space incidents (based on re:Post data), so this solution has higher impact there.

That said, if the customer was Microsoft-dominant or running hybrid on-prem + cloud, I'd flip this decision immediately. Architecture should follow customer context, not personal preference."

**Result:** You sound knowledgeable, humble, pragmatic, and customer-centric. That's exactly what they want to hear.

---

## Pre-Interview Checklist

- [ ] Can you explain the execution layer difference (Ansible + SSM vs. Ansible + Custom Script Extension)?
- [ ] Can you cite the critical path times (8–12h AWS vs. 9–15h Azure) with confidence?
- [ ] Can you admit Azure is better for hybrid scenarios without hesitation?
- [ ] Can you avoid sounding dismissive of Azure while defending AWS?
- [ ] Can you pivot back to customer context ("If they were Microsoft-heavy, I'd choose Azure")?

---

## Advanced: If Asked "What's the Single Biggest Pitfall?"

**The honest answer:**
"Fragmented orchestration. Using two tools (Ansible + Azure Automation) instead of one (Ansible + SSM) creates maintenance burden and increases the chance of configuration drift between the two. On AWS, Ansible is the single source of truth. On Azure, you'd have Ansible *and* Runbooks as sources of truth."

This shows deep architectural thinking—pitfalls aren't just technical, they're operational.

---

## Bonus: How This Relates to Lucidity

**Interviewer:** "Does this decision relate to Lucidity's philosophy at all?"

**You:**
"Yes. Lucidity's pitch is 'autonomous, hands-off optimization.' My solution reflects the same thinking: pick the simplest tool that scales, avoid unnecessary complexity, let automation handle the heavy lifting.

AWS + Ansible + SSM is simpler than Azure + Automation + Runbooks, so it aligns with Lucidity's philosophy of elegance at scale."

**Translation:** You understand Lucidity's values, not just cloud architecture.

---

## Summary

Your AWS choice is defensible on three fronts:
1. **Technical** — Cleaner integration (Ansible + SSM)
2. **Operational** — Faster critical path (8–12 hours)
3. **Market** — Higher customer pain frequency (AWS disk incidents)

But always close with: **"Customer context might change this decision."**

That's the sign of a real Solutions Architect—principles first, customer context second.

You're ready. 💪
