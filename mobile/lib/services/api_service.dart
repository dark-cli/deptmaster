import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/contact.dart';
import '../models/transaction.dart';
import '../models/wallet.dart';
import 'auth_service.dart';
import 'backend_config_service.dart';
import 'connection_manager.dart';
import 'wallet_service.dart';

class ApiService {
  // Get base URL from backend configuration
  static Future<String> get baseUrl async {
    return await BackendConfigService.getApiBaseUrl();
  }

  // Get auth headers with token and wallet_id
  static Future<Map<String, String>> _getHeaders() async {
    final headers = {'Content-Type': 'application/json'};
    final token = await AuthService.getToken();
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    // Add wallet_id to header (middleware prefers header over query param)
    final walletId = await WalletService.getCurrentWalletId();
    if (walletId != null && walletId.isNotEmpty) {
      headers['X-Wallet-Id'] = walletId;
    }
    return headers;
  }

  // Helper to add wallet_id to query parameters as fallback
  static Future<Uri> _addWalletIdToUri(Uri uri) async {
    final walletId = await WalletService.getCurrentWalletId();
    if (walletId != null && walletId.isNotEmpty) {
      final queryParams = Map<String, String>.from(uri.queryParameters);
      queryParams['wallet_id'] = walletId;
      return uri.replace(queryParameters: queryParams);
    }
    return uri;
  }

  // Helper method to handle HTTP responses and check for 401 errors
  static Future<http.Response> _handleResponse(http.Response response) async {
    // If we get a 401, logout immediately
    if (response.statusCode == 401) {
      print('⚠️ Received 401 Unauthorized - logging out');
      await AuthService.logout();
      throw Exception('Authentication expired. Please login again.');
    }
    return response;
  }
  
