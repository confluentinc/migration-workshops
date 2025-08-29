#!/usr/bin/env python3

import json
import signal
import sys
import argparse
from datetime import datetime
from typing import Dict, Any, Optional

from kafka import KafkaConsumer
from kafka.errors import KafkaError

from kafka_config import ConfigManager

class OrdersConsumer:
    def __init__(self, group_id: str = "orders-consumer-group"):
        self.config_manager = ConfigManager()
        self.consumer = None
        self.group_id = group_id
        self.running = True
        self.total_orders = 0
        self.total_value = 0.0
        
    def display_current_offsets(self):
        """Display current consumer group offsets"""
        try:
            if self.consumer:
                # Get current assignment
                assignment = self.consumer.assignment()
                if assignment:
                    print("📊 Current Consumer Group Offsets:")
                    for topic_partition in assignment:
                        position = self.consumer.position([topic_partition])
                        committed = self.consumer.committed([topic_partition])
                        print(f"   Topic: {topic_partition.topic}, "
                              f"Partition: {topic_partition.partition}, "
                              f"Current Position: {position[0] if position else 'N/A'}, "
                              f"Committed Offset: {committed[0] if committed else 'N/A'}")
                else:
                    print("📊 No partitions currently assigned to consumer")
                print("-" * 80)
        except Exception as e:
            print(f"⚠️  Could not display offsets: {e}")

    def setup_consumer(self):
        """Initialize Kafka consumer"""
        try:
            kafka_config = self.config_manager.get_kafka_config_dict()
            config = self.config_manager.get_active_config()
            
            # Add consumer-specific configurations
            consumer_config = {
                **kafka_config,
                'group_id': self.group_id,
                'value_deserializer': lambda m: json.loads(m.decode('utf-8')),
                'key_deserializer': lambda k: k.decode('utf-8') if k else None,
                'auto_offset_reset': 'earliest',
                'enable_auto_commit': True,
                'auto_commit_interval_ms': 1000,
                'session_timeout_ms': 30000,
                'heartbeat_interval_ms': 10000,
                'max_poll_records': 500,
                'fetch_min_bytes': 1,
                'fetch_max_wait_ms': 500
            }
            
            self.consumer = KafkaConsumer(
                config.topic_name,
                **consumer_config
            )
            
            print(f"✅ Consumer connected to: {kafka_config['bootstrap_servers']}")
            print(f"📊 Consumer group: {self.group_id}")
            print(f"📥 Subscribed to topic: {config.topic_name}")
            
        except Exception as e:
            print(f"❌ Failed to create consumer: {e}")
            raise
    
    def format_order(self, order: Dict[str, Any]) -> str:
        """Format order for display"""
        timestamp = datetime.fromisoformat(order['timestamp'].replace('Z', '+00:00'))
        formatted_time = timestamp.strftime('%Y-%m-%d %H:%M:%S')
        
        return (
            f"🛍️  Order #{order['order_id']:04d} | "
            f"Customer: {order['customer_id']} | "
            f"Product: {order['product_name']} | "
            f"Qty: {order['quantity']} | "
            f"Total: ${order['total_amount']:,.2f} | "
            f"Status: {order['status']} | "
            f"Time: {formatted_time}"
        )
    
    def process_order(self, message) -> bool:
        """Process a single order message"""
        try:
            order = message.value
            
            # Validate order structure
            required_fields = ['order_id', 'customer_id', 'total_amount', 'timestamp']
            if not all(field in order for field in required_fields):
                print(f"⚠️  Invalid order format: {order}")
                return False
            
            # Update statistics
            self.total_orders += 1
            self.total_value += order['total_amount']
            
            # Display offset information prominently
            print(f"📍 [Partition:{message.partition} | Offset:{message.offset} | Group:{self.group_id}]")
            
            # Display order
            print(self.format_order(order))
            
            # Show statistics every 10 orders
            if self.total_orders % 10 == 0:
                avg_value = self.total_value / self.total_orders
                print(f"📊 Statistics: {self.total_orders} orders, "
                      f"Total value: ${self.total_value:,.2f}, "
                      f"Average: ${avg_value:,.2f}")
                print("-" * 80)
            
            # Display offsets every 20 orders for monitoring
            if self.total_orders % 20 == 0:
                self.display_current_offsets()
            
            return True
            
        except json.JSONDecodeError as e:
            print(f"❌ JSON decode error: {e}")
            return False
        except Exception as e:
            print(f"❌ Error processing order: {e}")
            return False
    
    def signal_handler(self, signum, frame):
        """Handle graceful shutdown"""
        print(f"\n🛑 Received signal {signum}, shutting down gracefully...")
        self.running = False
    
    def run(self, timeout_ms: Optional[int] = 1000):
        """Run the consumer"""
        print(f"🚀 Starting Orders Consumer")
        print(f"📊 Environment: {self.config_manager.active_config}")
        print(f"👥 Consumer group: {self.group_id}")
        print(f"🔄 Press Ctrl+C to stop")
        print("=" * 80)
        
        # Setup signal handlers
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)
        
        try:
            self.setup_consumer()
            self.display_current_offsets() # Display offsets at startup
            
            print("🔍 Starting to consume orders...")
            print("-" * 80)
            
            while self.running:
                try:
                    message_batch = self.consumer.poll(timeout_ms=timeout_ms)
                    
                    if not message_batch:
                        continue
                    
                    for topic_partition, messages in message_batch.items():
                        for message in messages:
                            if not self.running:
                                break
                            
                            self.process_order(message)
                            
                except KafkaError as e:
                    print(f"❌ Kafka error: {e}")
                    if not self.running:
                        break
                except Exception as e:
                    print(f"❌ Unexpected error: {e}")
                    if not self.running:
                        break
                        
        except KeyboardInterrupt:
            print("\n🛑 Interrupted by user")
        except Exception as e:
            print(f"❌ Consumer error: {e}")
        finally:
            self.cleanup()
    
    def cleanup(self):
        """Clean up resources"""
        if self.consumer:
            print("🧹 Closing consumer...")
            self.consumer.close()
        
        print(f"📊 Final Statistics:")
        print(f"   Total orders processed: {self.total_orders}")
        print(f"   Total value: ${self.total_value:,.2f}")
        if self.total_orders > 0:
            avg_value = self.total_value / self.total_orders
            print(f"   Average order value: ${avg_value:,.2f}")
        print("✅ Consumer stopped")

def main():
    parser = argparse.ArgumentParser(description='Orders Consumer for Kafka')
    parser.add_argument('--group-id', type=str, default='orders-consumer-group',
                       help='Consumer group ID (default: orders-consumer-group)')
    parser.add_argument('--timeout', type=int, default=1000,
                       help='Poll timeout in milliseconds (default: 1000)')
    parser.add_argument('--env', choices=['msk', 'msk-scram', 'cc'], 
                       help='Kafka environment (overrides KAFKA_ENV)')
    
    args = parser.parse_args()
    
    # Override environment if specified
    if args.env:
        import os
        os.environ['KAFKA_ENV'] = args.env
    
    consumer = OrdersConsumer(group_id=args.group_id)
    consumer.run(timeout_ms=args.timeout)

if __name__ == "__main__":
    main() 