#!/usr/bin/env python3
"""
Script to check MSK Connect connector status and manage Kafka Connect connectors.
Supports both MSK Connect (source) and Confluent Cloud (target after migration).
"""

import os
import json
import sys
import requests
from typing import Dict, Any, Optional

try:
    import boto3
    HAS_BOTO3 = True
except ImportError:
    HAS_BOTO3 = False


# ------------------------------------------------------
# MSK Connect Functions (Source Cluster)
# ------------------------------------------------------

def get_msk_connect_client():
    """Get MSK Connect client (boto3)"""
    if not HAS_BOTO3:
        print("❌ boto3 is not installed. Install with: pip install boto3")
        return None
    
    region = os.getenv("AWS_REGION", "us-west-2")
    return boto3.client('kafkaconnect', region_name=region)


def list_msk_connectors():
    """List all MSK Connect connectors"""
    client = get_msk_connect_client()
    if not client:
        return
    
    try:
        response = client.list_connectors()
        connectors = response.get('connectors', [])
        
        print("📋 MSK Connect Connectors:")
        print("=" * 60)
        
        if not connectors:
            print("  No connectors found")
            return
        
        for connector in connectors:
            name = connector.get('connectorName', 'Unknown')
            state = connector.get('connectorState', 'Unknown')
            arn = connector.get('connectorArn', 'Unknown')
            
            # Status emoji based on state
            status_emoji = "✅" if state == "RUNNING" else "⏳" if state in ["CREATING", "UPDATING"] else "❌"
            
            print(f"  {status_emoji} {name}")
            print(f"     State: {state}")
            print(f"     ARN: {arn}")
            print()
            
    except Exception as e:
        print(f"❌ Error listing MSK Connect connectors: {e}")


def get_msk_connector_status(connector_name: str = None):
    """Get status of a specific MSK Connect connector"""
    client = get_msk_connect_client()
    if not client:
        return
    
    try:
        # If no connector name provided, look for orders-s3-sink
        if not connector_name:
            connector_name = os.getenv("MSK_CONNECTOR_NAME", "dev-orders-s3-sink")
        
        # List connectors and find the one matching the name
        response = client.list_connectors()
        connectors = response.get('connectors', [])
        
        target_connector = None
        for connector in connectors:
            if connector_name in connector.get('connectorName', ''):
                target_connector = connector
                break
        
        if not target_connector:
            print(f"❌ Connector '{connector_name}' not found")
            print("   Available connectors:")
            for c in connectors:
                print(f"     - {c.get('connectorName')}")
            return
        
        connector_arn = target_connector.get('connectorArn')
        
        # Get detailed connector info
        detail_response = client.describe_connector(connectorArn=connector_arn)
        
        print(f"📊 MSK Connect Connector Status: {connector_name}")
        print("=" * 60)
        print(f"  Name: {detail_response.get('connectorName')}")
        print(f"  State: {detail_response.get('connectorState')}")
        print(f"  ARN: {connector_arn}")
        print()
        print("  Kafka Cluster:")
        kafka_cluster = detail_response.get('kafkaCluster', {}).get('apacheKafkaCluster', {})
        print(f"    Bootstrap Servers: {kafka_cluster.get('bootstrapServers', 'N/A')}")
        print()
        print("  Connector Configuration:")
        config = detail_response.get('connectorConfiguration', {})
        for key, value in config.items():
            # Mask sensitive values
            if 'password' in key.lower() or 'secret' in key.lower():
                value = '********'
            print(f"    {key}: {value}")
        print()
        
        # Show capacity info
        capacity = detail_response.get('capacity', {})
        if 'autoScaling' in capacity:
            autoscaling = capacity['autoScaling']
            print(f"  Capacity (Autoscaling):")
            print(f"    MCU Count: {autoscaling.get('mcuCount')}")
            print(f"    Min Workers: {autoscaling.get('minWorkerCount')}")
            print(f"    Max Workers: {autoscaling.get('maxWorkerCount')}")
        elif 'provisionedCapacity' in capacity:
            provisioned = capacity['provisionedCapacity']
            print(f"  Capacity (Provisioned):")
            print(f"    MCU Count: {provisioned.get('mcuCount')}")
            print(f"    Worker Count: {provisioned.get('workerCount')}")
            
    except Exception as e:
        print(f"❌ Error getting MSK connector status: {e}")


