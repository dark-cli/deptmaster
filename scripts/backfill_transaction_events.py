#!/usr/bin/env python3
"""
Backfill PostgreSQL events for existing transactions that don't have events
This creates TRANSACTION_CREATED events for all existing transactions
"""

import sys
import psycopg2
import json
from datetime import datetime
from pathlib import Path

def get_db_connection():
    """Get PostgreSQL connection"""
    return psycopg2.connect(
        host="localhost",
        port=5432,
        database="debt_tracker",
        user="postgres",
        password="postgres"
    )

def backfill_transaction_events():
    """Create events for transactions that don't have events"""
    
    conn = get_db_connection()
    cur = conn.cursor()
    
    try:
        # Get user ID
        cur.execute("SELECT id FROM users_projection LIMIT 1")
        user_row = cur.fetchone()
        if not user_row:
            print("❌ No user found in database")
            return
        user_id = user_row[0]
        
        # Get all transactions that don't have events
        cur.execute("""
            SELECT t.id, t.user_id, t.contact_id, t.type, t.direction, t.amount, 
                   t.currency, t.description, t.transaction_date, t.due_date, t.created_at
            FROM transactions_projection t
            WHERE t.is_deleted = false
            AND NOT EXISTS (
                SELECT 1 FROM events e 
                WHERE e.aggregate_type = 'transaction' 
                AND e.aggregate_id = t.id
                AND e.event_type = 'TRANSACTION_CREATED'
            )
            ORDER BY t.created_at
        """)
        
        transactions = cur.fetchall()
        
        if not transactions:
            print("✅ All transactions already have events")
            return
        
        print(f"📊 Found {len(transactions)} transactions without events")
        print("🔄 Creating events...")
        
        created_count = 0
        error_count = 0
        
        for txn in transactions:
            (txn_id, txn_user_id, contact_id, txn_type, direction, amount, 
             currency, description, txn_date, due_date, created_at) = txn
            
            # Create event data
            event_data = {
                "contact_id": str(contact_id),
                "type": txn_type,
                "direction": direction,
                "amount": amount,
                "currency": currency or "USD",
                "description": description,
                "transaction_date": txn_date.isoformat() if txn_date else datetime.now().date().isoformat(),
                "due_date": due_date.isoformat() if due_date else None,
                "comment": f"Backfilled event for existing transaction - Created: {created_at.isoformat()}",
                "timestamp": created_at.isoformat() if created_at else datetime.now().isoformat()
            }
            
            try:
                # Insert event
                cur.execute("""
                    INSERT INTO events (user_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
                    VALUES (%s, 'transaction', %s, 'TRANSACTION_CREATED', 1, %s, %s)
                    RETURNING id
                """, (str(user_id), str(txn_id), json.dumps(event_data), created_at or datetime.now()))
                
                event_id = cur.fetchone()[0]
                
                # Update transaction's last_event_id
                cur.execute("""
                    UPDATE transactions_projection 
                    SET last_event_id = %s 
                    WHERE id = %s
                """, (event_id, txn_id))
                
                created_count += 1
                
                if created_count % 50 == 0:
                    print(f"  ✅ Created {created_count} events...")
                    conn.commit()  # Commit in batches
                
            except Exception as e:
                error_count += 1
                print(f"  ❌ Error creating event for transaction {txn_id}: {e}")
                conn.rollback()
        
        conn.commit()
        
        print(f"✅ Backfill complete!")
        print(f"   - Created {created_count} events")
        if error_count > 0:
            print(f"   - {error_count} errors")
        
    except Exception as e:
        print(f"❌ Error during backfill: {e}")
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()

if __name__ == "__main__":
    print("🔄 Backfilling transaction events...")
    backfill_transaction_events()
    print("✅ Done!")
