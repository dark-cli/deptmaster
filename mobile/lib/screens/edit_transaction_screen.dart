import 'package:flutter/material.dart';
import '../utils/text_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../models/contact.dart';
import '../services/local_database_service_v2.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/settings_service.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';
import '../utils/theme_colors.dart';
import '../widgets/gradient_background.dart';

class EditTransactionScreen extends ConsumerStatefulWidget {
  final Transaction transaction;
  final Contact? contact; // Optional - if provided, contact is fixed

  const EditTransactionScreen({
    super.key,
    required this.transaction,
    this.contact,
  });

  @override
  ConsumerState<EditTransactionScreen> createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends ConsumerState<EditTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  bool _amountHasText = false;
  
  Contact? _selectedContact;
  TransactionDirection _direction = TransactionDirection.owed;
  DateTime _selectedDate = DateTime.now();
  DateTime? _dueDate;
  bool _dueDateSwitchEnabled = false; // Switch state for due date
  bool _saving = false;
  List<Contact> _contacts = [];

  // Parse number to integer (removes commas)
  static int _parseNumber(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(digitsOnly) ?? 0;
  }

  // Format number with commas using NumberFormat
  static String _formatNumber(int value) {
    return NumberFormat.decimalPattern().format(value);
  }

  @override
  void initState() {
    super.initState();
    // Initialize with transaction data - format with commas
    _amountController.text = _formatNumber(widget.transaction.amount);
    _descriptionController.text = widget.transaction.description ?? '';
    _direction = widget.transaction.direction;
    _selectedDate = widget.transaction.transactionDate;
    _dueDate = widget.transaction.dueDate;
    _dueDateSwitchEnabled = widget.transaction.dueDate != null;
    _amountHasText = _amountController.text.isNotEmpty;
    _amountController.addListener(_onAmountChanged);
    _loadContacts();
    _loadSettings();
  }

  void _onAmountChanged() {
    setState(() {
      _amountHasText = _amountController.text.isNotEmpty;
    });
  }

  Future<void> _loadSettings() async {
    // Settings loaded, but due date switch state comes from transaction data
  }