  // Contacts
  static Future<List<Contact>> getContacts() async {
    try {
      final headers = await _getHeaders();
      final apiBaseUrl = await baseUrl;
      final uri = await _addWalletIdToUri(Uri.parse('$apiBaseUrl/contacts'));
      final response = await _handleResponse(await http.get(
        uri,
        headers: headers,
      ));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Contact.fromJson(json)).toList();
      } else {
        // Only log non-connection errors
        final errorStr = response.body;
        if (!errorStr.contains('Connection refused') && 
            !errorStr.contains('Failed host lookup') &&
            !errorStr.contains('Network is unreachable')) {
          print('Error fetching contacts: HTTP ${response.statusCode}');
          print('Response: ${response.body}');
        }
      }
    } catch (e) {
      // Use connection manager to format errors
      if (ConnectionManager.isNetworkError(e)) {
        final apiBaseUrl = await baseUrl;
        final serverUrl = apiBaseUrl.replaceFirst('http://', '').replaceFirst('/api/admin', '');
        final message = await ConnectionManager.formatConnectionError(
          e,
          serviceName: 'HTTP',
          serverUrl: serverUrl,
        );
        print('⚠️ $message');
      } else {
        print('Error fetching contacts: $e');
      }
    }
    return [];
  }

  static Future<Contact?> createContact(Contact contact, {String? comment}) async {
    try {
      final headers = await _getHeaders();
      final apiBaseUrl = await baseUrl;
      final apiUrl = apiBaseUrl.replaceAll('/admin', '');
      final uri = await _addWalletIdToUri(Uri.parse('$apiUrl/contacts'));
      final response = await _handleResponse(await http.post(
        uri,
        headers: headers,
        body: json.encode({
          'name': contact.name,
          'phone': contact.phone,
          'email': contact.email,
          'notes': contact.notes,
          'comment': comment ?? 'Contact created via mobile app',
        }),
      ));
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        // Return a contact with the data from response
        final walletId = await WalletService.getCurrentWalletId();
        return Contact(
          id: data['id'] as String,
          name: data['name'] as String,
          phone: null,
          email: null,
          notes: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          balance: (data['balance'] as num?)?.toInt() ?? 0,
          walletId: walletId, // Set wallet_id from current wallet
        );
      } else {
        final errorBody = response.body;
        try {
          final error = json.decode(errorBody);
          throw Exception(error['error'] ?? 'Failed to create contact');
        } catch (_) {
          throw Exception('Failed to create contact: ${response.statusCode} - $errorBody');
        }
      }
    } catch (e) {
      print('Error creating contact: $e');
      rethrow;
    }
  }

  // Update contact
  static Future<void> updateContact(String contactId, Contact contact, {String? comment}) async {
    try {
      final apiBaseUrl = await baseUrl;
      final apiUrl = apiBaseUrl.replaceAll('/admin', '');
      final headers = await _getHeaders();
      final uri = await _addWalletIdToUri(Uri.parse('$apiUrl/contacts/$contactId'));
      final response = await _handleResponse(await http.put(
        uri,
        headers: headers,
        body: json.encode({
          'name': contact.name,
          'phone': contact.phone,
          'email': contact.email,
          'notes': contact.notes,
          'comment': comment ?? 'Contact updated via mobile app',
        }),
      ));
      if (response.statusCode == 200) {
        return;
      } else {
        final errorBody = response.body;
        try {
          final error = json.decode(errorBody);
          throw Exception(error['error'] ?? 'Failed to update contact');
        } catch (_) {
          throw Exception('Failed to update contact: ${response.statusCode} - $errorBody');
        }
      }
    } catch (e) {
      print('Error updating contact: $e');
      rethrow;
    }
  }

  // Delete contact
  static Future<void> deleteContact(String contactId, {String? comment}) async {
    try {
      final apiBaseUrl = await baseUrl;
      final apiUrl = apiBaseUrl.replaceAll('/admin', '');
      final headers = await _getHeaders();
      final uri = await _addWalletIdToUri(Uri.parse('$apiUrl/contacts/$contactId'));
      final response = await _handleResponse(await http.delete(
        uri,
        headers: headers,
        body: json.encode({
          'comment': comment ?? 'Contact deleted via mobile app',
        }),
      ));
      if (response.statusCode == 200) {
        return;
      } else {
        final errorBody = response.body;
        try {
          final error = json.decode(errorBody);
          throw Exception(error['error'] ?? 'Failed to delete contact');
        } catch (_) {
          throw Exception('Failed to delete contact: ${response.statusCode} - $errorBody');
        }
      }
    } catch (e) {
      print('Error deleting contact: $e');
      rethrow;
    }
  }

  // Bulk delete contacts
  static Future<void> bulkDeleteContacts(List<String> contactIds, {String? comment}) async {
    try {
      // Delete contacts one by one (could be optimized with a bulk endpoint)
      for (final contactId in contactIds) {
        await deleteContact(contactId, comment: comment);
      }
    } catch (e) {
      print('Error bulk deleting contacts: $e');
      rethrow;
    }
  }

  // Bulk delete transactions
  static Future<void> bulkDeleteTransactions(List<String> transactionIds, {String? comment}) async {
    try {
      // Delete transactions one by one (could be optimized with a bulk endpoint)
      for (final transactionId in transactionIds) {
        await deleteTransaction(transactionId, comment: comment);
      }
    } catch (e) {
      print('Error bulk deleting transactions: $e');
      rethrow;
    }
  }

  // Transactions
  static Future<List<Transaction>> getTransactions() async {
    try {
      // Use /api/transactions instead of /api/admin/transactions
      final apiBaseUrl = await baseUrl;
      final apiUrl = apiBaseUrl.replaceAll('/admin', '');
      final headers = await _getHeaders();
      final uri = await _addWalletIdToUri(Uri.parse('$apiUrl/transactions'));
      final response = await _handleResponse(await http.get(
        uri,
        headers: headers,
      ));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final transactions = <Transaction>[];
        for (var jsonItem in data) {
          try {
            transactions.add(Transaction.fromJson(jsonItem));
          } catch (e, stackTrace) {
            print('Error parsing transaction: $e');
            print('Transaction data: $jsonItem');
            print('Stack trace: $stackTrace');
            // Continue with other transactions
          }
        }
        print('✅ Loaded ${transactions.length} transactions');
        return transactions;
      } else {
        // Only log non-connection errors
        final errorStr = response.body;
        if (!errorStr.contains('Connection refused') && 
            !errorStr.contains('Failed host lookup') &&
            !errorStr.contains('Network is unreachable')) {
          print('Error fetching transactions: HTTP ${response.statusCode}');
          print('Response: ${response.body}');
        }
      }
    } catch (e, stackTrace) {
      // Silently handle connection errors - app works offline
      final errorStr = e.toString();
      if (!errorStr.contains('Connection refused') && 
          !errorStr.contains('Failed host lookup') &&
          !errorStr.contains('Network is unreachable')) {
        print('Error fetching transactions: $e');
        print('Stack trace: $stackTrace');
      }
    }
    return [];
  }

  static Future<Transaction?> createTransaction(Transaction transaction, {String? comment}) async {
    try {
      final headers = await _getHeaders();
      final apiBaseUrl = await baseUrl;
      final apiUrl = apiBaseUrl.replaceAll('/admin', '');
      final uri = await _addWalletIdToUri(Uri.parse('$apiUrl/transactions'));
      final response = await _handleResponse(await http.post(
        uri,
        headers: headers,
        body: json.encode({
          'contact_id': transaction.contactId,
          'type': transaction.type == TransactionType.money ? 'money' : 'item',
          'direction': transaction.direction == TransactionDirection.owed ? 'owed' : 'lent',
          'amount': transaction.amount,
          'currency': transaction.currency,
          'description': transaction.description,
          'transaction_date': transaction.transactionDate.toIso8601String().split('T')[0],
          'due_date': transaction.dueDate?.toIso8601String().split('T')[0],
          'comment': comment ?? 'Transaction created via mobile app',
        }),
      ));
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        // Return a transaction with the data from request
        final walletId = await WalletService.getCurrentWalletId();
        return Transaction(
          id: data['id'] as String,
          contactId: data['contact_id'] as String,
          type: transaction.type,
          direction: transaction.direction,
          amount: transaction.amount,
          currency: transaction.currency,
          description: transaction.description,
          transactionDate: transaction.transactionDate,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          walletId: walletId, // Set wallet_id from current wallet
        );
      } else {
        final errorBody = response.body;
        try {
          final error = json.decode(errorBody);
          throw Exception(error['error'] ?? 'Failed to create transaction');
        } catch (_) {
          throw Exception('Failed to create transaction: ${response.statusCode} - $errorBody');
        }
      }
    } catch (e) {
      print('Error creating transaction: $e');
      rethrow;
    }
  }

  static Future<void> updateTransaction(
    String transactionId, {
    int? amount,
    TransactionDirection? direction,
    String? description,
    DateTime? transactionDate,
    String? contactId,
    DateTime? dueDate,
    String? comment,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (amount != null) body['amount'] = amount;
      if (direction != null) {
        body['direction'] = direction == TransactionDirection.owed ? 'owed' : 'lent';
      }
      if (description != null) body['description'] = description;
      if (transactionDate != null) {
        body['transaction_date'] = transactionDate.toIso8601String().split('T')[0];
      }
      if (contactId != null) body['contact_id'] = contactId;
      if (dueDate != null) {
        body['due_date'] = dueDate.toIso8601String().split('T')[0];
      }
      // Comment is required for updates
      body['comment'] = comment ?? 'Transaction updated via mobile app';

      final headers = await _getHeaders();
      final apiBaseUrl = await baseUrl;
      final apiUrl = apiBaseUrl.replaceAll('/admin', '');
      final uri = await _addWalletIdToUri(Uri.parse('$apiUrl/transactions/$transactionId'));
      final response = await _handleResponse(await http.put(
        uri,
        headers: headers,
        body: json.encode(body),
      ));

      if (response.statusCode != 200) {
        final errorBody = response.body;
        try {
          final error = json.decode(errorBody);
          throw Exception(error['error'] ?? 'Failed to update transaction');
        } catch (_) {
          throw Exception('Failed to update transaction: ${response.statusCode} - $errorBody');
        }
      }
    } catch (e) {
      print('Error updating transaction: $e');
      rethrow;
    }
  }

  static Future<void> deleteTransaction(String transactionId, {String? comment}) async {
    try {
      final headers = await _getHeaders();
      final apiBaseUrl = await baseUrl;
      final apiUrl = apiBaseUrl.replaceAll('/admin', '');
      final uri = await _addWalletIdToUri(Uri.parse('$apiUrl/transactions/$transactionId'));
      final response = await _handleResponse(await http.delete(
        uri,
        headers: headers,
        body: json.encode({
          'comment': comment ?? 'Transaction deleted via mobile app',
        }),
      ));

      if (response.statusCode != 200) {
        final errorBody = response.body;
        try {
          final error = json.decode(errorBody);
          throw Exception(error['error'] ?? 'Failed to delete transaction');
        } catch (_) {
          throw Exception('Failed to delete transaction: ${response.statusCode} - $errorBody');
        }
      }
    } catch (e) {
      print('Error deleting transaction: $e');
      rethrow;
    }
  }

  // Sync methods
  static Future<Map<String, dynamic>> getSyncHash() async {
    try {
      final headers = await _getHeaders();
      final baseUrl = await BackendConfigService.getBaseUrl();
      final uri = await _addWalletIdToUri(Uri.parse('$baseUrl/api/sync/hash'));
      final response = await _handleResponse(await http.get(
        uri,
        headers: headers,
      ));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to get sync hash: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting sync hash: $e');
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getSyncEvents({String? since}) async {
    try {
      final headers = await _getHeaders();
      final baseUrl = await BackendConfigService.getBaseUrl();
      var uri = Uri.parse('$baseUrl/api/sync/events');
      if (since != null) {
        uri = uri.replace(queryParameters: {'since': since});
      }
      uri = await _addWalletIdToUri(uri);

      final response = await _handleResponse(await http.get(
        uri,
        headers: headers,
      ));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((e) => e as Map<String, dynamic>).toList();
      } else {
        throw Exception('Failed to get sync events: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting sync events: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> postSyncEvents(List<Map<String, dynamic>> events) async {
    try {
      final headers = await _getHeaders();
      final baseUrl = await BackendConfigService.getBaseUrl();
      final uri = await _addWalletIdToUri(Uri.parse('$baseUrl/api/sync/events'));
      final response = await _handleResponse(await http.post(
        uri,
        headers: headers,
        body: json.encode(events),
      ));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        final errorBody = response.body;
        print('❌ Server error response (${response.statusCode}): $errorBody');
        // Try to parse error message if it's JSON
        try {
          final errorJson = json.decode(errorBody);
          if (errorJson is Map && errorJson.containsKey('error')) {
            print('❌ Error details: ${errorJson['error']}');
          }
        } catch (_) {
          // Not JSON, just print as-is
        }
        throw Exception('Failed to post sync events: ${response.statusCode} - $errorBody');
      }
    } catch (e) {
      print('Error posting sync events: $e');
      rethrow;
    }
  }

  // Delete an event from the server (only if less than 5 seconds old)
  /// @deprecated Use UNDO events instead of deleting events
  /// This method is kept for backward compatibility but should not be used
  static Future<bool> deleteEvent(String eventId) async {
    print('⚠️ deleteEvent is deprecated - use UNDO events instead');
    // Endpoint no longer exists - return false
    return false;
  }

  // Wallet methods
  /// Create a new wallet for the current user (user becomes owner). No X-Wallet-Id needed.
  static Future<Wallet?> createWallet({required String name, String? description}) async {
    try {
      final headers = await _getHeaders();
      final apiBaseUrl = await baseUrl;
      final apiUrl = apiBaseUrl.replaceAll('/admin', '');
      final response = await _handleResponse(await http.post(
        Uri.parse('$apiUrl/wallets'),
        headers: headers,
        body: json.encode({'name': name, 'description': description ?? ''}),
      ));
      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        final id = data['id'] as String?;
        final nameStr = data['name'] as String? ?? name;
        if (id == null) return null;
        return Wallet(
          id: id,
          name: nameStr,
          description: description != null && description.isNotEmpty ? description : null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          createdBy: null,
          isActive: true,
        );
      }
    } catch (e) {
      print('Error creating wallet: $e');
    }
    return null;
  }

  static Future<List<Wallet>> getWallets() async {
    final headers = await _getHeaders();
    final apiBaseUrl = await baseUrl;
    final apiUrl = apiBaseUrl.replaceAll('/admin', '');
    final response = await _handleResponse(await http.get(
      Uri.parse('$apiUrl/wallets'),
      headers: headers,
    ));
    if (response.statusCode != 200) {
      final errorStr = response.body;
      print('Error fetching wallets: HTTP ${response.statusCode}');
      print('Response: $errorStr');
      throw Exception('Failed to load wallets: ${response.statusCode}');
    }
    final responseData = json.decode(response.body);
    List<dynamic> walletsData;
    if (responseData is Map && responseData.containsKey('wallets')) {
      walletsData = responseData['wallets'] as List<dynamic>;
    } else if (responseData is List) {
      walletsData = responseData;
    } else {
      walletsData = [];
    }
    try {
      return walletsData.map((json) => Wallet.fromJson(json as Map<String, dynamic>)).toList();
    } catch (e, st) {
      print('Error parsing wallets response: $e');
      print('Stack: $st');
      print('Data: $walletsData');
      rethrow;
    }
  }

  static Future<Wallet?> getWalletById(String walletId) async {
    try {
      final headers = await _getHeaders();
      final apiBaseUrl = await baseUrl;
      final apiUrl = apiBaseUrl.replaceAll('/admin', '');
      final uri = await _addWalletIdToUri(Uri.parse('$apiUrl/wallets/$walletId'));
      final response = await _handleResponse(await http.get(
        uri,
        headers: headers,
      ));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return Wallet.fromJson(data);
      } else {
        print('Error fetching wallet: HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching wallet: $e');
    }
    return null;
  }
}
