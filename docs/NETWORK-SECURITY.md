# Network Security Decision: Public vs. Private Subnets

## The Rule

**Nothing in your monitoring architecture needs to be internet-facing.**

---

## Component Breakdown

### PUBLIC SUBNET ❌
**Don't put anything here for this solution.**

The Ansible control node and monitored EC2s should NOT be exposed to the internet.

---

### PRIVATE SUBNETS ✅
**Everything goes here:**

```
Private Subnet A (AZ-1)
├── Ansible Control Node (EC2)
│   └── Outbound: GitHub (via NAT or VPC Endpoint)
│   └── Outbound: AWS APIs (boto3, CloudWatch, SSM) — via VPC Endpoints
│
└── (Optional) Bastion/Jump Host
    └── Only if you need SSH access to control node

Private Subnet B (AZ-2)
├── Monitored EC2 Instance 1
├── Monitored EC2 Instance 2
├── Monitored EC2 Instance N
│   └── No inbound from internet (Security Group: deny all inbound)
│   └── Outbound: Only to AWS services via VPC Endpoints (SSM, CloudWatch)
└── (Optional) NAT Gateway
    └── If using NAT for outbound internet (not ideal)
```

---

## Why Private Subnets?

### Security Benefits
✅ **Attack surface minimized** — No one on the internet can reach your VMs
✅ **No exposed management tools** — Ansible control node stays hidden
✅ **SSM is secure by default** — Uses VPC endpoints, not internet
✅ **Least privilege networking** — Each component only reaches what it needs

### Operational Benefits
✅ **No public IPs needed** — Saves AWS costs
✅ **No security group management for inbound** — Always deny all inbound
✅ **CloudTrail logs everything** — All API calls are audited
✅ **Easier compliance** — Private infrastructure is easier to audit

---

## Network Connectivity Details

### Ansible Control Node Needs Outbound Access To:

1. **GitHub** (pull playbooks/code)
   ```
   Option A: NAT Gateway (internet route)
   Option B: VPC Endpoint for GitHub (HTTPS via privatelink)
   → Option B is preferred (more secure, cheaper)
   ```

2. **AWS APIs** (boto3 calls, CloudWatch, SSM)
   ```
   ✅ Use VPC Endpoints (S3, EC2, SSM, CloudWatch, CloudTrail)
   No internet route needed
   ```

### Monitored EC2 Instances Need Outbound Access To:

1. **SSM Session Manager** 
   ```
   ✅ VPC Endpoint for SSM (Systems Manager)
   ✅ VPC Endpoint for EC2 Messages
   ✅ VPC Endpoint for SSM Messages
   No internet route needed
   ```

2. **CloudWatch Metrics**
   ```
   ✅ VPC Endpoint for CloudWatch
   No internet route needed
   ```

3. **CloudTrail** (audit logging)
   ```
   ✅ VPC Endpoint for CloudTrail
   No internet route needed
   ```

---

## The Network Diagram (Best Practice)

```
┌─────────────────────────────────────────────────────┐
│ VPC (10.0.0.0/16)                                   │
│                                                      │
│  ┌──────────────────────────────────────────────┐  │
│  │ Private Subnet A (10.0.1.0/24)               │  │
│  │                                              │  │
│  │ ┌────────────────────────────────────────┐  │  │
│  │ │ Ansible Control Node (EC2)             │  │  │
│  │ │ Private IP: 10.0.1.50                  │  │  │
│  │ │ IAM Role: AnsibleManager                │  │  │
│  │ │ Security Group: Allow only outbound    │  │  │
│  │ │ - SSH in from Bastion (if needed)      │  │  │
│  │ │ - ALL outbound to VPC                  │  │  │
│  │ └────────────────────────────────────────┘  │  │
│  │                                              │  │
│  └──────────────────────────────────────────────┘  │
│                                                      │
│  ┌──────────────────────────────────────────────┐  │
│  │ Private Subnet B (10.0.2.0/24)               │  │
│  │                                              │  │
│  │ ┌──────────┐  ┌──────────┐  ┌──────────┐   │  │
│  │ │  VM 1    │  │  VM 2    │  │  VM N    │   │  │
│  │ │ i-1234   │  │ i-5678   │  │ i-abcd   │   │  │
│  │ │ 10.0.2.x │  │ 10.0.2.x │  │ 10.0.2.x │   │  │
│  │ │ SG: Deny │  │ SG: Deny │  │ SG: Deny │   │  │
│  │ │ all in   │  │ all in   │  │ all in   │   │  │
│  │ └──────────┘  └──────────┘  └──────────┘   │  │
│  │                                              │  │
│  └──────────────────────────────────────────────┘  │
│                                                      │
│  ┌──────────────────────────────────────────────┐  │
│  │ VPC Endpoints (Private — No Internet Route)  │  │
│  │                                              │  │
│  │ ✓ SSM (Systems Manager)                     │  │
│  │ ✓ EC2 Messages                              │  │
│  │ ✓ SSM Messages                              │  │
│  │ ✓ CloudWatch                                │  │
│  │ ✓ CloudTrail                                │  │
│  │ ✓ S3 (for Ansible code)                     │  │
│  │ ✓ GitHub (HTTPS via PrivateLink — optional) │  │
│  │                                              │  │
│  └──────────────────────────────────────────────┘  │
│                                                      │
│  ┌──────────────────────────────────────────────┐  │
│  │ Route Tables (PRIVATE)                       │  │
│  │                                              │  │
│  │ Destination    | Target                     │  │
│  │ ──────────────────────────────────────────  │  │
│  │ 10.0.0.0/16    | Local (VPC)                │  │
│  │ 0.0.0.0/0      | ✗ NONE (or NAT if needed) │  │
│  │                                              │  │
│  └──────────────────────────────────────────────┘  │
│                                                      │
└─────────────────────────────────────────────────────┘

AWS Managed Services (Outside VPC):
├── CloudWatch (accessed via VPC Endpoint)
├── SSM Session Manager (accessed via VPC Endpoint)
├── IAM (implicit, accessed via VPC Endpoint)
└── GitHub (accessed via NAT Gateway or GitHub VPC Endpoint)
```

