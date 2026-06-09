#!/usr/bin/env python3
"""
Script to register schemas in Schema Registry for the orders topic.
This script registers both key and value schemas for Avro serialization.
"""

import os
import json
import sys
import requests
from typing import Dict, Any

def get_schema_registry_url():
    """Get Schema Registry URL from environment or use default"""
    # For MSK, Schema Registry is typically not included, so we'll use Confluent Cloud Schema Registry
    # In a real scenario, you might have a separate Schema Registry instance
    schema_registry_url = os.getenv("SCHEMA_REGISTRY_URL")
    if not schema_registry_url:
        print("⚠️  SCHEMA_REGISTRY_URL not set. Using Confluent Cloud Schema Registry.")
        print("   Set SCHEMA_REGISTRY_URL environment variable if using a different registry.")
        return None
    return schema_registry_url

def get_schema_registry_auth():
    """Get Schema Registry authentication credentials"""
    api_key = os.getenv("SCHEMA_REGISTRY_API_KEY")
    api_secret = os.getenv("SCHEMA_REGISTRY_API_SECRET")
    
    if api_key and api_secret:
        return (api_key, api_secret)
    return None

def register_schema(subject: str, schema: Dict[str, Any], schema_type: str = "AVRO") -> bool:
    """Register a schema in Schema Registry"""
    schema_registry_url = get_schema_registry_url()
    if not schema_registry_url:
        print("❌ Schema Registry URL not configured")
        return False
    
    auth = get_schema_registry_auth()
    
    url = f"{schema_registry_url}/subjects/{subject}/versions"
    
    payload = {
        "schema": json.dumps(schema),
        "schemaType": schema_type
    }
    
    headers = {
        "Content-Type": "application/vnd.schemaregistry.v1+json"
    }
    
    try:
        response = requests.post(url, json=payload, headers=headers, auth=auth)
        
        if response.status_code == 200 or response.status_code == 201:
            result = response.json()
            print(f"✅ Schema registered for subject '{subject}'")
            print(f"   Schema ID: {result.get('id')}")
            print(f"   Version: {result.get('version')}")
            return True
        elif response.status_code == 409:
            print(f"⚠️  Schema already exists for subject '{subject}'")
            # Try to get the existing schema
            get_url = f"{schema_registry_url}/subjects/{subject}/versions/latest"
            get_response = requests.get(get_url, auth=auth)
            if get_response.status_code == 200:
                existing = get_response.json()
                print(f"   Existing Schema ID: {existing.get('id')}")
                print(f"   Existing Version: {existing.get('version')}")
            return True
        else:
            print(f"❌ Failed to register schema: {response.status_code}")
            print(f"   Response: {response.text}")
            return False
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Error connecting to Schema Registry: {e}")
        return False

def get_orders_value_schema() -> Dict[str, Any]:
    """Get the Avro schema for orders value"""
    return {
        "type": "record",
        "name": "Order",
        "namespace": "com.example.orders",
        "fields": [
            {"name": "order_id", "type": "int"},
            {"name": "customer_id", "type": "string"},
            {"name": "product_id", "type": "string"},
            {"name": "product_name", "type": "string"},
            {"name": "quantity", "type": "int"},
            {"name": "unit_price", "type": "double"},
            {"name": "total_amount", "type": "double"},
            {"name": "status", "type": "string"},
            {"name": "timestamp", "type": "string"},
            {"name": "region", "type": "string"},
            {"name": "payment_method", "type": "string"}
        ]
    }

def get_orders_key_schema() -> Dict[str, Any]:
    """Get the Avro schema for orders key (order_id)"""
    return {
        "type": "int"
    }

def setup_schemas():
    """Set up schemas for the orders topic"""
    print("📋 Setting up schemas in Schema Registry")
    print("=" * 60)
    
    topic_name = os.getenv("TOPIC_NAME", "orders")
    
    # Schema Registry subject naming convention: <topic-name>-key or <topic-name>-value
    key_subject = f"{topic_name}-key"
    value_subject = f"{topic_name}-value"
    
    print(f"Topic: {topic_name}")
    print(f"Key Subject: {key_subject}")
    print(f"Value Subject: {value_subject}")
    print("-" * 60)
    
    # Register key schema
    print("\n🔑 Registering key schema...")
    key_schema = get_orders_key_schema()
    key_success = register_schema(key_subject, key_schema)
    
    # Register value schema
    print("\n📦 Registering value schema...")
    value_schema = get_orders_value_schema()
    value_success = register_schema(value_subject, value_schema)
    
    if key_success and value_success:
        print("\n✅ All schemas registered successfully!")
        return True
    else:
        print("\n❌ Some schemas failed to register")
        return False

