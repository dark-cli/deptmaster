// Event Generator Helper
// Generates events from a simple text format to minimize test code

import 'package:debt_tracker_mobile/models/transaction.dart';
import 'app_instance.dart';

/// Event action types
enum EventAction {
  create,
  update,
  delete,
  undo,
}

/// Event generator that creates events from a simple text format
class EventGenerator {
  final Map<String, AppInstance> apps;
  final Map<String, String> contactIds = {}; // name -> id mapping
  final Map<String, String> transactionIds = {}; // label -> id mapping
  final List<Map<String, dynamic>> eventHistory = []; // Track events for undo

  EventGenerator(this.apps);

  /// Parse and execute event commands from text format
  /// Format examples:
  ///   app1: contact create "Contact Name"
  ///   app1: transaction create contact1 owed 1000 "Description"
  ///   app2: contact update contact1 name "New Name"
  ///   app1: transaction update trans1 amount 2000
  ///   app2: transaction delete trans1
  ///   app1: undo last
  Future<void> executeCommands(List<String> commands) async {
    for (final command in commands) {
      await executeCommand(command.trim());
    }
  }

  /// Execute a single command
  Future<void> executeCommand(String command) async {
    if (command.isEmpty || command.startsWith('#')) {
      return; // Skip empty lines and comments
    }

    final parts = command.split(':');
    if (parts.length != 2) {
      throw FormatException('Invalid command format: $command. Expected: "app: action"');
    }

    final appName = parts[0].trim();
    final actionPart = parts[1].trim();

    final app = apps[appName];
    if (app == null) {
      throw ArgumentError('App instance not found: $appName');
    }

    // Parse action - handle quoted strings properly
    final args = _parseArgs(actionPart);
    if (args.isEmpty) {
      throw FormatException('Empty action in command: $command');
    }

    final action = args[0].toLowerCase();
    final actionArgs = args.sublist(1);

    switch (action) {
      case 'contact':
        await _handleContact(app, actionArgs, command);
        break;
      case 'transaction':
        await _handleTransaction(app, actionArgs, command);
        break;
      case 'undo':
        await _handleUndo(app, actionArgs, command);
        break;
      default:
        throw FormatException('Unknown action: $action in command: $command');
    }
  }

  /// Parse arguments handling quoted strings
  List<String> _parseArgs(String input) {
    final args = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;
    
    for (int i = 0; i < input.length; i++) {
      final char = input[i];
      
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ' ' && !inQuotes) {
        if (buffer.length > 0) {
          args.add(buffer.toString());
          buffer.clear();
        }
      } else {
        buffer.write(char);
      }
    }
    
    if (buffer.length > 0) {
      args.add(buffer.toString());
    }
    
