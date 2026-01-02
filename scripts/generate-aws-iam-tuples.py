#!/usr/bin/env python3
"""
Generate AWS IAM-style tuples at different scales for load testing.

Scales:
- Mini: ~1,000 tuples
- Mid: ~10,000 tuples
- Large: ~100,000 tuples
- Huge: ~1,000,000 tuples
"""

import json
import sys
from typing import List, Dict

def generate_tuples(scale: str) -> List[Dict]:
    """Generate tuples based on the specified scale."""

    scale_config = {
        "mini": {
            "accounts": 2,
            "users_per_account": 10,
            "groups_per_account": 3,
            "roles_per_account": 5,
            "s3_buckets_per_account": 10,
            "ec2_instances_per_account": 8,
            "dynamodb_tables_per_account": 5,
            "lambda_functions_per_account": 7,
        },
        "mid": {
            "accounts": 5,
            "users_per_account": 100,
            "groups_per_account": 20,
            "roles_per_account": 30,
            "s3_buckets_per_account": 50,
            "ec2_instances_per_account": 40,
            "dynamodb_tables_per_account": 30,
            "lambda_functions_per_account": 25,
        },
        "large": {
            "accounts": 10,
            "users_per_account": 500,
            "groups_per_account": 100,
            "roles_per_account": 200,
            "s3_buckets_per_account": 200,
            "ec2_instances_per_account": 150,
            "dynamodb_tables_per_account": 100,
            "lambda_functions_per_account": 100,
        },
        "huge": {
            "accounts": 20,
            "users_per_account": 2000,
            "groups_per_account": 500,
            "roles_per_account": 1000,
            "s3_buckets_per_account": 500,
            "ec2_instances_per_account": 300,
            "dynamodb_tables_per_account": 200,
            "lambda_functions_per_account": 200,
        }
    }

    if scale not in scale_config:
        raise ValueError(f"Invalid scale: {scale}. Choose from: {list(scale_config.keys())}")

    config = scale_config[scale]
    tuples = []

    # Generate for each account
    for account_id in range(config["accounts"]):
        account_name = f"account:account-{account_id:04d}"

        # Create users and assign them to account
        users = []
        for user_id in range(config["users_per_account"]):
            user_name = f"user:user-{account_id:04d}-{user_id:05d}"
            users.append(user_name)

            # 10% of users are account admins
            if user_id % 10 == 0:
                tuples.append({
                    "user": user_name,
                    "relation": "admin",
                    "object": account_name
                })
            else:
                tuples.append({
                    "user": user_name,
                    "relation": "member",
                    "object": account_name
                })

        # Create groups
        groups = []
        for group_id in range(config["groups_per_account"]):
            group_name = f"group:group-{account_id:04d}-{group_id:03d}"
            groups.append(group_name)

            # Add users to groups (each user in 1-3 groups)
            for user_idx in range(group_id * 5, min((group_id + 1) * 5, len(users))):
                if user_idx < len(users):
                    tuples.append({
                        "user": users[user_idx],
                        "relation": "member",
                        "object": group_name
                    })

            # Groups are part of the account
            tuples.append({
                "user": f"{group_name}#member",
                "relation": "member",
                "object": account_name
            })

        # Create roles
        roles = []
        for role_id in range(config["roles_per_account"]):
            role_name = f"role:role-{account_id:04d}-{role_id:04d}"
            roles.append(role_name)

            # Users can assume roles (20% of users can assume each role)
            for user_idx in range(0, len(users), 5):
                if user_idx < len(users) and role_id % 3 == user_idx % 3:
                    tuples.append({
                        "user": users[user_idx],
                        "relation": "assumable_by",
                        "object": role_name
                    })

            # Some groups can assume roles
            if role_id < len(groups):
                tuples.append({
                    "user": f"{groups[role_id]}#member",
                    "relation": "assumable_by",
                    "object": role_name
                })

        # Create S3 buckets
        for bucket_id in range(config["s3_buckets_per_account"]):
            bucket_name = f"s3_bucket:bucket-{account_id:04d}-{bucket_id:05d}"

            # Account relationship
            tuples.append({
                "user": account_name,
                "relation": "account",
                "object": bucket_name
            })

            # Owner (first user of the account)
            tuples.append({
                "user": users[0],
                "relation": "owner",
                "object": bucket_name
            })

            # Identity-based permissions
            # 30% of users have read access
            for user_idx in range(0, len(users), 3):
                if user_idx < len(users):
                    tuples.append({
                        "user": users[user_idx],
                        "relation": "identity_based_read",
                        "object": bucket_name
                    })

            # 10% of users have write access
            for user_idx in range(0, len(users), 10):
                if user_idx < len(users):
                    tuples.append({
                        "user": users[user_idx],
                        "relation": "identity_based_write",
                        "object": bucket_name
                    })

            # Group-based access
            if bucket_id < len(groups):
                tuples.append({
                    "user": f"{groups[bucket_id % len(groups)]}#member",
                    "relation": "identity_based_read",
                    "object": bucket_name
                })

            # Resource-based policies (allow some roles)
            if bucket_id < len(roles) and bucket_id % 5 == 0:
                tuples.append({
                    "user": roles[bucket_id % len(roles)],
                    "relation": "resource_policy_allows",
                    "object": bucket_name
                })

        # Create EC2 instances
        for ec2_id in range(config["ec2_instances_per_account"]):
            instance_name = f"ec2_instance:instance-{account_id:04d}-{ec2_id:05d}"

            tuples.append({
                "user": account_name,
                "relation": "account",
                "object": instance_name
            })

            # Owner
            tuples.append({
                "user": users[ec2_id % len(users)],
                "relation": "owner",
                "object": instance_name
            })

            # Roles can manage instances
            if ec2_id < len(roles):
                role_name = roles[ec2_id % len(roles)]
                tuples.append({
                    "user": role_name,
                    "relation": "identity_based_start",
                    "object": instance_name
                })
                tuples.append({
                    "user": role_name,
                    "relation": "identity_based_stop",
                    "object": instance_name
                })
                if ec2_id % 3 == 0:
                    tuples.append({
                        "user": role_name,
                        "relation": "identity_based_terminate",
                        "object": instance_name
                    })

            # Groups can describe instances
            if ec2_id < len(groups):
                tuples.append({
                    "user": f"{groups[ec2_id % len(groups)]}#member",
                    "relation": "identity_based_describe",
                    "object": instance_name
                })

        # Create DynamoDB tables
        for table_id in range(config["dynamodb_tables_per_account"]):
            table_name = f"dynamodb_table:table-{account_id:04d}-{table_id:05d}"

            tuples.append({
                "user": account_name,
                "relation": "account",
                "object": table_name
            })

            tuples.append({
                "user": users[0],
                "relation": "owner",
                "object": table_name
            })

            # Groups have read access
            if table_id < len(groups):
                tuples.append({
                    "user": f"{groups[table_id % len(groups)]}#member",
                    "relation": "identity_based_read",
                    "object": table_name
                })

            # Some roles have write access (for Lambda execution roles)
            if table_id < len(roles) and table_id % 2 == 0:
                tuples.append({
                    "user": roles[table_id % len(roles)],
                    "relation": "identity_based_write",
                    "object": table_name
                })

        # Create Lambda functions
        for lambda_id in range(config["lambda_functions_per_account"]):
            function_name = f"lambda_function:function-{account_id:04d}-{lambda_id:05d}"

            tuples.append({
                "user": account_name,
                "relation": "account",
                "object": function_name
            })

            tuples.append({
                "user": users[0],
                "relation": "owner",
                "object": function_name
            })

            # Execution role
            if lambda_id < len(roles):
                tuples.append({
                    "user": roles[lambda_id % len(roles)],
                    "relation": "execution_role",
                    "object": function_name
                })

            # Groups can invoke
            if lambda_id < len(groups):
                tuples.append({
                    "user": f"{groups[lambda_id % len(groups)]}#member",
                    "relation": "identity_based_invoke",
                    "object": function_name
                })

            # Some roles can update
            if lambda_id < len(roles) and lambda_id % 4 == 0:
                tuples.append({
                    "user": roles[lambda_id % len(roles)],
                    "relation": "identity_based_update",
                    "object": function_name
                })

    return tuples

def main():
    if len(sys.argv) != 2:
        print("Usage: python generate-aws-iam-tuples.py <scale>")
        print("Scales: mini, mid, large, huge")
        sys.exit(1)

    scale = sys.argv[1].lower()

    print(f"Generating {scale} scale tuples...")
    tuples = generate_tuples(scale)

    output = {
        "writes": {
            "tuple_keys": tuples
        }
    }

    output_file = f"tuples/aws-iam-style/scale/{scale}-tuples.json"
    with open(output_file, 'w') as f:
        json.dump(output, f, indent=2)

    print(f"Generated {len(tuples):,} tuples")
    print(f"Saved to: {output_file}")

    # Print summary
    print(f"\nSummary:")
    print(f"  Total tuples: {len(tuples):,}")

    # Count by relation type
    relation_counts = {}
    for tuple in tuples:
        relation = tuple["relation"]
        relation_counts[relation] = relation_counts.get(relation, 0) + 1

    print(f"\nTuples by relation:")
    for relation, count in sorted(relation_counts.items(), key=lambda x: x[1], reverse=True):
        print(f"    {relation}: {count:,}")

if __name__ == "__main__":
    main()
