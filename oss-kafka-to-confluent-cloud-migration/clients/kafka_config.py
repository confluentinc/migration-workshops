import os
import sys
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
    """Resolves the active Kafka connection for the OSS-Kafka -> Confluent Cloud workshop.

    Three environments are used during the migration (all from the bastion):
      - oss:     SASL/SCRAM-SHA-512 over TLS directly to the source broker on EC2, verified
                 against the workshop CA
      - gateway: SASL/SCRAM-SHA-512 to the Confluent Gateway (passthrough to OSS Kafka
                 before cutover, swap to Confluent Cloud after)
      - cc:      SASL/PLAIN (API key) directly to Confluent Cloud over PrivateLink
    """

    def __init__(self):
        self.active_config = os.getenv("KAFKA_ENV", "oss")  # Default to the source cluster

    def get_oss_config(self) -> KafkaConfig:
        """Source broker on EC2: SASL_SSL with SCRAM-SHA-512, certificate signed by the workshop CA."""
        bootstrap_servers = os.getenv("OSS_BOOTSTRAP_SERVERS", "kafka.oss-workshop.internal:9092")

        sasl_username = os.getenv("OSS_SASL_USERNAME")
        sasl_password = os.getenv("OSS_SASL_PASSWORD")

        if not sasl_username or not sasl_password:
            raise ValueError("OSS_SASL_USERNAME and OSS_SASL_PASSWORD must be set for SCRAM authentication")

        return KafkaConfig(
            bootstrap_servers=bootstrap_servers,
            security_protocol="SASL_SSL",
            sasl_mechanism="SCRAM-SHA-512",
            sasl_username=sasl_username,
            sasl_password=sasl_password,
            ssl_ca_location=os.getenv("OSS_SSL_CAFILE"),
            client_id="orders-oss-scram-client"
        )

    def get_gateway_config(self) -> KafkaConfig:
        """Gateway configuration -- clients always connect here during migration.
        Uses SCRAM-SHA-512: passthrough to OSS Kafka before cutover, swap to CC after."""
        bootstrap_servers = os.getenv("GATEWAY_BOOTSTRAP_SERVERS", "localhost:9595")

        sasl_username = os.getenv("GATEWAY_SASL_USERNAME")
        sasl_password = os.getenv("GATEWAY_SASL_PASSWORD")

        if not sasl_username or not sasl_password:
            raise ValueError("GATEWAY_SASL_USERNAME and GATEWAY_SASL_PASSWORD must be set for Gateway authentication")

        return KafkaConfig(
            bootstrap_servers=bootstrap_servers,
            security_protocol="SASL_PLAINTEXT",
            sasl_mechanism="SCRAM-SHA-512",
            sasl_username=sasl_username,
            sasl_password=sasl_password,
            client_id="orders-gateway-client"
        )

    def get_confluent_cloud_config(self) -> KafkaConfig:
        """Confluent Cloud configuration (SASL/PLAIN with an API key/secret)."""
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
            "oss": self.get_oss_config,
            "gateway": self.get_gateway_config,
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
            'request_timeout_ms': 40000,  # Larger than session_timeout_ms
            'api_version': (2, 6, 0),  # Add API version for compatibility
            'connections_max_idle_ms': 540000,
        }

        if config.sasl_mechanism:
            kafka_config['sasl_mechanism'] = config.sasl_mechanism
            # PLAIN (Confluent Cloud) and SCRAM-SHA-512 (OSS / Gateway) both use
            # username/password, which kafka-python takes as sasl_plain_*.
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
            'request.timeout.ms': 40000,
            'socket.timeout.ms': 30000,
        }

        if config.sasl_mechanism:
            kafka_config['sasl.mechanism'] = config.sasl_mechanism

        if config.sasl_username:
            kafka_config['sasl.username'] = config.sasl_username

        if config.sasl_password:
            kafka_config['sasl.password'] = config.sasl_password

        if config.ssl_ca_location:
            kafka_config['ssl.ca.location'] = config.ssl_ca_location

        return kafka_config


if __name__ == "__main__":
    # Prints the resolved settings for KAFKA_ENV; with --check, also connects and lists topics.
    mgr = ConfigManager()
    cfg = mgr.get_active_config()
    print(f"KAFKA_ENV         = {mgr.active_config}")
    print(f"bootstrap_servers = {cfg.bootstrap_servers}")
    print(f"security_protocol = {cfg.security_protocol}")
    print(f"sasl_mechanism    = {cfg.sasl_mechanism}")
    print(f"client_id         = {cfg.client_id}")
    print(f"topic_name        = {cfg.topic_name}")

    if "--check" in sys.argv[1:]:
        from kafka.admin import KafkaAdminClient
        admin = KafkaAdminClient(**mgr.get_kafka_config_dict())
        try:
            print(f"connected; topics = {sorted(admin.list_topics())}")
        finally:
            admin.close()
