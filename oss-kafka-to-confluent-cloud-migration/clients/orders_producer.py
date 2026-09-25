#!/usr/bin/env python3

import json
import time
import random
from datetime import datetime, timezone
from typing import Dict, Any
import argparse
import signal
import sys

from kafka import KafkaProducer
from kafka.errors import KafkaError

from kafka_config import ConfigManager

import warnings

# kafka-python 3.x warns that our lambda (de)serializers don't subclass
# kafka.serializer.Serializer. That's intentional for this workshop and the version is
# pinned, so silence just that one deprecation to keep the output readable.
warnings.filterwarnings(
    "ignore",
    message=r"(key|value)_(de)?serializer does not implement",
    category=DeprecationWarning,
)

class OrdersProducer:
    def __init__(self):
        self.config_manager = ConfigManager()
        self.producer = None
        self.order_counter = 1
        self.running = True

        # Delivery accounting so a failed send is never silently dropped.
        self.delivered = 0
        self.failed_attempts = 0
        self.pending_order = None      # a generated order not yet confirmed delivered
        self.last_delivered_id = None

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
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "region": "aws",
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

            while self.running:
                if max_orders and self.delivered >= max_orders:
                    print(f"✅ Reached maximum delivered orders ({max_orders}), stopping...")
                    break

                # Reuse the previously-generated order if its last send failed, so a
                # transient failure retries the SAME order instead of moving on and
                # dropping it. This is at-least-once: a send that fails after the broker
                # persisted the record may therefore be redelivered — see the note on
                # duplication in STEP-4.
                order = self.pending_order if self.pending_order is not None else self.generate_order()

                if self.send_order(order):
                    self.delivered += 1
                    self.last_delivered_id = order["order_id"]
                    self.pending_order = None
                else:
                    self.pending_order = order
                    self.failed_attempts += 1

                time.sleep(interval)

        except KeyboardInterrupt:
            print("\n🛑 Interrupted by user")
        except Exception as e:
            print(f"❌ Producer error: {e}")
        finally:
            self.cleanup()

    def cleanup(self):
        """Clean up resources and report delivery outcomes."""
        if self.producer:
            print("🧹 Flushing and closing producer...")
            self.producer.flush()
            self.producer.close()

        print("📊 Delivery summary:")
        print(f"   Orders confirmed delivered: {self.delivered}")
        print(f"   Last delivered order_id:    {self.last_delivered_id}")
        print(f"   Failed send attempts:       {self.failed_attempts}")
        if self.pending_order is not None:
            print(f"   ⚠️  Order {self.pending_order['order_id']} was generated but NOT "
                  f"confirmed delivered before shutdown.")
        print("✅ Producer stopped")

def main():
    parser = argparse.ArgumentParser(description='Orders Producer for Kafka')
    parser.add_argument('--interval', type=float, default=1.0,
                       help='Interval between orders in seconds (default: 1.0)')
    parser.add_argument('--max-orders', type=int, default=None,
                       help='Maximum number of orders to send (default: unlimited)')
    parser.add_argument('--env', choices=['oss', 'gateway', 'cc'],
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
