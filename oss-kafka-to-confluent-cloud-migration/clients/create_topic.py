#!/usr/bin/env python3
"""Create the orders topic in whichever environment KAFKA_ENV points at.

Replication factor defaults to 1 because the source OSS Kafka broker is a single
node. Override with REPLICATION_FACTOR if you point this at a multi-broker cluster.
"""
import os
import sys
from kafka.admin import KafkaAdminClient, NewTopic
from kafka.errors import TopicAlreadyExistsError
from kafka_config import ConfigManager

def create_topic(topic_name="orders", num_partitions=3, replication_factor=None):
    if replication_factor is None:
        replication_factor = int(os.getenv("REPLICATION_FACTOR", "1"))

    config_manager = ConfigManager()
    kafka_config = config_manager.get_kafka_config_dict()

    admin_client = KafkaAdminClient(**kafka_config)

    topic = NewTopic(
        name=topic_name,
        num_partitions=num_partitions,
        replication_factor=replication_factor
    )

    try:
        admin_client.create_topics([topic])
        print(f"✅ Topic '{topic_name}' created successfully")
    except TopicAlreadyExistsError:
        print(f"⚠️  Topic '{topic_name}' already exists")
    except Exception as e:
        print(f"❌ Error creating topic: {e}")
    finally:
        admin_client.close()

if __name__ == "__main__":
    if len(sys.argv) > 1:
        create_topic(sys.argv[1])
    else:
        create_topic()
