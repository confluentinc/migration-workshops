#!/bin/bash

# Setup script for Orders Producer/Consumer on EC2 Jump Server

echo "🚀 Setting up Orders Producer/Consumer for MSK Migration"
echo "============================================="

# Update system packages
echo "📦 Updating system packages..."
sudo yum update -y

# Install Python 3 and pip if not already installed
echo "🐍 Installing Python 3 and pip..."
sudo yum install -y python3 python3-pip

# Install required Python packages
echo "📚 Installing Python dependencies..."
sudo pip3 install kafka-python boto3 requests

# Make scripts executable
echo "🔧 Making scripts executable..."
chmod +x orders_producer.py
chmod +x orders_consumer.py
chmod +x setup_acls.py
chmod +x setup_schemas.py
chmod +x setup_connector.py
chmod +x setup_gateway.sh
chmod +x configure_gateway_target.sh

# Create logs directory
echo "📁 Creating logs directory..."
mkdir -p logs

# Create a simple topic creation script
echo "📝 Creating topic creation script..."
cat > create_topic.py << 'EOF'
#!/usr/bin/env python3
import sys
from kafka.admin import KafkaAdminClient, NewTopic
from kafka.errors import TopicAlreadyExistsError
from kafka_config import ConfigManager

def create_topic(topic_name="orders", num_partitions=3, replication_factor=3):
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
EOF

chmod +x create_topic.py

echo "✅ Setup complete!"
echo ""
echo "🔧 Next steps:"
echo "1. Source the MSK environment:  source env.msk"
echo "2. Deploy the Gateway:          ./setup_gateway.sh"
echo "3. Source the Gateway env:       source env.gateway"
echo "4. Start the producer:           python3 orders_producer.py"
echo "5. Start the consumer:           python3 orders_consumer.py"
echo ""
echo "🔄 Clients connect through Gateway for zero-cut migration"