  Future<void> _loadContacts() async {
    try {
      // Always use local database - never call API from UI
      final contacts = await LocalDatabaseServiceV2.getContacts();
      if (mounted) {
        setState(() {
          _contacts = contacts;
          // Set selected contact - find by ID from loaded list
          if (widget.contact != null && contacts.isNotEmpty) {
            _selectedContact = contacts.firstWhere(
              (c) => c.id == widget.contact!.id,
              orElse: () => contacts.firstWhere(
                (c) => c.id == widget.transaction.contactId,
                orElse: () => contacts.first,
              ),
            );
          } else if (contacts.isNotEmpty) {
            _selectedContact = contacts.firstWhere(
              (c) => c.id == widget.transaction.contactId,
              orElse: () => contacts.first,
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading contacts: $e')),
        );
      }
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _dueDate = picked;
      });
    }
  }

  Future<void> _saveTransaction() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedContact == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a contact')),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final amountText = _amountController.text.trim();
      final amount = _parseNumber(amountText);

      // Always update local database first (instant, snappy)
      // Background sync service will handle server communication
      final updatedTransaction = Transaction(
        id: widget.transaction.id,
        contactId: _selectedContact!.id,
        type: widget.transaction.type,
        direction: _direction,
        amount: amount,
        currency: widget.transaction.currency,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        transactionDate: _selectedDate,
        dueDate: _dueDateSwitchEnabled ? _dueDate : null,
        imagePaths: widget.transaction.imagePaths,
        createdAt: widget.transaction.createdAt,
        updatedAt: DateTime.now(),
        isSynced: false, // Mark as unsynced since we're updating locally
      );
      await LocalDatabaseServiceV2.updateTransaction(updatedTransaction);

      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Transaction updated!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
        title: const Text('Edit Transaction'),
        actions: [
          IconButton(
            icon: _saving
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  )
                : Icon(
                    Icons.save,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            onPressed: _saving ? null : _saveTransaction,
            tooltip: 'Update Transaction',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete Transaction'),
                  content: const Text('Are you sure you want to delete this transaction?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );

              if (confirm == true && mounted) {
                try {
                  // Delete from local database (creates event, rebuilds state)
                  await LocalDatabaseServiceV2.deleteTransaction(widget.transaction.id);
                  
                  if (!mounted) return;
                  Navigator.of(context).pop(true); // Return true to refresh
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ Transaction deleted!')),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error deleting: $e')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            // Contact selector (disabled if contact is fixed)
            _contacts.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<Contact>(
                    value: _selectedContact,
                    decoration: const InputDecoration(
                      labelText: 'Contact *',
                      border: OutlineInputBorder(),
                    ),
                    items: _contacts.map((contact) {
                      return DropdownMenuItem(
                        value: contact,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                TextUtils.forceLtr(contact.name), // Force LTR for mixed Arabic/English text
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            if (contact.username != null && contact.username!.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '@${contact.username}',
                                  style: TextStyle(
                                    color: ThemeColors.gray(context, shade: 500),
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: widget.contact != null ? null : (contact) {
                      setState(() {
                        _selectedContact = contact;
                      });
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Please select a contact';
                      }
                      return null;
                    },
                  ),
            const SizedBox(height: 16),
            
            // Direction selector - "Gave" or "Received"
            Consumer(
              builder: (context, ref, child) {
                final flipColors = ref.watch(flipColorsProvider);
                final isDark = Theme.of(context).brightness == Brightness.dark;
                // Standardized: Gave (lent) = red, Received (owed) = green
                final gaveColor = AppColors.getGiveColor(flipColors, isDark);
                final receivedColor = AppColors.getReceivedColor(flipColors, isDark);
                
                return SegmentedButton<TransactionDirection>(
                  segments: [
                    ButtonSegment(
                      value: TransactionDirection.lent,
                      label: const Text('Gave'),
                      icon: Icon(Icons.arrow_upward, color: gaveColor),
                    ),
                    ButtonSegment(
                      value: TransactionDirection.owed,
                      label: const Text('Received'),
                      icon: Icon(Icons.arrow_downward, color: receivedColor),
                    ),
                  ],
                  selected: {_direction},
                  onSelectionChanged: (Set<TransactionDirection> newSelection) {
                    setState(() {
                      _direction = newSelection.first;
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 16),
            
            // Amount
            TextFormField(
              controller: _amountController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Amount (IQD) *',
                border: const OutlineInputBorder(),
                suffixIcon: _amountHasText
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _amountController.clear();
                          setState(() {
                            _amountHasText = false;
                          });
                        },
                        tooltip: 'Clear',
                      )
                    : null,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                // Allow digits and commas
                FilteringTextInputFormatter.allow(RegExp(r'[\d,]')),
                // Simple formatter: add commas every 3 digits from right
                TextInputFormatter.withFunction((oldValue, newValue) {
                  // Remove all commas, then add them back
                  final digitsOnly = newValue.text.replaceAll(',', '');
                  if (digitsOnly.isEmpty) {
                    return const TextEditingValue(text: '');
                  }
                  
                  // Format with commas using NumberFormat
                  final number = int.tryParse(digitsOnly);
                  if (number == null) {
                    return oldValue; // Invalid input, keep old value
                  }
                  
                  final formatted = _formatNumber(number);
                  
                  // Try to preserve cursor position
                  final oldCursor = newValue.selection.baseOffset;
                  final oldTextLength = oldValue.text.length;
                  
                  // Simple cursor adjustment: if at end, stay at end
                  int newCursor;
                  if (oldCursor >= oldTextLength) {
                    newCursor = formatted.length;
                  } else {
                    // Count digits before cursor in old text
                    final digitsBeforeCursor = oldValue.text
                        .substring(0, oldCursor)
                        .replaceAll(',', '')
                        .length;
                    // Find position in new text with same digit count
                    int digitsSeen = 0;
                    newCursor = formatted.length;
                    for (int i = 0; i < formatted.length; i++) {
                      if (RegExp(r'\d').hasMatch(formatted[i])) {
                        digitsSeen++;
                        if (digitsSeen > digitsBeforeCursor) {
                          newCursor = i;
                          break;
                        }
                      }
                    }
                  }
                  
                  return TextEditingValue(
                    text: formatted,
                    selection: TextSelection.collapsed(
                      offset: newCursor.clamp(0, formatted.length),
                    ),
                  );
                }),
              ],
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Amount is required';
                }
                final parsed = _parseNumber(value);
                if (parsed == 0) {
                  return 'Please enter a valid number';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Date
            InkWell(
              onTap: _selectDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date *',
                  border: OutlineInputBorder(),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                    ),
                    const Icon(Icons.calendar_today),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Due Date Switch
            SwitchListTile(
              title: const Text('Due Date'),
              subtitle: Text(
                _dueDateSwitchEnabled && _dueDate != null
                    ? '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}'
                    : 'Not set',
              ),
              value: _dueDateSwitchEnabled,
              onChanged: (value) async {
                setState(() {
                  _dueDateSwitchEnabled = value;
                });
                if (value && _dueDate == null) {
                  // Set default due date when switch is turned on
                  final defaultDays = await SettingsService.getDefaultDueDateDays();
                  if (mounted) {
                    setState(() {
                      _dueDate = DateTime.now().add(Duration(days: defaultDays));
                    });
                  }
                } else if (!value) {
                  setState(() {
                    _dueDate = null;
                  });
                }
              },
              secondary: _dueDateSwitchEnabled
                  ? IconButton(
                      icon: const Icon(Icons.calendar_today),
                      onPressed: _selectDueDate,
                      tooltip: 'Select due date',
                    )
                  : null,
            ),
            if (_dueDateSwitchEnabled && _dueDate != null) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: _selectDueDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Due Date',
                    border: OutlineInputBorder(),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}',
                      ),
                      const Icon(Icons.event),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // Description
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
      ),
    );
  }
}
