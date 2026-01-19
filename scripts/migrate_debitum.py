#!/usr/bin/env python3
"""
Migrate Debitum SQLite database to Debt Tracker PostgreSQL event-sourced database
"""

import sys
import sqlite3
import psycopg2
import json
import uuid
import re
from datetime import datetime
from pathlib import Path

def get_db_connection():
    """Get PostgreSQL connection"""
    return psycopg2.connect(
        host="localhost",
        port=5432,
        database="debt_tracker",
        user="debt_tracker",
        password="dev_password"
    )

def extract_username(name):
    """
    Extract username (English letters and numbers) from contact name.
    
    Args:
        name: Contact name string (may contain Arabic, English, numbers)
    
    Returns:
        Extracted username string, or None if no username found
    """
    if not name:
        return None
    
    # Find all sequences of English letters and numbers
    matches = re.findall(r'[a-zA-Z0-9]+', name)
    
    if not matches:
        return None
    
    # Join all matches (in case username is split by spaces or other chars)
    username = ''.join(matches)
    
    # Return None if empty, otherwise return the extracted username
    return username if username else None

def split_name_and_username(full_name):
    """
    Split a contact name into name (without username) and username.
    
    Args:
        full_name: Full contact name that may contain username
    
    Returns:
        Tuple of (name_without_username, username)
        - name_without_username: Original name with username removed, or original if no username
        - username: Extracted username, or None
    """
    if not full_name:
        return (None, None)
    
    username = extract_username(full_name)
    
    if not username:
        return (full_name, None)
    
    # Remove the username from the name
    # Replace the username pattern with empty string
    name_without_username = re.sub(r'[a-zA-Z0-9]+', '', full_name)
    name_without_username = re.sub(r'\s+', ' ', name_without_username).strip()
    
    # If after removing username, name is empty, keep original name
    if not name_without_username:
        name_without_username = full_name
    
    return (name_without_username, username)

