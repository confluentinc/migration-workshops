#!/usr/bin/env python3

import json
import time
import random
from datetime import datetime
from typing import Dict, Any
import argparse
import signal
import sys

from kafka import KafkaProducer
from kafka.errors import KafkaError

from kafka_config import ConfigManager

class OrdersProducer:
    def __init__(self):
        self.config_manager = ConfigManager()
        self.producer = None
        self.order_counter = 1
        self.running = True
        
        # Sample data for realistic orders
        self.customers = [
            "customer_001", "customer_002", "customer_003", "customer_004", "customer_005",
            "customer_006", "customer_007", "customer_008", "customer_009", "customer_010"
        ]
        
        self.products = [
            {"id": "prod_001", "name": "Laptop", "price": 1299.99},
            {"id": "prod_002", "name": "Mouse", "price": 29.99},
            {"id": "prod_003", "name": "Keyboard", "price": 89.99},
            {"id": "prod_004", "name": "Monitor", "price": 299.99},
            {"id": "prod_005", "name": "Headphones", "price": 149.99}
        ]
        
        self.statuses = ["pending", "processing", "shipped", "delivered"]
        
    def setup_producer(self):
        """Initialize Kafka producer"""
        try:
            kafka_config = self.config_manager.get_kafka_config_dict()
            
            # Add producer-specific configurations
            producer_config = {
                **kafka_config,
                'value_serializer': lambda v: json.dumps(v).encode('utf-8'),
                'key_serializer': lambda k: str(k).encode('utf-8'),
                'acks': 'all',
                'retries': 3,
                'retry_backoff_ms': 1000,
                'batch_size': 16384,
                'linger_ms': 10,
                'compression_type': 'gzip'
            }
            
            self.producer = KafkaProducer(**producer_config)
            print(f"✅ Producer connected to: {kafka_config['bootstrap_servers']}")
            
        except Exception as e:
            print(f"❌ Failed to create producer: {e}")
            raise
    
    def generate_order(self) -> Dict[str, Any]:
        """Generate a realistic order"""
        product = random.choice(self.products)
        quantity = random.randint(1, 5)
        
        order = {
            "order_id": self.order_counter,
            "customer_id": random.choice(self.customers),
            "product_id": product["id"],
            "product_name": product["name"],
            "quantity": quantity,
            "unit_price": product["price"],
            "total_amount": round(product["price"] * quantity, 2),
            "status": random.choice(self.statuses),
            "timestamp": datetime.utcnow().isoformat(),
            "region": "us-west-2",
            "payment_method": random.choice(["credit_card", "debit_card", "paypal", "apple_pay"])
        }
        
        self.order_counter += 1
        return order
    
    def send_order(self, order: Dict[str, Any]) -> bool:
        """Send order to Kafka topic"""
        try:
            config = self.config_manager.get_active_config()
            
            future = self.producer.send(
                config.topic_name,
                key=order["order_id"],
                value=order
            )
            
            # Wait for message to be sent
            result = future.get(timeout=10)
            
            print(f"📦 Sent order {order['order_id']}: ${order['total_amount']:.2f} "
                  f"to {result.topic} partition {result.partition} offset {result.offset}")
            
            return True
            
        except KafkaError as e:
            print(f"❌ Failed to send order {order['order_id']}: {e}")
            return False
        except Exception as e:
            print(f"❌ Unexpected error sending order {order['order_id']}: {e}")
            return False
    
    def signal_handler(self, signum, frame):
        """Handle graceful shutdown"""
        print(f"\n🛑 Received signal {signum}, shutting down gracefully...")
        self.running = False
    
    def run(self, interval: float = 1.0, max_orders: int = None):
        """Run the producer"""
        print(f"🚀 Starting Orders Producer")
        print(f"📊 Environment: {self.config_manager.active_config}")
        print(f"⏱️  Interval: {interval} seconds")
        print(f"📈 Max orders: {max_orders or 'unlimited'}")
        print(f"🔄 Press Ctrl+C to stop")
        print("-" * 50)
        
        # Setup signal handlers
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)
        
        try:
            self.setup_producer()
            
            orders_sent = 0
            while self.running:
                if max_orders and orders_sent >= max_orders:
                    print(f"✅ Reached maximum orders ({max_orders}), stopping...")
                    break
                
                order = self.generate_order()
                if self.send_order(order):
                    orders_sent += 1
                
                time.sleep(interval)
                
        except KeyboardInterrupt:
            print("\n🛑 Interrupted by user")
        except Exception as e:
            print(f"❌ Producer error: {e}")
        finally:
            self.cleanup()
    
    def cleanup(self):
        """Clean up resources"""
        if self.producer:
            print("🧹 Flushing and closing producer...")
            self.producer.flush()
            self.producer.close()
        print("✅ Producer stopped")

def main():
    parser = argparse.ArgumentParser(description='Orders Producer for Kafka')
    parser.add_argument('--interval', type=float, default=1.0, 
                       help='Interval between orders in seconds (default: 1.0)')
    parser.add_argument('--max-orders', type=int, default=None,
                       help='Maximum number of orders to send (default: unlimited)')
    parser.add_argument('--env', choices=['msk', 'msk-scram', 'cc'], 
                       help='Kafka environment (overrides KAFKA_ENV)')
    
    args = parser.parse_args()
    
    # Override environment if specified
    if args.env:
        import os
        os.environ['KAFKA_ENV'] = args.env
    
    producer = OrdersProducer()
    producer.run(interval=args.interval, max_orders=args.max_orders)

if __name__ == "__main__":
    main() 
