import os
from dataclasses import dataclass
from typing import Dict, Any

@dataclass
class KafkaConfig:
    bootstrap_servers: str
    security_protocol: str
    sasl_mechanism: str = None
    sasl_username: str = None
    sasl_password: str = None
    ssl_ca_location: str = None
    client_id: str = "orders-client"
    topic_name: str = "orders"

class ConfigManager:
    def __init__(self):
        self.active_config = os.getenv("KAFKA_ENV", "msk")  # Default to MSK
    
    def get_msk_config(self) -> KafkaConfig:
        """MSK configuration with SASL/IAM (default for MSK)"""
        bootstrap_servers = os.getenv("MSK_BOOTSTRAP_SERVERS")
        if not bootstrap_servers:
            raise ValueError("MSK_BOOTSTRAP_SERVERS environment variable is not set")
        
        return KafkaConfig(
            bootstrap_servers=bootstrap_servers,
            security_protocol="SASL_SSL",
            sasl_mechanism="AWS_MSK_IAM",
            client_id="orders-msk-iam-client"
        )
    
    def get_msk_scram_config(self) -> KafkaConfig:
        """MSK configuration with SASL/SCRAM-SHA-512"""
        bootstrap_servers = os.getenv("MSK_BOOTSTRAP_SERVERS")
        if not bootstrap_servers:
            raise ValueError("MSK_BOOTSTRAP_SERVERS environment variable is not set")
        
        sasl_username = os.getenv("MSK_SASL_USERNAME")
        sasl_password = os.getenv("MSK_SASL_PASSWORD")
        
        if not sasl_username or not sasl_password:
            raise ValueError("MSK_SASL_USERNAME and MSK_SASL_PASSWORD must be set for SCRAM authentication")
        
        return KafkaConfig(
            bootstrap_servers=bootstrap_servers,
            security_protocol="SASL_SSL",
            sasl_mechanism="SCRAM-SHA-512",
            sasl_username=sasl_username,
            sasl_password=sasl_password,
            client_id="orders-msk-scram-client"
        )
    
    def get_confluent_cloud_config(self) -> KafkaConfig:
        """Confluent Cloud configuration"""
        bootstrap_servers = os.getenv("CC_BOOTSTRAP_SERVERS")
        if not bootstrap_servers:
            raise ValueError("CC_BOOTSTRAP_SERVERS environment variable is not set")
        
        api_key = os.getenv("CC_API_KEY")
        api_secret = os.getenv("CC_API_SECRET")
        
        if not api_key or not api_secret:
            raise ValueError("CC_API_KEY and CC_API_SECRET must be set for Confluent Cloud authentication")
        
        return KafkaConfig(
            bootstrap_servers=bootstrap_servers,
            security_protocol="SASL_SSL",
            sasl_mechanism="PLAIN",
            sasl_username=api_key,
            sasl_password=api_secret,
            client_id="orders-cc-client"
        )
    
    def get_active_config(self) -> KafkaConfig:
        """Get the currently active configuration"""
        config_map = {
            "msk": self.get_msk_config,
            "msk-scram": self.get_msk_scram_config,
            "cc": self.get_confluent_cloud_config
        }
        
        if self.active_config not in config_map:
            raise ValueError(f"Unknown config: {self.active_config}")
        
        return config_map[self.active_config]()
    
    def get_kafka_config_dict(self) -> Dict[str, Any]:
        """Get configuration as dictionary for kafka-python"""
        config = self.get_active_config()
        
        kafka_config = {
            'bootstrap_servers': config.bootstrap_servers,
            'security_protocol': config.security_protocol,
            'client_id': config.client_id,
            'request_timeout_ms': 40000,  # Increased from 30000 to be larger than session_timeout_ms
            'api_version': (2, 6, 0),  # Add API version for compatibility
            'connections_max_idle_ms': 540000,
        }
        
        if config.sasl_mechanism:
            kafka_config['sasl_mechanism'] = config.sasl_mechanism
            
            # Handle AWS MSK IAM authentication
            if config.sasl_mechanism == "AWS_MSK_IAM":
                # For AWS MSK IAM, we need to use the aws-msk-iam-sasl-signer-go library
                # This will be handled by the aws-msk-iam-sasl-signer-go package
                pass
            elif config.sasl_mechanism == "PLAIN":
                # For PLAIN mechanism (Confluent Cloud)
                if config.sasl_username:
                    kafka_config['sasl_plain_username'] = config.sasl_username
                if config.sasl_password:
                    kafka_config['sasl_plain_password'] = config.sasl_password
            elif config.sasl_mechanism == "SCRAM-SHA-512":
                # For SCRAM-SHA-512 mechanism (MSK SCRAM)
                if config.sasl_username:
                    kafka_config['sasl_plain_username'] = config.sasl_username
                if config.sasl_username:
                    kafka_config['sasl_plain_password'] = config.sasl_password
            else:
                # For other SASL mechanisms
                if config.sasl_username:
                    kafka_config['sasl_plain_username'] = config.sasl_username
                if config.sasl_password:
                    kafka_config['sasl_plain_password'] = config.sasl_password
        
        if config.ssl_ca_location:
            kafka_config['ssl_cafile'] = config.ssl_ca_location
        
        return kafka_config
    
    def get_confluent_kafka_config_dict(self) -> Dict[str, Any]:
        """Get configuration as dictionary for confluent-kafka library"""
        config = self.get_active_config()
        
        kafka_config = {
            'bootstrap.servers': config.bootstrap_servers,
            'security.protocol': config.security_protocol,
            'client.id': config.client_id,
            'request.timeout.ms': 40000,  # Increased from 30000 to be larger than session timeout
            'socket.timeout.ms': 30000,
        }
        
        if config.sasl_mechanism:
            kafka_config['sasl.mechanism'] = config.sasl_mechanism
        
        if config.sasl_username:
            kafka_config['sasl.username'] = config.sasl_username
        
        if config.sasl_password:
            kafka_config['sasl.password'] = config.sasl_password
        
        return kafka_config 