def migrate_debitum(debitum_db_path):
    """Migrate Debitum data to Debt Tracker"""
    
    print(f"📊 Reading Debitum database: {debitum_db_path}")
    
    # Connect to Debitum SQLite
    debitum_conn = sqlite3.connect(debitum_db_path)
    debitum_conn.row_factory = sqlite3.Row
    debitum_cur = debitum_conn.cursor()
    
    # Connect to Debt Tracker PostgreSQL
    pg_conn = get_db_connection()
    pg_cur = pg_conn.cursor()
    
    try:
        # First, check if database has any existing data (should be empty after RESET_DATABASE.sh)
        pg_cur.execute("SELECT COUNT(*) FROM transactions_projection")
        total_txns = pg_cur.fetchone()[0]
        pg_cur.execute("SELECT COUNT(*) FROM contacts_projection")
        total_contacts = pg_cur.fetchone()[0]
        
        if total_txns > 0 or total_contacts > 0:
            print(f"⚠️  WARNING: Database already contains {total_txns} transactions and {total_contacts} contacts!")
            print("   This script should be run after RESET_DATABASE.sh which drops and recreates the database.")
            print("   Existing data will be cleared for the 'max' user, but other users' data will remain.")
            print("   Proceeding with clearing and re-importing data for 'max' user...")
        
        # Find or create the "max" user
        pg_cur.execute("SELECT id FROM users_projection WHERE email = 'max' LIMIT 1")
        user_row = pg_cur.fetchone()
        
        if user_row:
            user_id = uuid.UUID(user_row[0])
            print(f"👤 Using existing user 'max': {user_id}")
        else:
            # Create the "max" user if it doesn't exist
            user_id = uuid.uuid4()
            print(f"👤 Creating user 'max': {user_id}")
            pg_cur.execute("""
                INSERT INTO users_projection (id, email, password_hash, created_at, last_event_id)
                VALUES (%s, %s, %s, %s, 0)
            """, (str(user_id), "max", "$2b$12$MzvHQ6CeZgenzzwkEV2WeeDQscVKQed1kTh8NxB7w2bXCXe2qFjxK", datetime.now()))
            pg_conn.commit()
        
        # Clear existing data for this user (but keep the user)
        print("🗑️  Clearing existing data...")
        
        # Use TRUNCATE CASCADE for more reliable deletion (faster and handles foreign keys)
        # But we need to be careful - we only want to delete data for this user
        # So we'll use DELETE with proper ordering instead
        
        # First, verify we're starting clean by counting existing records
        pg_cur.execute("SELECT COUNT(*) FROM transactions_projection WHERE user_id = %s", (str(user_id),))
        existing_txns = pg_cur.fetchone()[0]
        pg_cur.execute("SELECT COUNT(*) FROM contacts_projection WHERE user_id = %s", (str(user_id),))
        existing_contacts = pg_cur.fetchone()[0]
        pg_cur.execute("SELECT COUNT(*) FROM events WHERE user_id = %s", (str(user_id),))
        existing_events = pg_cur.fetchone()[0]
        
        print(f"  📊 Existing records: {existing_txns} transactions, {existing_contacts} contacts, {existing_events} events")
        
        # Delete in order: dependent tables first, then main tables
        # Delete transaction images (if table exists)
        try:
            pg_cur.execute("""
                DELETE FROM transaction_images_projection 
                WHERE transaction_id IN (SELECT id FROM transactions_projection WHERE user_id = %s)
            """, (str(user_id),))
            if pg_cur.rowcount > 0:
                print(f"  ✅ Deleted {pg_cur.rowcount} transaction images")
        except Exception as e:
            print(f"  ⚠️  Could not delete transaction images: {e}")
        
        # Delete reminders
        try:
            pg_cur.execute("""
                DELETE FROM reminders_projection 
                WHERE user_id = %s
            """, (str(user_id),))
            if pg_cur.rowcount > 0:
                print(f"  ✅ Deleted {pg_cur.rowcount} reminders")
        except Exception as e:
            print(f"  ⚠️  Could not delete reminders: {e}")
        
        # Delete transactions (must be before contacts due to foreign key)
        pg_cur.execute("""
            DELETE FROM transactions_projection 
            WHERE user_id = %s
        """, (str(user_id),))
        print(f"  ✅ Deleted {pg_cur.rowcount} transactions")
        
        # Delete contacts
        pg_cur.execute("""
            DELETE FROM contacts_projection 
            WHERE user_id = %s
        """, (str(user_id),))
        print(f"  ✅ Deleted {pg_cur.rowcount} contacts")
        
        # Delete events
        pg_cur.execute("""
            DELETE FROM events 
            WHERE user_id = %s
        """, (str(user_id),))
        print(f"  ✅ Deleted {pg_cur.rowcount} events")
        
        # Delete snapshots
        try:
            pg_cur.execute("""
                DELETE FROM snapshots 
                WHERE user_id = %s
            """, (str(user_id),))
            if pg_cur.rowcount > 0:
                print(f"  ✅ Deleted {pg_cur.rowcount} snapshots")
        except Exception as e:
            print(f"  ⚠️  Could not delete snapshots: {e}")
        
        pg_conn.commit()
        
        # Verify deletion
        pg_cur.execute("SELECT COUNT(*) FROM transactions_projection WHERE user_id = %s", (str(user_id),))
        remaining_txns = pg_cur.fetchone()[0]
        pg_cur.execute("SELECT COUNT(*) FROM contacts_projection WHERE user_id = %s", (str(user_id),))
        remaining_contacts = pg_cur.fetchone()[0]
        
        if remaining_txns > 0 or remaining_contacts > 0:
            print(f"  ⚠️  WARNING: Still have {remaining_txns} transactions and {remaining_contacts} contacts after deletion!")
        else:
            print("✅ Existing data cleared (verified)")
        
        # Migrate persons to contacts
        print("📇 Migrating contacts...")
        debitum_cur.execute("SELECT * FROM person ORDER BY id_person")
        persons = debitum_cur.fetchall()
        
        contact_map = {}  # Map old person ID to new contact UUID
        event_counter = 0
        
        for person in persons:
            contact_id = uuid.uuid4()
            contact_map[person['id_person']] = contact_id
            event_counter += 1
            
            # Extract username from name
            original_name = person['name'] or ''
            contact_name, username = split_name_and_username(original_name)
            
            # Ensure we have at least a name (fallback to original if extraction resulted in empty)
            if not contact_name or contact_name.strip() == '':
                contact_name = original_name
            
            # Create event
            event_data = {
                "name": contact_name,
                "username": username,
                "phone": person['linked_contact_uri'] if person['linked_contact_uri'] else None,
                "email": None,
                "notes": person['note'] if person['note'] else ''
            }
            
            pg_cur.execute("""
                INSERT INTO events (user_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
                VALUES (%s, 'contact', %s, 'CONTACT_CREATED', 1, %s, %s)
                RETURNING id
            """, (str(user_id), str(contact_id), json.dumps(event_data), datetime.now()))
            
            event_id = pg_cur.fetchone()[0]
            
            # Create projection
            # Truncate phone/URI if too long (VARCHAR(50) limit)
            phone = person['linked_contact_uri'] if person['linked_contact_uri'] else None
            if phone and len(phone) > 50:
                # For Android contact URIs, just store a shortened version or None
                phone = None  # Android URIs are not useful outside Android anyway
            
            pg_cur.execute("""
                INSERT INTO contacts_projection (id, user_id, name, username, phone, email, notes, is_deleted, created_at, updated_at, last_event_id)
                VALUES (%s, %s, %s, %s, %s, %s, %s, false, %s, %s, %s)
            """, (
                str(contact_id),
                str(user_id),
                contact_name,
                username,
                phone,
                None,  # email
                person['note'] if person['note'] else None,
                datetime.now(),
                datetime.now(),
                event_id
            ))
            
            display_name = contact_name
            if username:
                display_name = f"{contact_name} (@{username})"
            print(f"  ✅ {display_name}")
        
        pg_conn.commit()
        print(f"✅ Migrated {len(persons)} contacts")
        
        # Migrate transactions
        print("💰 Migrating transactions...")
        debitum_cur.execute("""
            SELECT t.*, p.name as person_name
            FROM txn t
            JOIN person p ON t.id_person = p.id_person
            ORDER BY t.id_transaction
        """)
        transactions = debitum_cur.fetchall()
        
        for txn in transactions:
            transaction_id = uuid.uuid4()
            contact_id = contact_map[txn['id_person']]
            event_counter += 1
            
            # Determine direction based on amount sign
            # In Debitum: negative = user gave money, positive = user received
            direction = "lent" if txn['amount'] > 0 else "owed"
            amount = abs(txn['amount'])
            
            # Convert timestamp (Debitum uses milliseconds)
            if txn['timestamp']:
                txn_date = datetime.fromtimestamp(txn['timestamp'] / 1000.0).date()
            else:
                txn_date = datetime.now().date()
            
            # Create event
            event_data = {
                "contact_id": str(contact_id),
                "type": "money" if txn['is_monetary'] else "item",
                "direction": direction,
                "amount": amount,
                "currency": "USD",
                "description": txn['description'] if txn['description'] else '',
                "transaction_date": str(txn_date)
            }
            
            pg_cur.execute("""
                INSERT INTO events (user_id, aggregate_type, aggregate_id, event_type, event_version, event_data, created_at)
                VALUES (%s, 'transaction', %s, 'TRANSACTION_CREATED', 1, %s, %s)
                RETURNING id
            """, (str(user_id), str(transaction_id), json.dumps(event_data), datetime.now()))
            
            event_id = pg_cur.fetchone()[0]
            
            # Note: is_settled and settled_at columns were removed in migration 002
            # We only migrate money transactions now (items are not supported)
            if not txn['is_monetary']:
                # Skip non-monetary transactions (items)
                continue
            
            # Create projection (only money transactions)
            pg_cur.execute("""
                INSERT INTO transactions_projection 
                (id, user_id, contact_id, type, direction, amount, currency, description, transaction_date, is_deleted, created_at, updated_at, last_event_id)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, false, %s, %s, %s)
            """, (
                str(transaction_id),
                str(user_id),
                str(contact_id),
                "money",
                direction,
                amount,
                "USD",
                txn['description'] if txn['description'] else None,
                txn_date,
                datetime.now(),
                datetime.now(),
                event_id
            ))
            
            print(f"  ✅ {txn['person_name']}: {amount} ({'money' if txn['is_monetary'] else 'item'})")
        
        pg_conn.commit()
        
        # Count only monetary transactions (items are skipped)
        monetary_transactions = [t for t in transactions if t['is_monetary']]
        print(f"✅ Migrated {len(monetary_transactions)} transactions ({len(transactions) - len(monetary_transactions)} items skipped)")
        
        # Verify final counts
        pg_cur.execute("SELECT COUNT(*) FROM transactions_projection WHERE user_id = %s", (str(user_id),))
        final_txns = pg_cur.fetchone()[0]
        pg_cur.execute("SELECT COUNT(*) FROM contacts_projection WHERE user_id = %s", (str(user_id),))
        final_contacts = pg_cur.fetchone()[0]
        
        print("")
        print("📊 Final verification:")
        print(f"   - {final_contacts} contacts in database")
        print(f"   - {final_txns} transactions in database")
        
        if final_contacts != len(persons):
            print(f"   ⚠️  WARNING: Expected {len(persons)} contacts but found {final_contacts}")
        if final_txns != len(monetary_transactions):
            print(f"   ⚠️  WARNING: Expected {len(monetary_transactions)} transactions but found {final_txns}")
        
        # Migrate images if any
        print("🖼️  Checking for images...")
        debitum_cur.execute("SELECT COUNT(*) FROM image")
        image_count = debitum_cur.fetchone()[0]
        if image_count > 0:
            print(f"  ℹ️  Found {image_count} images (not migrated - you'll need to handle images separately)")
        
        print("")
        print(f"✅ Migration complete!")
        print(f"   - {len(persons)} contacts")
        print(f"   - {len(monetary_transactions)} transactions")
        print(f"   - {event_counter} events created")
        print("")
        print("🌐 View your data at: http://localhost:8000/admin")
        
    except Exception as e:
        pg_conn.rollback()
        print(f"❌ Error during migration: {e}")
        raise
    finally:
        debitum_conn.close()
        pg_cur.close()
        pg_conn.close()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 migrate_debitum.py <path-to-debitum.db>")
        sys.exit(1)
    
    debitum_db = sys.argv[1]
    if not Path(debitum_db).exists():
        print(f"Error: File not found: {debitum_db}")
        sys.exit(1)
    
    migrate_debitum(debitum_db)