def check_s3_output():
    """Check if the connector is writing to S3"""
    if not HAS_BOTO3:
        print("❌ boto3 is not installed. Install with: pip install boto3")
        return
    
    bucket_name = os.getenv("S3_BUCKET_NAME")
    if not bucket_name:
        print("⚠️  S3_BUCKET_NAME not set. Looking for orders-archive bucket...")
        # Try to find the bucket
        s3 = boto3.client('s3')
        response = s3.list_buckets()
        for bucket in response.get('Buckets', []):
            if 'orders-archive' in bucket['Name']:
                bucket_name = bucket['Name']
                break
    
    if not bucket_name:
        print("❌ Could not find orders-archive S3 bucket")
        return
    
    region = os.getenv("AWS_REGION", "us-west-2")
    s3 = boto3.client('s3', region_name=region)
    
    try:
        print(f"📦 Checking S3 bucket: {bucket_name}")
        print("=" * 60)
        
        response = s3.list_objects_v2(Bucket=bucket_name, MaxKeys=20)
        objects = response.get('Contents', [])
        
        if not objects:
            print("  No objects found yet. The connector may still be processing.")
            print("  Tip: Make sure the orders producer is running to generate data.")
            return
        
        print(f"  Found {len(objects)} object(s):")
        for obj in objects[:10]:  # Show first 10
            print(f"    📄 {obj['Key']} ({obj['Size']} bytes)")
        
        if len(objects) > 10:
            print(f"    ... and {len(objects) - 10} more")
            
    except Exception as e:
        print(f"❌ Error checking S3 bucket: {e}")


# ------------------------------------------------------
# Confluent Cloud Connect Functions (Target Cluster)
# ------------------------------------------------------

def get_connect_rest_url():
    """Get Kafka Connect REST API URL from environment"""
    connect_rest_url = os.getenv("KAFKA_CONNECT_REST_URL")
    if not connect_rest_url:
        print("⚠️  KAFKA_CONNECT_REST_URL not set.")
        print("   For Confluent Cloud, this is typically: https://<region>.api.confluent.cloud")
        return None
    return connect_rest_url


def get_connect_auth():
    """Get Kafka Connect authentication credentials"""
    api_key = os.getenv("KAFKA_CONNECT_API_KEY")
    api_secret = os.getenv("KAFKA_CONNECT_API_SECRET")
    
    if api_key and api_secret:
        return (api_key, api_secret)
    return None


def create_cc_connector(connector_name: str, connector_config: Dict[str, Any]) -> bool:
    """Create a Kafka Connect connector in Confluent Cloud"""
    connect_rest_url = get_connect_rest_url()
    if not connect_rest_url:
        print("❌ Kafka Connect REST URL not configured")
        return False
    
    auth = get_connect_auth()
    
    # Get the cluster ID from environment (for Confluent Cloud)
    cluster_id = os.getenv("KAFKA_CLUSTER_ID")
    if not cluster_id:
        print("⚠️  KAFKA_CLUSTER_ID not set. Using default endpoint.")
        url = f"{connect_rest_url}/connectors"
    else:
        url = f"{connect_rest_url}/connect/v1/environments/{os.getenv('ENVIRONMENT_ID')}/clusters/{cluster_id}/connectors"
    
    payload = {
        "name": connector_name,
        "config": connector_config
    }
    
    headers = {
        "Content-Type": "application/json"
    }
    
    try:
        response = requests.post(url, json=payload, headers=headers, auth=auth)
        
        if response.status_code == 200 or response.status_code == 201:
            result = response.json()
            print(f"✅ Connector '{connector_name}' created successfully in Confluent Cloud")
            print(f"   Status: {result.get('status', {}).get('state', 'UNKNOWN')}")
            return True
        elif response.status_code == 409:
            print(f"⚠️  Connector '{connector_name}' already exists")
            return True
        else:
            print(f"❌ Failed to create connector: {response.status_code}")
            print(f"   Response: {response.text}")
            return False
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Error connecting to Kafka Connect: {e}")
        return False


def get_s3_sink_connector_config() -> Dict[str, Any]:
    """Get configuration for S3 Sink connector in Confluent Cloud"""
    topic_name = os.getenv("TOPIC_NAME", "orders")
    s3_bucket = os.getenv("S3_BUCKET_NAME", "orders-archive")
    s3_region = os.getenv("AWS_REGION", "us-west-2")
    
    # For Confluent Cloud S3 Sink connector
    config = {
        "connector.class": "io.confluent.connect.s3.S3SinkConnector",
        "tasks.max": "1",
        "topics": topic_name,
        "s3.region": s3_region,
        "s3.bucket.name": s3_bucket,
        "s3.part.size": "5242880",
        "flush.size": "3",
        "storage.class": "io.confluent.connect.s3.storage.S3Storage",
        "format.class": "io.confluent.connect.s3.format.json.JsonFormat",
        "partitioner.class": "io.confluent.connect.storage.partitioner.TimeBasedPartitioner",
        "partition.duration.ms": "3600000",
        "path.format": "'year'=YYYY/'month'=MM/'day'=dd/'hour'=HH",
        "locale": "en-US",
        "timezone": "UTC",
        "schema.compatibility": "NONE"
    }
    
    # Add AWS credentials if provided
    aws_access_key_id = os.getenv("AWS_ACCESS_KEY_ID")
    aws_secret_access_key = os.getenv("AWS_SECRET_ACCESS_KEY")
    
    if aws_access_key_id and aws_secret_access_key:
        config["aws.access.key.id"] = aws_access_key_id
        config["aws.secret.access.key"] = aws_secret_access_key
    
    return config


