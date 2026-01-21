#!/usr/bin/env python3
"""
Fast migration using sync endpoints - batches all events and uploads at once
This is much faster than individual API calls
"""

import sys
import sqlite3
import json
import re
import requests
import uuid
import zipfile
import tempfile
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path

API_BASE_URL = "http://localhost:8000"

def extract_username(name):
    """Extract username (English letters and numbers) from contact name."""
    if not name:
        return None
    
    matches = re.findall(r'[a-zA-Z0-9]+', name)
    if not matches:
        return None
    
    username = ''.join(matches)
    return username if username else None

def split_name_and_username(full_name):
    """Split a contact name into name (without username) and username."""
    if not full_name:
        return (None, None)
    
    username = extract_username(full_name)
    if not username:
        return (full_name, None)
    
    name_without_username = re.sub(r'[a-zA-Z0-9]+', '', full_name)
    name_without_username = re.sub(r'\s+', ' ', name_without_username).strip()
    
    if not name_without_username:
        name_without_username = full_name
    
    return (name_without_username, username)

def wait_for_server(max_retries=30, delay=1):
    """Wait for the API server to be ready."""
    for i in range(max_retries):
        try:
            response = requests.get(f"{API_BASE_URL}/health", timeout=2)
            if response.status_code == 200:
                return True
        except requests.exceptions.RequestException:
            pass
        
        if i < max_retries - 1:
            import time
            time.sleep(delay)
    
    print("❌ API server is not responding")
    return False

def extract_db_from_zip(zip_path):
    """Extract database from zip file if needed."""
    if zip_path.endswith('.zip'):
        temp_dir = tempfile.mkdtemp()
        try:
            with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                # Look for .db file in the zip
                db_files = [f for f in zip_ref.namelist() if f.endswith('.db')]
                if not db_files:
                    print("❌ No .db file found in zip archive")
                    sys.exit(1)
                
                # Extract the first .db file found
                db_file = db_files[0]
                zip_ref.extract(db_file, temp_dir)
                db_path = os.path.join(temp_dir, db_file)
                return db_path, temp_dir
        except zipfile.BadZipFile:
            print(f"❌ Invalid zip file: {zip_path}")
            sys.exit(1)
    else:
        return zip_path, None

