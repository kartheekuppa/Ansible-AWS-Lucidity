output "ansible_manager_role_arn" {
  description = "ARN of the AnsibleManager role in management account"
  value       = aws_iam_role.ansible_manager.arn
}

output "ansible_manager_role_name" {
  description = "Name of the AnsibleManager role"
  value       = aws_iam_role.ansible_manager.name
}

output "ansible_executor_role_arn" {
  description = "ARN of the AnsibleExecutor role in child accounts"
  value       = try(aws_iam_role.ansible_executor[0].arn, "")
}

output "ansible_executor_role_name" {
  description = "Name of the AnsibleExecutor role"
  value       = try(aws_iam_role.ansible_executor[0].name, "")
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group for Ansible"
  value       = aws_cloudwatch_log_group.ansible.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for disk alerts"
  value       = aws_sns_topic.disk_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.disk_alerts.name
}

output "setup_instructions" {
  description = "Setup instructions for next steps"
  value = <<-EOT

    Setup Complete!
    ===============

    Next Steps:
    1. Update your Ansible playbooks with the role ARNs
    2. Tag EC2 instances: aws ec2 create-tags --resources i-xxxxx --tags Key=monitoring,Value=true
    3. Configure boto3 with external ID: export AWS_EXTERNAL_ID=${var.external_id}
    4. Run discovery: python inventory/aws_ec2_inventory.py --list
    5. Execute playbook: ansible-playbook playbooks/collect_disk_metrics.yml

    Roles Created:
    - Management: ${aws_iam_role.ansible_manager.arn}
    - Executor:   ${try(aws_iam_role.ansible_executor[0].arn, "Not created in this account")}

    Logs:    ${aws_cloudwatch_log_group.ansible.name}
    Alerts:  ${aws_sns_topic.disk_alerts.arn}

  EOT
}