def list_schemas():
    """List all registered schemas"""
    schema_registry_url = get_schema_registry_url()
    if not schema_registry_url:
        print("❌ Schema Registry URL not configured")
        return
    
    auth = get_schema_registry_auth()
    
    try:
        url = f"{schema_registry_url}/subjects"
        response = requests.get(url, auth=auth)
        
        if response.status_code == 200:
            subjects = response.json()
            print("📋 Registered Schema Subjects:")
            print("=" * 60)
            for subject in subjects:
                print(f"  - {subject}")
        else:
            print(f"❌ Failed to list schemas: {response.status_code}")
            print(f"   Response: {response.text}")
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Error connecting to Schema Registry: {e}")

def glue_list_schemas():
    """List schemas in the AWS Glue Schema Registry"""
    import boto3

    registry_name = os.getenv("GLUE_REGISTRY_NAME", "dev-msk-schemas")
    region = os.getenv("AWS_REGION", os.getenv("AWS_DEFAULT_REGION", "us-west-2"))

    client = boto3.client("glue", region_name=region)

    print(f"Glue Schema Registry: {registry_name}")
    print("=" * 60)

    try:
        response = client.list_schemas(
            RegistryId={"RegistryName": registry_name},
            MaxResults=100
        )
        schemas = response.get("Schemas", [])
        if not schemas:
            print("  No schemas found.")
            return

        for schema in schemas:
            name = schema.get("SchemaName", "unknown")
            status = schema.get("SchemaStatus", "unknown")
            print(f"  - {name}  (status: {status})")

            # Get latest version details
            try:
                version_resp = client.get_schema_version(
                    SchemaId={
                        "RegistryName": registry_name,
                        "SchemaName": name
                    },
                    SchemaVersionNumber={"LatestVersion": True}
                )
                print(f"    Format: {version_resp.get('DataFormat', 'N/A')}")
                print(f"    Version: {version_resp.get('VersionNumber', 'N/A')}")
            except Exception:
                pass

    except Exception as e:
        print(f"Error listing Glue schemas: {e}")

def glue_verify_schemas():
    """Verify that expected orders schemas exist in Glue"""
    import boto3

    registry_name = os.getenv("GLUE_REGISTRY_NAME", "dev-msk-schemas")
    region = os.getenv("AWS_REGION", os.getenv("AWS_DEFAULT_REGION", "us-west-2"))

    client = boto3.client("glue", region_name=region)

    expected = ["orders-key", "orders-value"]
    all_ok = True

    print(f"Verifying schemas in Glue registry: {registry_name}")
    print("=" * 60)

    for schema_name in expected:
        try:
            resp = client.get_schema_version(
                SchemaId={
                    "RegistryName": registry_name,
                    "SchemaName": schema_name
                },
                SchemaVersionNumber={"LatestVersion": True}
            )
            print(f"  [OK] {schema_name}")
            print(f"       Format: {resp.get('DataFormat')}, Version: {resp.get('VersionNumber')}")
        except client.exceptions.EntityNotFoundException:
            print(f"  [MISSING] {schema_name}")
            all_ok = False
        except Exception as e:
            print(f"  [ERROR] {schema_name}: {e}")
            all_ok = False

    print()
    if all_ok:
        print("All expected schemas found.")
    else:
        print("Some schemas are missing. Check your Terraform deployment.")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        if cmd == "list":
            list_schemas()
        elif cmd == "glue-list":
            glue_list_schemas()
        elif cmd == "glue-verify":
            glue_verify_schemas()
        else:
            print(f"Unknown command: {cmd}")
            print("Usage: setup_schemas.py [list|glue-list|glue-verify]")
            sys.exit(1)
    else:
        setup_schemas()
