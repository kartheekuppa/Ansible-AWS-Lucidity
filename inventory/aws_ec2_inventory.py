#!/usr/bin/env python3
"""
AWS EC2 Dynamic Inventory Discovery
Discovers EC2 instances tagged with 'monitoring=true' across multiple AWS accounts
Outputs Ansible-compatible JSON inventory
"""

import json
import sys
import boto3
from botocore.exceptions import ClientError, NoCredentialsError


class AWSInventory:
    def __init__(self, external_id=None):
        self.external_id = external_id
        self.inventory = {
            "all": {
                "hosts": {},
                "vars": {}
            },
            "_meta": {
                "hostvars": {}
            }
        }
        self.session = boto3.Session()
        self.sts_client = self.session.client("sts")

    def assume_role(self, account_id, role_name="AnsibleExecutor"):
        """Assume role in child account for cross-account access"""
        try:
            role_arn = f"arn:aws:iam::{account_id}:role/{role_name}"

            assume_role_params = {
                "RoleArn": role_arn,
                "RoleSessionName": "ansible-inventory-discovery"
            }

            if self.external_id:
                assume_role_params["ExternalId"] = self.external_id

            response = self.sts_client.assume_role(**assume_role_params)

            credentials = response["Credentials"]
            return boto3.Session(
                aws_access_key_id=credentials["AccessKeyId"],
                aws_secret_access_key=credentials["SecretAccessKey"],
                aws_session_token=credentials["SessionToken"]
            )
        except ClientError as e:
            print(f"Error assuming role in account {account_id}: {e}", file=sys.stderr)
            return None

    def discover_instances(self, session, account_id):
        """Discover instances with 'monitoring=true' tag"""
        try:
            ec2 = session.client("ec2")

            # Filter for instances with monitoring=true tag and running state
            response = ec2.describe_instances(
                Filters=[
                    {"Name": "tag:monitoring", "Values": ["true"]},
                    {"Name": "instance-state-name", "Values": ["running"]}
                ]
            )

            instances = []
            for reservation in response.get("Reservations", []):
                for instance in reservation.get("Instances", []):
                    instances.append(instance)

            return instances
        except ClientError as e:
            print(f"Error discovering instances in account {account_id}: {e}", file=sys.stderr)
            return []

    def add_instance_to_inventory(self, instance, account_id):
        """Add instance to Ansible inventory"""
        instance_id = instance["InstanceId"]
        private_ip = instance.get("PrivateIpAddress")

        if not private_ip:
            print(f"Warning: Instance {instance_id} has no private IP, skipping", file=sys.stderr)
            return

        # Extract tags
        tags = {tag["Key"]: tag["Value"] for tag in instance.get("Tags", [])}
        environment = tags.get("environment", "unknown")

        # Add to inventory
        hostname = f"{instance_id}.{environment}"

        self.inventory["all"]["hosts"][hostname] = {
            "ansible_host": instance_id,
            "ansible_connection": "aws_ssm"
        }

        # Add host variables
        self.inventory["_meta"]["hostvars"][hostname] = {
            "instance_id": instance_id,
            "private_ip": private_ip,
            "region": instance["Placement"]["AvailabilityZone"][:-1],  # us-east-1a -> us-east-1
            "account_id": account_id,
            "environment": environment,
            "tags": tags,
            "availability_zone": instance["Placement"]["AvailabilityZone"],
            "instance_type": instance["InstanceType"],
            "launch_time": instance["LaunchTime"].isoformat()
        }

    def get_all_accounts(self):
        """Get list of AWS accounts to scan (from STS GetCallerIdentity)"""
        try:
            current_account = self.sts_client.get_caller_identity()["Account"]
            # In production, you'd want to fetch child accounts from Organizations or config
            # For now, return current account and check environment for child accounts
            accounts = [current_account]
            return accounts
        except (ClientError, NoCredentialsError) as e:
            print(f"Error getting caller identity: {e}", file=sys.stderr)
            return []

    def run(self, accounts=None):
        """Discover instances across all accounts"""
        if not accounts:
            accounts = self.get_all_accounts()

        for account_id in accounts:
            # Try to assume role if not current account
            if account_id != self.session.client("sts").get_caller_identity()["Account"]:
                session = self.assume_role(account_id)
                if not session:
                    continue
            else:
                session = self.session

            # Discover instances
            instances = self.discover_instances(session, account_id)
            print(f"Found {len(instances)} instances in account {account_id}", file=sys.stderr)

            for instance in instances:
                self.add_instance_to_inventory(instance, account_id)

        return self.inventory


def main():
    """Main entry point"""
    import argparse
    import os

    parser = argparse.ArgumentParser(description="AWS EC2 Dynamic Inventory")
    parser.add_argument("--list", action="store_true", help="List all hosts")
    parser.add_argument("--host", help="Get host variables")
    parser.add_argument("--external-id", help="External ID for cross-account access",
                       default=os.environ.get("AWS_EXTERNAL_ID"))
    parser.add_argument("--accounts", help="Comma-separated list of account IDs",
                       default=os.environ.get("AWS_ACCOUNTS"))

    args = parser.parse_args()

    # Parse accounts
    accounts = None
    if args.accounts:
        accounts = args.accounts.split(",")

    # Initialize inventory
    inventory_obj = AWSInventory(external_id=args.external_id)
    inventory = inventory_obj.run(accounts=accounts)

    if args.list:
        print(json.dumps(inventory, indent=2))
    elif args.host:
        if args.host in inventory["_meta"]["hostvars"]:
            print(json.dumps(inventory["_meta"]["hostvars"][args.host], indent=2))
        else:
            print(json.dumps({}))
    else:
        print(json.dumps(inventory, indent=2))


if __name__ == "__main__":
    main()
