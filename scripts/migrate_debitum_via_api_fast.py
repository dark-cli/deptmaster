#!/usr/bin/env python3
"""
Fast migration using sync endpoints - batches all events and uploads at once
This is much faster than individual API calls.

Requires username and wallet; if the wallet does not exist it will be created.
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

def login(username, password):
    """Login with given credentials and return auth token."""
    try:
        response = requests.post(
            f"{API_BASE_URL}/api/auth/login",
            json={"username": username, "password": password},
            timeout=10
        )
        if response.status_code == 200:
            data = response.json()
            token = data.get('token')
            if token:
                return token
    except requests.exceptions.RequestException as e:
        print(f"⚠️  Login request failed: {e}")
    return None

def ensure_wallet(auth_headers, wallet_name):
    """
    Get wallet ID by name; if the wallet does not exist, create it.
    Returns wallet_id (UUID string) or None on failure.
    """
    # List user's wallets
    try:
        response = requests.get(
            f"{API_BASE_URL}/api/wallets",
            headers=auth_headers,
            timeout=10
        )
        if response.status_code != 200:
            print(f"❌ Failed to list wallets: HTTP {response.status_code}")
            return None
        data = response.json()
        wallets = data.get("wallets", [])
        for w in wallets:
            if w.get("name") == wallet_name:
                return w.get("id")
    except requests.exceptions.RequestException as e:
        print(f"❌ Error listing wallets: {e}")
        return None

    # Create wallet if not found
    print(f"📁 Wallet '{wallet_name}' not found; creating...")
    try:
        response = requests.post(
            f"{API_BASE_URL}/api/wallets",
            headers=auth_headers,
            json={"name": wallet_name, "description": None},
            timeout=10
        )
        if response.status_code in (200, 201):
            data = response.json()
            wallet_id = data.get("id")
            if wallet_id:
                print(f"✅ Created wallet '{wallet_name}' ({wallet_id})")
                return wallet_id
        print(f"❌ Failed to create wallet: HTTP {response.status_code} - {response.text[:200]}")
    except requests.exceptions.RequestException as e:
        print(f"❌ Error creating wallet: {e}")
    return None

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

def migrate_debitum(debitum_db_path, username, wallet_name, password):
    """Migrate Debitum data to Debt Tracker via sync endpoints (fast batch upload)."""
    
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
    
    # Login with required username/password
    print(f"🔐 Authenticating as '{username}'...")
    import time
    time.sleep(2)
    
    auth_token = login(username, password)
    if not auth_token:
        print("❌ Failed to authenticate")
        print(f"💡 Check that user '{username}' exists and the password is correct")
        if temp_dir:
            import shutil
            shutil.rmtree(temp_dir)
        sys.exit(1)
    
    # Set up auth headers
    auth_headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {auth_token}"
    }
    
    # Ensure wallet exists (create if not) and get wallet_id for sync requests
    wallet_id = ensure_wallet(auth_headers, wallet_name)
    if not wallet_id:
        if temp_dir:
            import shutil
            shutil.rmtree(temp_dir)
        sys.exit(1)
    auth_headers["X-Wallet-Id"] = wallet_id

    # Get current user ID from auth token
    # Extract user_id from JWT token claims
    try:
        import base64
        import json
        # JWT format: header.payload.signature
        token_parts = auth_token.split('.')
        if len(token_parts) >= 2:
            # Add padding if needed
            payload = token_parts[1]
            payload += '=' * (4 - len(payload) % 4)
            decoded = base64.urlsafe_b64decode(payload)
            claims = json.loads(decoded)
            user_id = claims.get('sub')  # 'sub' is typically the user ID in JWT
            if not user_id:
                # Fallback: try 'user_id' or 'id'
                user_id = claims.get('user_id') or claims.get('id')
        else:
            user_id = None
    except Exception as e:
        print(f"⚠️  Failed to extract user_id from token: {e}")
        user_id = None

    if not user_id:
        print("❌ Failed to determine user ID from auth token")
        if temp_dir:
            import shutil
            shutil.rmtree(temp_dir)
        sys.exit(1)

    print(f"✅ Using wallet_id={wallet_id}, user_id={user_id}")

    debitum_conn = None
    try:
        # Connect to Debitum SQLite
        debitum_conn = sqlite3.connect(db_path)
        debitum_conn.row_factory = sqlite3.Row
        debitum_cur = debitum_conn.cursor()
        
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
                "type": "contact_created",
                "name": contact_name,
                "username": username,
                "phone": phone,
                "email": None,
                "notes": person['note'] if person['note'] else '',
                "group_ids": []
            }
            
            # Create CREATED event
            event = {
                "id": str(uuid.uuid4()),
                "aggregate_type": "contact",
                "aggregate_id": contact_id,
                "event_type": "CREATED",
                "event_data": event_data,
                "timestamp": contact_timestamp.isoformat() + "Z",
                "version": 1,
                "wallet_id": wallet_id,
                "user_id": user_id
            }
            events.append(event)
        
        print(f"✅ Prepared {len(events)} contact events")
        
        # Batch upload contact events
        print("📤 Uploading contact events (batch)...")
        try:
            response = requests.post(
                f"{API_BASE_URL}/api/wallets/{wallet_id}/sync/events",
                json=events,
                headers=auth_headers,
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
                "type": "transaction_created",
                "contact_id": contact_id,
                "amount": amount,
                "direction": direction,
                "currency": "IQD",  # Iraqi Dinar - default currency
                "description": txn['description'] if txn['description'] else None,
                "transaction_date": txn_date,
                "transaction_type": None
            }
            
            # Create CREATED event with actual timestamp from database
            event = {
                "id": str(uuid.uuid4()),
                "aggregate_type": "transaction",
                "aggregate_id": transaction_id,
                "event_type": "CREATED",
                "event_data": event_data,
                "timestamp": txn_timestamp.isoformat().replace('+00:00', 'Z'),
                "version": 1,
                "wallet_id": wallet_id,
                "user_id": user_id
            }
            transaction_events.append(event)
        
        monetary_transactions = [t for t in transactions if t['is_monetary']]
        print(f"✅ Prepared {len(transaction_events)} transaction events ({skipped_count} items skipped)")
        
        # Batch upload transaction events
        if transaction_events:
            print("📤 Uploading transaction events...")
            try:
                response = requests.post(
                    f"{API_BASE_URL}/api/wallets/{wallet_id}/sync/events",
                    json=transaction_events,
                    headers=auth_headers,
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
    if len(sys.argv) < 4:
        print("Usage: python3 migrate_debitum_via_api_fast.py <path-to-backup.zip> <username> <wallet> [password]")
        print("  username  User to import as (must exist)")
        print("  wallet    Wallet name to import into (created if it does not exist)")
        print("  password  Optional; defaults to common defaults if omitted")
        sys.exit(1)
    
    debitum_db = sys.argv[1]
    username = sys.argv[2]
    wallet_name = sys.argv[3]
    password = sys.argv[4] if len(sys.argv) > 4 else None
    
    if not Path(debitum_db).exists():
        print(f"Error: File not found: {debitum_db}")
        sys.exit(1)
    
    # Default password if not given (matches manage.sh reset: user "max" gets password 12345678)
    if not password:
        password = "12345678"
    
    migrate_debitum(debitum_db, username, wallet_name, password)