---

## Security Group Rules (Strict)

### Ansible Control Node Security Group
```
Inbound:
  ❌ DENY all (or allow SSH from Bastion only)

Outbound:
  ✅ HTTPS (443) → VPC Endpoints
  ✅ HTTPS (443) → GitHub (if NAT route)
  ✅ All traffic → VPC CIDR (10.0.0.0/16)
```

### Monitored EC2 Instances Security Group
```
Inbound:
  ❌ DENY all (absolutely no inbound)

Outbound:
  ✅ HTTPS (443) → VPC Endpoints (SSM, CloudWatch, EC2Messages)
  ✅ DNS (53) → Route 53 (VPC resolver)
```

---

## Do You Need a Bastion Host? (Jump Server)

**No, not for this solution.**

Why?
- ✅ You don't need SSH access to EC2 instances (SSM Session Manager handles it)
- ✅ You don't need SSH access to Ansible control node (it runs on schedule)
- ✅ Everything is private and secure

If you did need manual debugging:
- Put a bastion in PUBLIC subnet (only one exposed)
- Bastion SSH to private instances via Systems Manager Session Manager (not SSH)
- This keeps your architecture secure

---

## Cost Implications

### ✅ Cheapest & Most Secure (RECOMMENDED)
```
Private subnets only
+ VPC Endpoints (for AWS services)
Total: ~$7-14/month for endpoints (depending on usage)
```

### ⚠️ More Expensive
```
Private subnets
+ NAT Gateway (for GitHub access)
Total: $32/month + data transfer charges
```

### ❌ Not Recommended
```
Public subnets with Security Groups
Exposes infrastructure unnecessarily
```

---

## Summary Table

| Component | Subnet | Why | Security |
|-----------|--------|-----|----------|
| Ansible Control Node | Private | No internet exposure needed | SSH from Bastion only |
| Monitored EC2 VMs | Private | No internet exposure needed | DENY all inbound |
| VPC Endpoints | Private | Secure AWS API access | No internet route needed |
| Bastion (if needed) | Public | Only if manual SSH needed | Restricted security group |
| NAT Gateway (if needed) | Public | Only for legacy apps | Use VPC Endpoints instead |
| GitHub Code | Private via endpoint | Use PrivateLink endpoint | No data crosses internet |

---

## Implementation Checklist

### Phase 1: Build Private Subnets
- [ ] Create 2 private subnets (multi-AZ)
- [ ] Create route tables (no internet routes)
- [ ] Create security groups (deny inbound, limited outbound)

### Phase 2: Setup VPC Endpoints
- [ ] SSM (Systems Manager)
- [ ] EC2 Messages
- [ ] SSM Messages
- [ ] CloudWatch
- [ ] CloudTrail
- [ ] S3 (for Ansible code/logs)
- [ ] GitHub (optional, if private access needed)

### Phase 3: Deploy Ansible Control Node
- [ ] EC2 in Private Subnet A
- [ ] IAM role with needed permissions
- [ ] Security group with outbound HTTPS only
- [ ] Git SSH key or GitHub token (stored in Secrets Manager)

### Phase 4: Deploy Monitored EC2s
- [ ] EC2s in Private Subnet B
- [ ] SSM Agent (pre-installed on AWS AMIs)
- [ ] IAM role with CloudWatch + SSM permissions
- [ ] Security group with DENY all inbound

### Phase 5: Test
- [ ] Ansible can reach EC2s via SSM
- [ ] EC2s can push metrics to CloudWatch
- [ ] CloudTrail logs SSM commands
- [ ] Verify NO internet routes

---

## Architecture Decision

**For your Lucidity interview, here's the pitch:**

"All infrastructure is in **private subnets**. The Ansible control node and monitored EC2 instances have zero internet exposure. We use **AWS Systems Manager Session Manager via VPC endpoints** — no SSH keys, no open ports, everything is encrypted and audited through CloudTrail. The architecture is secure by default: deny all inbound, minimal outbound (only to AWS services via VPC endpoints). This gives us least-privilege networking with maximum security."

---

## One More Thing: Terraform IaC Example

```hcl
# Private Subnets
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

# Route Table: NO Internet Routes (stays private)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
}

# VPC Endpoints (secure private access to AWS services)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.us-east-1.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
}

# Security Group: Deny all inbound
resource "aws_security_group" "private_ec2" {
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [] # Empty = DENY all
  }
  
  egress {
    from_port   = 443 # HTTPS only
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # To VPC endpoints
  }
}
```

---

## Bottom Line

✅ **Everything private, zero internet exposure**
✅ **VPC Endpoints for AWS service access**
✅ **SSM Session Manager (no SSH needed)**
✅ **Security group: deny inbound, whitelist outbound**
✅ **Audit everything via CloudTrail**

This is production-grade, enterprise-secure architecture.
