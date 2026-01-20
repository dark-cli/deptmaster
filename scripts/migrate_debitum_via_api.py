#!/usr/bin/env python3
"""
Migrate Debitum SQLite database to Debt Tracker via API endpoints
This ensures all data is inserted naturally with EventStore events
"""

import sys
import sqlite3
import json
import re
import requests
import time
from datetime import datetime
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
    print("⏳ Waiting for API server to be ready...")
    for i in range(max_retries):
        try:
            response = requests.get(f"{API_BASE_URL}/health", timeout=2)
            if response.status_code == 200:
                print("✅ API server is ready")
                return True
        except requests.exceptions.RequestException:
            pass
        
        if i < max_retries - 1:
            time.sleep(delay)
            print(f"   Retrying... ({i+1}/{max_retries})")
    
    print("❌ API server is not responding")
    return False

def migrate_debitum(debitum_db_path):
    """Migrate Debitum data to Debt Tracker via API"""
    
    print(f"📊 Reading Debitum database: {debitum_db_path}")
    
    # Wait for server to be ready
    if not wait_for_server():
        print("❌ Cannot proceed without API server")
        print("💡 Make sure the server is running: ./START_SERVER.sh")
        sys.exit(1)
    
    # Connect to Debitum SQLite
    debitum_conn = sqlite3.connect(debitum_db_path)
    debitum_conn.row_factory = sqlite3.Row
    debitum_cur = debitum_conn.cursor()
    
    try:
        # Migrate persons to contacts
        print("📇 Migrating contacts via API...")
        debitum_cur.execute("SELECT * FROM person ORDER BY id_person")
        persons = debitum_cur.fetchall()
        
        contact_map = {}  # Map old person ID to new contact UUID
        success_count = 0
        error_count = 0
        
        for person in persons:
            # Extract username from name
            original_name = person['name'] or ''
            contact_name, username = split_name_and_username(original_name)
            
            # Ensure we have at least a name
            if not contact_name or contact_name.strip() == '':
                contact_name = original_name
            
            # Prepare contact data
            contact_data = {
                "name": contact_name,
                "username": username,
                "phone": person['linked_contact_uri'] if person['linked_contact_uri'] else None,
                "email": None,
                "notes": person['note'] if person['note'] else '',
                "comment": f"Migrated from Debitum backup - Person ID: {person['id_person']}"  # Required comment field
            }
            
            # Truncate phone if too long
            if contact_data['phone'] and len(contact_data['phone']) > 50:
                contact_data['phone'] = None
            
            # Create contact via API
            try:
                response = requests.post(
                    f"{API_BASE_URL}/api/contacts",
                    json=contact_data,
                    headers={"Content-Type": "application/json"},
                    timeout=10
                )
                
                if response.status_code in [200, 201]:
                    result = response.json()
                    contact_id = result.get('id')
                    if contact_id:
                        contact_map[person['id_person']] = contact_id
                        success_count += 1
                        display_name = contact_name
                        if username:
                            display_name = f"{contact_name} (@{username})"
                        print(f"  ✅ {display_name}")
                    else:
                        error_count += 1
                        print(f"  ❌ {contact_name}: No ID returned")
                else:
                    error_count += 1
                    error_msg = response.text[:100] if response.text else "Unknown error"
                    print(f"  ❌ {contact_name}: HTTP {response.status_code} - {error_msg}")
                
                # Small delay to avoid overwhelming the server
                time.sleep(0.1)
                
            except requests.exceptions.RequestException as e:
                error_count += 1
                print(f"  ❌ {contact_name}: Request failed - {str(e)[:100]}")
        
        print(f"✅ Migrated {success_count} contacts ({error_count} errors)")
        
        if error_count > 0:
            print(f"⚠️  {error_count} contacts failed to migrate")
        
        # Migrate transactions
        print("💰 Migrating transactions via API...")
        debitum_cur.execute("""
            SELECT t.*, p.name as person_name
            FROM txn t
            JOIN person p ON t.id_person = p.id_person
            ORDER BY t.id_transaction
        """)
        transactions = debitum_cur.fetchall()
        
        success_count = 0
        error_count = 0
        skipped_count = 0
        
        for txn in transactions:
            # Skip non-monetary transactions (items)
            if not txn['is_monetary']:
                skipped_count += 1
                continue
            
            contact_id = contact_map.get(txn['id_person'])
            if not contact_id:
                error_count += 1
                print(f"  ❌ Transaction for person {txn['id_person']}: Contact not found")
                continue
            
            # Determine direction based on amount sign
            direction = "lent" if txn['amount'] > 0 else "owed"
            amount = abs(txn['amount'])
            
            # Convert timestamp
            if txn['timestamp']:
                txn_date = datetime.fromtimestamp(txn['timestamp'] / 1000.0).date().isoformat()
            else:
                txn_date = datetime.now().date().isoformat()
            
            # Prepare transaction data
            transaction_data = {
                "contact_id": contact_id,
                "type": "money",
                "direction": direction,
                "amount": amount,
                "currency": "USD",
                "description": txn['description'] if txn['description'] else None,
                "transaction_date": txn_date,
                "comment": f"Migrated from Debitum backup - Transaction ID: {txn['id_transaction']}"  # Required comment field
            }
            
            # Create transaction via API
            try:
                response = requests.post(
                    f"{API_BASE_URL}/api/transactions",
                    json=transaction_data,
                    headers={"Content-Type": "application/json"},
                    timeout=10
                )
                
                if response.status_code in [200, 201]:
                    success_count += 1
                    print(f"  ✅ {txn['person_name']}: {amount} USD")
                else:
                    error_count += 1
                    error_msg = response.text[:100] if response.text else "Unknown error"
                    print(f"  ❌ {txn['person_name']}: HTTP {response.status_code} - {error_msg}")
                
                # Small delay to avoid overwhelming the server
                time.sleep(0.1)
                
            except requests.exceptions.RequestException as e:
                error_count += 1
                print(f"  ❌ {txn['person_name']}: Request failed - {str(e)[:100]}")
        
        monetary_transactions = [t for t in transactions if t['is_monetary']]
        print(f"✅ Migrated {success_count} transactions ({error_count} errors, {skipped_count} items skipped)")
        
        if error_count > 0:
            print(f"⚠️  {error_count} transactions failed to migrate")
        
        # Verify final counts via API
        print("")
        print("📊 Verifying data via API...")
        try:
            contacts_response = requests.get(f"{API_BASE_URL}/api/admin/contacts", timeout=5)
            transactions_response = requests.get(f"{API_BASE_URL}/api/admin/transactions", timeout=5)
            
            if contacts_response.status_code == 200:
                contacts = contacts_response.json()
                print(f"   - {len(contacts)} contacts in database")
            
            if transactions_response.status_code == 200:
                transactions = transactions_response.json()
                print(f"   - {len(transactions)} transactions in database")
        except Exception as e:
            print(f"   ⚠️  Could not verify: {e}")
        
        print("")
        print(f"✅ Migration complete!")
        print(f"   - {len(persons)} contacts processed")
        print(f"   - {len(monetary_transactions)} transactions processed")
        print("")
        print("🌐 View your data at: http://localhost:8000/admin")
        print("📊 View EventStore events at: http://localhost:2113 (admin/changeit)")
        
    except Exception as e:
        print(f"❌ Error during migration: {e}")
        raise
    finally:
        debitum_conn.close()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 migrate_debitum_via_api.py <path-to-debitum.db>")
        sys.exit(1)
    
    debitum_db = sys.argv[1]
    if not Path(debitum_db).exists():
        print(f"Error: File not found: {debitum_db}")
        sys.exit(1)
    
    migrate_debitum(debitum_db)