def list_cc_connectors():
    """List all connectors in Confluent Cloud"""
    connect_rest_url = get_connect_rest_url()
    if not connect_rest_url:
        print("❌ Kafka Connect REST URL not configured")
        return
    
    auth = get_connect_auth()
    
    cluster_id = os.getenv("KAFKA_CLUSTER_ID")
    if not cluster_id:
        url = f"{connect_rest_url}/connectors"
    else:
        url = f"{connect_rest_url}/connect/v1/environments/{os.getenv('ENVIRONMENT_ID')}/clusters/{cluster_id}/connectors"
    
    try:
        response = requests.get(url, auth=auth)
        
        if response.status_code == 200:
            connectors = response.json()
            print("📋 Confluent Cloud Connectors:")
            print("=" * 60)
            if isinstance(connectors, list):
                for connector in connectors:
                    print(f"  - {connector}")
            else:
                print(f"  {connectors}")
        else:
            print(f"❌ Failed to list connectors: {response.status_code}")
            print(f"   Response: {response.text}")
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Error connecting to Kafka Connect: {e}")


def get_cc_connector_status(connector_name: str):
    """Get status of a specific connector in Confluent Cloud"""
    connect_rest_url = get_connect_rest_url()
    if not connect_rest_url:
        print("❌ Kafka Connect REST URL not configured")
        return
    
    auth = get_connect_auth()
    
    cluster_id = os.getenv("KAFKA_CLUSTER_ID")
    if not cluster_id:
        url = f"{connect_rest_url}/connectors/{connector_name}/status"
    else:
        url = f"{connect_rest_url}/connect/v1/environments/{os.getenv('ENVIRONMENT_ID')}/clusters/{cluster_id}/connectors/{connector_name}/status"
    
    try:
        response = requests.get(url, auth=auth)
        
        if response.status_code == 200:
            status = response.json()
            print(f"📊 Confluent Cloud Connector Status: {connector_name}")
            print("=" * 60)
            print(json.dumps(status, indent=2))
        else:
            print(f"❌ Failed to get connector status: {response.status_code}")
            print(f"   Response: {response.text}")
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Error connecting to Kafka Connect: {e}")


def print_usage():
    """Print usage information"""
    print("""
Usage: python3 setup_connector.py [command]

MSK Connect Commands (Source Cluster):
  msk-list          List all MSK Connect connectors
  msk-status        Get status of the orders S3 sink connector
  msk-status <name> Get status of a specific MSK Connect connector
  check-s3          Check if data is being written to S3

Confluent Cloud Commands (Target Cluster - after migration):
  cc-list           List all Confluent Cloud connectors
  cc-status <name>  Get status of a specific Confluent Cloud connector
  cc-create         Create the S3 sink connector in Confluent Cloud

No arguments:
  Shows this help message

Examples:
  python3 setup_connector.py msk-list
  python3 setup_connector.py msk-status
  python3 setup_connector.py check-s3
  python3 setup_connector.py cc-list
""")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print_usage()
        sys.exit(0)
    
    command = sys.argv[1].lower()
    
    # MSK Connect commands
    if command == "msk-list":
        list_msk_connectors()
    elif command == "msk-status":
        connector_name = sys.argv[2] if len(sys.argv) > 2 else None
        get_msk_connector_status(connector_name)
    elif command == "check-s3":
        check_s3_output()
    
    # Confluent Cloud commands
    elif command == "cc-list":
        list_cc_connectors()
    elif command == "cc-status":
        if len(sys.argv) > 2:
            get_cc_connector_status(sys.argv[2])
        else:
            print("❌ Please provide a connector name")
            print("   Usage: python3 setup_connector.py cc-status <connector_name>")
    elif command == "cc-create":
        print("🔌 Setting up S3 Sink Connector in Confluent Cloud")
        print("=" * 60)
        connector_name = os.getenv("CONNECTOR_NAME", "orders-s3-sink")
        connector_config = get_s3_sink_connector_config()
        print(f"Connector Name: {connector_name}")
        print("\n📋 Connector Configuration:")
        print(json.dumps(connector_config, indent=2))
        print("-" * 60)
        create_cc_connector(connector_name, connector_config)
    
    # Legacy/help commands
    elif command in ["help", "-h", "--help"]:
        print_usage()
    else:
        print(f"❌ Unknown command: {command}")
        print_usage()
        sys.exit(1)