def migrate_debitum(debitum_db_path):
    """Migrate Debitum data to Debt Tracker via sync endpoints (fast batch upload)"""
    
    # Extract from zip if needed
    db_path, temp_dir = extract_db_from_zip(debitum_db_path)
    
    # Wait for server to be ready
    if not wait_for_server():
        print("❌ Cannot proceed without API server")
        print("💡 Make sure the server is running: ./START_SERVER.sh")
        if temp_dir:
            import shutil
            shutil.rmtree(temp_dir)
        sys.exit(1)
    
    debitum_conn = None
    try:
        # Connect to Debitum SQLite
        debitum_conn = sqlite3.connect(db_path)
        debitum_conn.row_factory = sqlite3.Row
        debitum_cur = debitum_conn.cursor()
        
        # Get user ID (needed for events)
        try:
            user_response = requests.get(f"{API_BASE_URL}/api/admin/contacts", timeout=5)
            if user_response.status_code == 200:
                contacts = user_response.json()
                if contacts:
                    # Extract user_id from first contact (all contacts have same user_id)
                    user_id = contacts[0].get('user_id')
                else:
                    user_id = None
            else:
                user_id = None
        except:
            user_id = None
        
        # Prepare all events for batch upload
        print("📇 Preparing contacts...")
        debitum_cur.execute("SELECT * FROM person ORDER BY id_person")
        persons = debitum_cur.fetchall()
        
        contact_map = {}  # Map old person ID to new contact UUID
        events = []
        # Use a base timestamp - we'll use actual timestamps from transactions for ordering
        base_timestamp = datetime.utcnow() - timedelta(days=365)  # Start from a year ago
        
        for idx, person in enumerate(persons):
            # Extract username from name
            original_name = person['name'] or ''
            contact_name, username = split_name_and_username(original_name)
            
            # Ensure we have at least a name
            if not contact_name or contact_name.strip() == '':
                contact_name = original_name
            
            # Generate contact ID
            contact_id = str(uuid.uuid4())
            contact_map[person['id_person']] = contact_id
            
            # Prepare contact event data
            phone = person['linked_contact_uri'] if person['linked_contact_uri'] else None
            if phone and len(phone) > 50:
                phone = None
            
            # Use base timestamp with small increments to maintain order
            # Contacts are created before their transactions
            contact_timestamp = base_timestamp + timedelta(seconds=idx)
            
            event_data = {
                "name": contact_name,
                "username": username,
                "phone": phone,
                "email": None,
                "notes": person['note'] if person['note'] else '',
                "comment": f"Migrated from Debitum backup - Person ID: {person['id_person']}",
                "timestamp": contact_timestamp.isoformat() + "Z"
            }
            
            # Create CREATED event
            event = {
                "id": str(uuid.uuid4()),
                "aggregate_type": "contact",
                "aggregate_id": contact_id,
                "event_type": "CREATED",
                "event_data": event_data,
                "timestamp": contact_timestamp.isoformat() + "Z",
                "version": 1
            }
            events.append(event)
        
        print(f"✅ Prepared {len(events)} contact events")
        
        # Batch upload contact events
        print("📤 Uploading contact events (batch)...")
        try:
            response = requests.post(
                f"{API_BASE_URL}/api/sync/events",
                json=events,
                headers={"Content-Type": "application/json"},
                timeout=60
            )
            
            if response.status_code == 200:
                result = response.json()
                accepted = result.get('accepted', [])
                conflicts = result.get('conflicts', [])
                print(f"✅ Uploaded {len(accepted)} contact events ({len(conflicts)} conflicts)")
            else:
                print(f"❌ Failed to upload events: HTTP {response.status_code}")
                print(f"   Response: {response.text[:200]}")
                sys.exit(1)
        except requests.exceptions.RequestException as e:
            print(f"❌ Error uploading events: {e}")
            sys.exit(1)
        
        # Prepare transaction events
        print("💰 Preparing transactions...")
        debitum_cur.execute("""
            SELECT t.*, p.name as person_name
            FROM txn t
            JOIN person p ON t.id_person = p.id_person
            ORDER BY t.id_transaction
        """)
        transactions = debitum_cur.fetchall()
        
        transaction_events = []
        skipped_count = 0
        
        for txn in transactions:
            # Skip non-monetary transactions (items)
            if not txn['is_monetary']:
                skipped_count += 1
                continue
            
            contact_id = contact_map.get(txn['id_person'])
            if not contact_id:
                # Silently skip - we'll show summary at the end
                continue
            
            # Determine direction based on amount sign
            direction = "lent" if txn['amount'] > 0 else "owed"
            amount = abs(txn['amount'])
            
            # Use actual timestamp from database (convert from milliseconds to datetime)
            if txn['timestamp']:
                txn_timestamp = datetime.fromtimestamp(txn['timestamp'] / 1000.0, tz=timezone.utc)
                txn_date = txn_timestamp.date().isoformat()
            else:
                # Fallback to current time if no timestamp
                txn_timestamp = datetime.utcnow().replace(tzinfo=timezone.utc)
                txn_date = txn_timestamp.date().isoformat()
            
            # Prepare transaction event data
            transaction_id = str(uuid.uuid4())
            event_data = {
                "contact_id": contact_id,
                "type": "money",
                "direction": direction,
                "amount": amount,
                "currency": "IQD",  # Iraqi Dinar - default currency
                "description": txn['description'] if txn['description'] else None,
                "transaction_date": txn_date,
                "comment": f"Migrated from Debitum backup - Transaction ID: {txn['id_transaction']}",
                "timestamp": txn_timestamp.isoformat().replace('+00:00', 'Z')
            }
            
            # Create CREATED event with actual timestamp from database
            event = {
                "id": str(uuid.uuid4()),
                "aggregate_type": "transaction",
                "aggregate_id": transaction_id,
                "event_type": "CREATED",
                "event_data": event_data,
                "timestamp": txn_timestamp.isoformat().replace('+00:00', 'Z'),
                "version": 1
            }
            transaction_events.append(event)
        
        monetary_transactions = [t for t in transactions if t['is_monetary']]
        print(f"✅ Prepared {len(transaction_events)} transaction events ({skipped_count} items skipped)")
        
        # Batch upload transaction events
        if transaction_events:
            print("📤 Uploading transaction events...")
            try:
                response = requests.post(
                    f"{API_BASE_URL}/api/sync/events",
                    json=transaction_events,
                    headers={"Content-Type": "application/json"},
                    timeout=120
                )
                
                if response.status_code == 200:
                    result = response.json()
                    accepted = result.get('accepted', [])
                    conflicts = result.get('conflicts', [])
                    print(f"✅ Uploaded {len(accepted)} transaction events ({len(conflicts)} conflicts)")
                else:
                    print(f"❌ Failed to upload transaction events: HTTP {response.status_code}")
                    print(f"   Response: {response.text[:200]}")
            except requests.exceptions.RequestException as e:
                print(f"❌ Error uploading transaction events: {e}")
        
        print(f"✅ Migration complete: {len(persons)} contacts, {len(transaction_events)} transactions ({skipped_count} items skipped)")
        
    except Exception as e:
        print(f"❌ Error during migration: {e}")
        import traceback
        traceback.print_exc()
        raise
    finally:
        if debitum_conn:
            debitum_conn.close()
        # Clean up temp directory if we extracted from zip
        if temp_dir:
            import shutil
            try:
                shutil.rmtree(temp_dir)
            except:
                pass

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 migrate_debitum_via_api_fast.py <path-to-debitum.db>")
        sys.exit(1)
    
    debitum_db = sys.argv[1]
    if not Path(debitum_db).exists():
        print(f"Error: File not found: {debitum_db}")
        sys.exit(1)
    
    migrate_debitum(debitum_db)
