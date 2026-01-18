# Debt Tracker Mobile App

Flutter mobile application for debt tracking with real API integration.

## ✅ Current Status

- ✅ Connected to real API (`/api/admin/contacts` and `/api/admin/transactions`)
- ✅ Shows your real Debitum data (59 contacts, 249 transactions)
- ✅ Displays net balance per contact
- ✅ Offline-first with Hive local storage
- ✅ Auto-refresh from API on startup

## Setup

1. **Install Flutter dependencies:**
   ```bash
   cd mobile
   flutter pub get
   ```

2. **Generate Hive adapters:**
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

3. **Configure API URL:**
   
   Edit `lib/services/api_service.dart` and set the correct base URL:
   - **Android Emulator**: `http://10.0.2.2:8000/api/admin` (already set)
   - **iOS Simulator**: `http://localhost:8000/api/admin`
   - **Physical Device**: `http://YOUR_COMPUTER_IP:8000/api/admin`
   
   To find your computer's IP:
   ```bash
   # Linux/Mac
   ip addr show | grep "inet " | grep -v 127.0.0.1
   
   # Or
   hostname -I
   ```

4. **Make sure the backend is running:**
   ```bash
   # In project root
   cd backend/rust-api
   DATABASE_URL="postgresql://debt_tracker:dev_password@localhost:5432/debt_tracker" \
   PORT=8000 cargo run
   ```

5. **Run the app:**
   ```bash
   flutter run
   ```

## Features

- **View Contacts**: See all your contacts with net balances
- **View Transactions**: See all transactions
- **Balance Display**: 
  - Green = They owe you money
  - Red = You owe them money
  - Gray = Settled (zero balance)
- **Offline Support**: Data cached locally in Hive
- **Pull to Refresh**: Tap refresh button to sync with API

## API Endpoints Used

- `GET /api/admin/contacts` - Get all contacts with balances
- `GET /api/admin/transactions` - Get all transactions

## Data Model

### Contact
- `id`: UUID
- `name`: String
- `phone`: String? (optional)
- `email`: String? (optional)
- `balance`: int (net balance in cents)
- `createdAt`: DateTime

### Transaction
- `id`: UUID
- `contactId`: UUID
- `type`: "money" | "item"
- `direction`: "owed" | "lent"
- `amount`: int (cents for money)
- `transactionDate`: DateTime
- `description`: String? (optional)

## Next Steps

- [ ] Add authentication
- [ ] Add biometric login
- [ ] Implement create/edit/delete operations
- [ ] Add sync conflict resolution
- [ ] Add search functionality
- [ ] Add notifications/reminders

## Troubleshooting

**Can't connect to API:**
- Make sure backend is running on port 8000
- Check API URL in `api_service.dart`
- For physical device, ensure phone and computer are on same network
- Check firewall settings

**Data not showing:**
- Check console logs for errors
- Verify API is returning data: `curl http://localhost:8000/api/admin/contacts`
- Try pull-to-refresh button
