variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "management_account" {
  description = "AWS account ID of the management account"
  type        = string
  validation {
    condition     = can(regex("^\\d{12}$", var.management_account))
    error_message = "Management account must be a 12-digit AWS account ID."
  }
}

variable "child_accounts" {
  description = "List of AWS account IDs to monitor (child accounts)"
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for account_id in var.child_accounts : can(regex("^\\d{12}$", account_id))
    ])
    error_message = "All child accounts must be 12-digit AWS account IDs."
  }
}

variable "external_id" {
  description = "External ID for cross-account role assumption (for security)"
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.external_id) >= 8
    error_message = "External ID must be at least 8 characters for security."
  }
}

variable "alert_email" {
  description = "Email address for SNS alerts (optional)"
  type        = string
  default     = ""
}

variable "enable_logging" {
  description = "Enable CloudWatch Logs for Ansible"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch Logs"
  type        = number
  default     = 30
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention must be one of the valid CloudWatch values."
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "DiskMonitoring"
    ManagedBy   = "Terraform"
    CaseStudy   = "Lucidity"
  }
}
