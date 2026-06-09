#!/usr/bin/env python3
"""
Script to set up ACLs (Access Control Lists) on MSK cluster.
This script creates ACLs for:
- Topic read/write permissions
- Consumer group permissions
- Transactional ID permissions (if needed)
"""

import os
import sys
import subprocess
import tempfile
from kafka_config import ConfigManager

def create_command_config(username: str, password: str) -> str:
    """Create a temporary command config file for kafka-acls.sh"""
    config_content = f"""security.protocol=SASL_SSL
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="{username}" password="{password}";
"""
    # Create a temporary file
    with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.properties') as f:
        f.write(config_content)
        return f.name

def find_kafka_acls():
    """Find kafka-acls or kafka-acls.sh in common locations"""
    # Check both with and without .sh extension (newer versions don't have .sh)
    kafka_acls_paths = [
        "/home/ec2-user/confluent-8.0.0/bin/kafka-acls",
        "/home/ec2-user/confluent-8.0.0/bin/kafka-acls.sh",
        "/usr/local/bin/kafka-acls",
        "/usr/local/bin/kafka-acls.sh",
    ]
    
    for path in kafka_acls_paths:
        if os.path.exists(path):
            return path
    
    # Fallback: check if either version is in PATH
    for cmd in ["kafka-acls", "kafka-acls.sh"]:
        result = subprocess.run(["which", cmd], capture_output=True, text=True)
        if result.returncode == 0:
            return result.stdout.strip()
    
    return None

def run_kafka_acls_command(bootstrap_servers: str, config_file: str, operation: str, principal: str, op_type: str, resource_type: str, resource_name: str) -> bool:
    """Run a kafka-acls.sh command"""
    kafka_acls = find_kafka_acls()
    
    if not kafka_acls:
        print("⚠️  kafka-acls not found. Please ensure Confluent Platform is installed.")
        print("   You can install it by running:")
        print("   curl -O https://packages.confluent.io/archive/8.0/confluent-8.0.0.tar.gz")
        print("   tar xzf confluent-8.0.0.tar.gz")
        print("   export PATH=$PATH:/home/ec2-user/confluent-8.0.0/bin")
        return False
    
    # Build command based on resource type
    if resource_type == "topic":
        cmd = [
            kafka_acls,
            "--bootstrap-server", bootstrap_servers,
            "--command-config", config_file,
            operation,
            "--allow-principal", principal,
            "--operation", op_type,
            "--topic", resource_name
        ]
    elif resource_type == "group":
        cmd = [
            kafka_acls,
            "--bootstrap-server", bootstrap_servers,
            "--command-config", config_file,
            operation,
            "--allow-principal", principal,
            "--operation", op_type,
            "--group", resource_name
        ]
    else:
        print(f"❌ Unknown resource type: {resource_type}")
        return False
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            return True
        elif "already exists" in result.stderr.lower() or "already has" in result.stderr.lower():
            return True  # ACL already exists, which is fine
        else:
            print(f"⚠️  Command output: {result.stderr}")
            return False
    except subprocess.TimeoutExpired:
        print(f"❌ Command timed out")
        return False
    except Exception as e:
        print(f"❌ Error running command: {e}")
        return False

def setup_acls():
    """Set up ACLs on MSK cluster using kafka-acls.sh"""
    config_manager = ConfigManager()
    config = config_manager.get_active_config()
    
    # Get the username from environment
    username = os.getenv("MSK_SASL_USERNAME", "msk-user")
    password = os.getenv("MSK_SASL_PASSWORD", "ChangeMe123!")
    topic_name = config.topic_name
    consumer_group = "orders-consumer-group"
    
    print("🔐 Setting up ACLs for MSK cluster")
    print("=" * 60)
    print(f"Username: {username}")
    print(f"Topic: {topic_name}")
    print(f"Consumer Group: {consumer_group}")
    print(f"Bootstrap Servers: {config.bootstrap_servers}")
    print("-" * 60)
    
    # Create temporary config file
    config_file = create_command_config(username, password)
    
    try:
        acl_definitions = [
            # Topic ACLs
            ("--add", f"User:{username}", "Read", topic_name, "topic"),
            ("--add", f"User:{username}", "Write", topic_name, "topic"),
            ("--add", f"User:{username}", "Describe", topic_name, "topic"),
            ("--add", f"User:{username}", "DescribeConfigs", topic_name, "topic"),
            # Consumer Group ACLs
            ("--add", f"User:{username}", "Read", consumer_group, "group"),
            ("--add", f"User:{username}", "Describe", consumer_group, "group"),
        ]
        
        success_count = 0
        for operation, principal, op_type, resource_name, resource_kind in acl_definitions:
            print(f"\n📝 Creating ACL: {principal} -> {op_type} on {resource_kind} '{resource_name}'...")
            
            result = run_kafka_acls_command(
                config.bootstrap_servers, 
                config_file, 
                operation, 
                principal, 
                op_type,
                resource_kind,
                resource_name
            )
            
            if result:
                print(f"✅ ACL created successfully")
                success_count += 1
            else:
                print(f"⚠️  ACL may already exist or there was an issue")
        
        print("\n" + "=" * 60)
        if success_count == len(acl_definitions):
            print("✅ All ACLs set up successfully!")
        else:
            print(f"⚠️  {success_count}/{len(acl_definitions)} ACLs processed")
        print("\n💡 These ACLs will be migrated to Confluent Cloud using the KCP UI in Part 3.")
        
        return True
        
    finally:
        # Clean up temporary config file
        if os.path.exists(config_file):
            os.unlink(config_file)

def list_acls():
    """List current ACLs"""
    config_manager = ConfigManager()
    config = config_manager.get_active_config()
    username = os.getenv("MSK_SASL_USERNAME", "msk-user")
    password = os.getenv("MSK_SASL_PASSWORD", "ChangeMe123!")
    
    print("📋 Listing ACLs on MSK cluster:")
    print("=" * 60)
    
    config_file = create_command_config(username, password)
    
    try:
        kafka_acls = find_kafka_acls()
        
        if kafka_acls:
            cmd = [
                kafka_acls,
                "--bootstrap-server", config.bootstrap_servers,
                "--command-config", config_file,
                "--list"
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                print(result.stdout)
            else:
                print(f"⚠️  Error listing ACLs: {result.stderr}")
        else:
            print("⚠️  kafka-acls not found")
    finally:
        if os.path.exists(config_file):
            os.unlink(config_file)
    
    print("=" * 60)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "list":
        list_acls()
    else:
        setup_acls()