    return args;
  }

  /// Handle contact-related commands
  Future<void> _handleContact(
    AppInstance app,
    List<String> args,
    String originalCommand,
  ) async {
    if (args.isEmpty) {
      throw FormatException('Contact command requires action: $originalCommand');
    }

    final contactAction = args[0].toLowerCase();
    final contactArgs = args.sublist(1);

    switch (contactAction) {
      case 'create':
        await _createContact(app, contactArgs, originalCommand);
        break;
      case 'update':
        await _updateContact(app, contactArgs, originalCommand);
        break;
      case 'delete':
        await _deleteContact(app, contactArgs, originalCommand);
        break;
      default:
        throw FormatException('Unknown contact action: $contactAction in command: $originalCommand');
    }
  }

  /// Handle transaction-related commands
  Future<void> _handleTransaction(
    AppInstance app,
    List<String> args,
    String originalCommand,
  ) async {
    if (args.isEmpty) {
      throw FormatException('Transaction command requires action: $originalCommand');
    }

    final transactionAction = args[0].toLowerCase();
    final transactionArgs = args.sublist(1);

    switch (transactionAction) {
      case 'create':
        await _createTransaction(app, transactionArgs, originalCommand);
        break;
      case 'update':
        await _updateTransaction(app, transactionArgs, originalCommand);
        break;
      case 'delete':
        await _deleteTransaction(app, transactionArgs, originalCommand);
        break;
      default:
        throw FormatException('Unknown transaction action: $transactionAction in command: $originalCommand');
    }
  }

  /// Create a contact
  /// Format: create "Contact Name" [label]
  Future<void> _createContact(
    AppInstance app,
    List<String> args,
    String originalCommand,
  ) async {
    if (args.isEmpty) {
      throw FormatException('Contact create requires name: $originalCommand');
    }

    String name = _parseQuotedString(args[0]);
    String? label;
    if (args.length > 1) {
      label = args[1];
    } else {
      label = name.toLowerCase().replaceAll(' ', '');
    }

    final contact = await app.createContact(name: name);
    contactIds[label] = contact.id;

    eventHistory.add({
      'type': 'contact',
      'action': 'create',
      'app': app.id,
      'contactId': contact.id,
      'label': label,
    });
  }

  /// Update a contact
  /// Format: update contactLabel field "value"
  Future<void> _updateContact(
    AppInstance app,
    List<String> args,
    String originalCommand,
  ) async {
    if (args.length < 3) {
      throw FormatException('Contact update requires: contactLabel field "value": $originalCommand');
    }

    final contactLabel = args[0];
    final field = args[1].toLowerCase();
    final value = _parseQuotedString(args[2]);

    final contactId = contactIds[contactLabel];
    if (contactId == null) {
      throw ArgumentError('Contact label not found: $contactLabel');
    }

    final updates = <String, dynamic>{};
    switch (field) {
      case 'name':
        updates['name'] = value;
        break;
      case 'phone':
        updates['phone'] = value;
        break;
      case 'email':
        updates['email'] = value;
        break;
      default:
        throw FormatException('Unknown contact field: $field in command: $originalCommand');
    }

    await app.updateContact(contactId, updates);

    eventHistory.add({
      'type': 'contact',
      'action': 'update',
      'app': app.id,
      'contactId': contactId,
      'label': contactLabel,
    });
  }

  /// Delete a contact
  /// Format: delete contactLabel
  Future<void> _deleteContact(
    AppInstance app,
    List<String> args,
    String originalCommand,
  ) async {
    if (args.isEmpty) {
      throw FormatException('Contact delete requires label: $originalCommand');
    }

    final contactLabel = args[0];
    final contactId = contactIds[contactLabel];
    if (contactId == null) {
      throw ArgumentError('Contact label not found: $contactLabel');
    }

    await app.deleteContact(contactId);

    eventHistory.add({
      'type': 'contact',
      'action': 'delete',
      'app': app.id,
      'contactId': contactId,
      'label': contactLabel,
    });
  }

  /// Create a transaction
  /// Format: create contactLabel direction amount ["description"] [label]
  Future<void> _createTransaction(
    AppInstance app,
    List<String> args,
    String originalCommand,
  ) async {
    if (args.length < 3) {
      throw FormatException('Transaction create requires: contactLabel direction amount: $originalCommand');
    }

    final contactLabel = args[0];
    final directionStr = args[1].toLowerCase();
    final amount = int.parse(args[2]);

    final contactId = contactIds[contactLabel];
    if (contactId == null) {
      throw ArgumentError('Contact label not found: $contactLabel');
    }

    final direction = directionStr == 'owed'
        ? TransactionDirection.owed
        : TransactionDirection.lent;

    String? description;
    String? label;

    // Parse description and label
    // Format: [contactLabel] [direction] [amount] ["description"] [label]
    // After _parseArgs, quoted strings are already unquoted, so we use position-based logic
    if (args.length == 4) {
      // Only 4 args: contactLabel, direction, amount, label (no description)
      label = args[3];
    } else if (args.length == 5) {
      // 5 args: contactLabel, direction, amount, description, label
      description = args[3];
      label = args[4];
    } else if (args.length > 5) {
      // More than 5 args - description might have spaces, join args[3] to args[length-2], last is label
      description = args.sublist(3, args.length - 1).join(' ');
      label = args[args.length - 1];
    }

    if (label == null) {
      label = 'trans${transactionIds.length + 1}';
    }

    final transaction = await app.createTransaction(
      contactId: contactId,
      direction: direction,
      amount: amount,
      description: description,
    );

    transactionIds[label] = transaction.id;
    print('📝 EventGenerator: Stored transaction label "$label" -> ${transaction.id}');

    eventHistory.add({
      'type': 'transaction',
      'action': 'create',
      'app': app.id,
      'transactionId': transaction.id,
      'label': label,
    });
  }

  /// Update a transaction
  /// Format: update transLabel field value
  Future<void> _updateTransaction(
    AppInstance app,
    List<String> args,
    String originalCommand,
  ) async {
    if (args.length < 3) {
      throw FormatException('Transaction update requires: transLabel field value: $originalCommand');
    }

    final transLabel = args[0];
    final field = args[1].toLowerCase();
    final valueStr = args[2];

    final transactionId = transactionIds[transLabel];
    if (transactionId == null) {
      throw ArgumentError('Transaction label not found: $transLabel');
    }

    final updates = <String, dynamic>{};
    switch (field) {
      case 'amount':
        updates['amount'] = int.parse(valueStr);
        break;
      case 'description':
        updates['description'] = _parseQuotedString(valueStr);
        break;
      default:
        throw FormatException('Unknown transaction field: $field in command: $originalCommand');
    }

    await app.updateTransaction(transactionId, updates);

    eventHistory.add({
      'type': 'transaction',
      'action': 'update',
      'app': app.id,
      'transactionId': transactionId,
      'label': transLabel,
    });
  }

  /// Delete a transaction
  /// Format: delete transLabel
  Future<void> _deleteTransaction(
    AppInstance app,
    List<String> args,
    String originalCommand,
  ) async {
    if (args.isEmpty) {
      throw FormatException('Transaction delete requires label: $originalCommand');
    }

    final transLabel = args[0];
    final transactionId = transactionIds[transLabel];
    if (transactionId == null) {
      throw ArgumentError('Transaction label not found: $transLabel');
    }

    await app.deleteTransaction(transactionId);

    eventHistory.add({
      'type': 'transaction',
      'action': 'delete',
      'app': app.id,
      'transactionId': transactionId,
      'label': transLabel,
    });
  }

  /// Handle undo command
  /// Format: undo contact contactLabel | undo transaction transLabel
  Future<void> _handleUndo(
    AppInstance app,
    List<String> args,
    String originalCommand,
  ) async {
    if (args.isEmpty) {
      throw FormatException('Undo requires type and label: undo contact label or undo transaction label');
    }

    final type = args[0].toLowerCase();
    if (args.length < 2) {
      throw FormatException('Undo requires label: $originalCommand');
    }

    final label = args[1];

    switch (type) {
      case 'contact':
        final contactId = contactIds[label];
        if (contactId == null) {
          throw ArgumentError('Contact label not found: $label');
        }
        await app.undoContactAction(contactId);
        eventHistory.add({
          'type': 'contact',
          'action': 'undo',
          'app': app.id,
          'contactId': contactId,
          'label': label,
        });
        break;
      case 'transaction':
        final transactionId = transactionIds[label];
        if (transactionId == null) {
          throw ArgumentError('Transaction label not found: $label');
        }
        await app.undoTransactionAction(transactionId);
        eventHistory.add({
          'type': 'transaction',
          'action': 'undo',
          'app': app.id,
          'transactionId': transactionId,
          'label': label,
        });
        break;
      default:
        throw FormatException('Unknown undo type: $type in command: $originalCommand');
    }
  }

  /// Parse a quoted string, handling both "quoted" and unquoted formats
  String _parseQuotedString(String str) {
    if (str.startsWith('"') && str.endsWith('"')) {
      return str.substring(1, str.length - 1);
    }
    return str;
  }

  /// Get contact ID by label
  String? getContactId(String label) => contactIds[label];

  /// Get transaction ID by label
  String? getTransactionId(String label) => transactionIds[label];

  /// Get event history
  List<Map<String, dynamic>> get history => List.unmodifiable(eventHistory);
}
