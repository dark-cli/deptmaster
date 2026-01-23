import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/contact.dart';
import '../models/transaction.dart';
import 'auth_service.dart';
import 'backend_config_service.dart';

class ApiService {
  // Get base URL from backend configuration
  static Future<String> get baseUrl async {
    return await BackendConfigService.getApiBaseUrl();
  }

  // Get auth headers with token
  static Future<Map<String, String>> _getHeaders() async {
    final headers = {'Content-Type': 'application/json'};
    final token = await AuthService.getToken();
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }
  
  // Contacts
  static Future<List<Contact>> getContacts() async {
    try {
      final headers = await _getHeaders();
      final apiBaseUrl = await baseUrl;
      final response = await http.get(
        Uri.parse('$apiBaseUrl/contacts'),
        headers: headers,
      );
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
      // Silently handle connection errors - app works offline
      final errorStr = e.toString();
      if (!errorStr.contains('Connection refused') && 
          !errorStr.contains('Failed host lookup') &&
          !errorStr.contains('Network is unreachable')) {
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
      final response = await http.post(
        Uri.parse('$apiUrl/contacts'),
        headers: headers,
        body: json.encode({
          'name': contact.name,
          'phone': contact.phone,
          'email': contact.email,
          'notes': contact.notes,
          'comment': comment ?? 'Contact created via mobile app',
        }),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        // Return a contact with the data from response
        return Contact(
          id: data['id'] as String,
          name: data['name'] as String,
          phone: null,
          email: null,
          notes: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          balance: (data['balance'] as num?)?.toInt() ?? 0,
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
      final response = await http.put(
        Uri.parse('$apiUrl/contacts/$contactId'),
        headers: headers,
        body: json.encode({
          'name': contact.name,
          'phone': contact.phone,
          'email': contact.email,
          'notes': contact.notes,
          'comment': comment ?? 'Contact updated via mobile app',
        }),
      );
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
      final response = await http.delete(
        Uri.parse('$apiUrl/contacts/$contactId'),
        headers: headers,
        body: json.encode({
          'comment': comment ?? 'Contact deleted via mobile app',
        }),
      );
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
      final response = await http.get(
        Uri.parse('$apiUrl/transactions'),
        headers: headers,
      );
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
      final response = await http.post(
        Uri.parse('$apiUrl/transactions'),
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
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        // Return a transaction with the data from request
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
      final response = await http.put(
        Uri.parse('$apiUrl/transactions/$transactionId'),
        headers: headers,
        body: json.encode(body),
      );

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
      final response = await http.delete(
        Uri.parse('$apiUrl/transactions/$transactionId'),
        headers: headers,
        body: json.encode({
          'comment': comment ?? 'Transaction deleted via mobile app',
        }),
      );

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
      final response = await http.get(
        Uri.parse('$baseUrl/api/sync/hash'),
        headers: headers,
      );

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
      final uri = Uri.parse('$baseUrl/api/sync/events');
      final uriWithParams = since != null
          ? uri.replace(queryParameters: {'since': since})
          : uri;

      final response = await http.get(
        uriWithParams,
        headers: headers,
      );

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
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/events'),
        headers: headers,
        body: json.encode(events),
      );

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
  static Future<bool> deleteEvent(String eventId) async {
    try {
      final headers = await _getHeaders();
      final baseUrl = await BackendConfigService.getBaseUrl();
      final response = await http.delete(
        Uri.parse('$baseUrl/api/admin/events/$eventId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return true;
      } else {
        final errorBody = response.body;
        try {
          final errorJson = json.decode(errorBody);
          if (errorJson is Map && errorJson.containsKey('error')) {
            print('⚠️ Cannot delete event: ${errorJson['error']}');
          }
        } catch (_) {
          print('⚠️ Cannot delete event: ${response.statusCode} - $errorBody');
        }
        return false;
      }
    } catch (e) {
      print('Error deleting event: $e');
      return false;
    }
  }
}
