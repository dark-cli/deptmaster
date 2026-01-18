import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../utils/text_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/transaction.dart';
import '../models/contact.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';
import '../utils/theme_colors.dart';
import 'add_contact_screen.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  final Contact? contact; // Optional - if provided, contact is pre-selected and fixed

  const AddTransactionScreen({super.key, this.contact});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

// Alias for when called from contact screen
class AddTransactionScreenForContact extends AddTransactionScreen {
  const AddTransactionScreenForContact({super.key, required Contact contact})
      : super(contact: contact);
}

// Screen with pre-filled data (for reverse transactions)
class AddTransactionScreenWithData extends AddTransactionScreen {
  final int? amount;
  final TransactionDirection? direction;
  final String? description;

  const AddTransactionScreenWithData({
    super.key,
    required Contact? contact,
    this.amount,
    this.direction,
    this.description,
  }) : super(contact: contact);
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _contactSearchController = TextEditingController();
  
  Contact? _selectedContact;
  TransactionDirection _direction = TransactionDirection.owed;
  DateTime _selectedDate = DateTime.now();
  DateTime? _dueDate;
  bool _dueDateSwitchEnabled = false; // Switch state for due date
  bool _saving = false;
  List<Contact> _contacts = [];
  List<Contact> _filteredContacts = [];
  bool _showContactSuggestions = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _loadSettings();
    _prefillData();
    _contactSearchController.addListener(_onContactSearchChanged);
  }

  void _onContactSearchChanged() {
    final query = _contactSearchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      setState(() {
        _filteredContacts = [];
        _showContactSuggestions = false;
        _selectedContact = null;
      });
      return;
    }

    final filtered = _contacts.where((contact) {
      return contact.name.toLowerCase().contains(query);
    }).toList();

    setState(() {
      _filteredContacts = filtered;
      _showContactSuggestions = true;
      // If there's an exact match, auto-select it
      final exactMatch = filtered.firstWhere(
        (c) => c.name.toLowerCase() == query,
        orElse: () => Contact(
          id: '',
          name: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          balance: 0,
        ),
      );
      if (exactMatch.id.isNotEmpty) {
        _selectedContact = exactMatch;
      } else {
        _selectedContact = null;
      }
    });
  }

  void _prefillData() {
    // Check if widget is AddTransactionScreenWithData and pre-fill data
    if (widget is AddTransactionScreenWithData) {
      final dataWidget = widget as AddTransactionScreenWithData;
      if (mounted) {
        setState(() {
          if (dataWidget.amount != null) {
            // Format amount with commas
            final formatted = dataWidget.amount!.toString().replaceAllMapped(
              RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
              (Match m) => '${m[1]},',
            );
            _amountController.text = formatted;
          }
          if (dataWidget.direction != null) {
            _direction = dataWidget.direction!;
          }
          if (dataWidget.description != null) {
            _descriptionController.text = dataWidget.description!;
          }
        });
      }
    }
  }

  Future<void> _loadSettings() async {
    final defaultDir = await SettingsService.getDefaultDirection();
    final defaultDueDateSwitch = await SettingsService.getDefaultDueDateSwitch();
    final defaultDays = await SettingsService.getDefaultDueDateDays();
    
    if (mounted) {
      setState(() {
        // Only set default direction if not pre-filled
        if (widget is! AddTransactionScreenWithData || 
            (widget as AddTransactionScreenWithData).direction == null) {
          _direction = defaultDir == 'give' 
              ? TransactionDirection.lent 
              : TransactionDirection.owed;
        }
        _dueDateSwitchEnabled = defaultDueDateSwitch;
        if (defaultDueDateSwitch) {
          _dueDate = DateTime.now().add(Duration(days: defaultDays));
        }
      });
    }
  }

  Future<void> _loadContacts() async {
    try {
      final contacts = await ApiService.getContacts();
      if (mounted) {
        setState(() {
          _contacts = contacts;
          // If contact is provided, find it in the loaded list by ID
          if (widget.contact != null && _contacts.isNotEmpty) {
            _selectedContact = _contacts.firstWhere(
              (c) => c.id == widget.contact!.id,
              orElse: () => _contacts.first,
            );
            _contactSearchController.text = _selectedContact?.name ?? '';
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

  // Format number with thousands separators
  static String _formatNumber(String value) {
    // Remove all non-digit characters
    final digitsOnly = value.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.isEmpty) return '';
    
    // Parse as integer and format with commas
    final number = int.tryParse(digitsOnly);
    if (number == null) return value;
    
    return number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  // Parse formatted number back to integer
  static int _parseFormattedNumber(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(digitsOnly) ?? 0;
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
      final amount = _parseFormattedNumber(amountText); // Parse formatted number

      final transaction = Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(), // Temporary ID
        contactId: _selectedContact!.id,
        type: TransactionType.money, // Always money (items removed)
        direction: _direction,
        amount: amount,
        currency: 'IQD',
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        transactionDate: _selectedDate,
        dueDate: _dueDateSwitchEnabled ? _dueDate : null,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Call API to create transaction
      await ApiService.createTransaction(transaction);

      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Transaction created!')),
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
    _amountController.dispose();
    _descriptionController.dispose();
    _contactSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Transaction'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Contact search field
            _contacts.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _contactSearchController,
                        decoration: InputDecoration(
                          labelText: 'Contact *',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.person_search),
                          suffixIcon: _contactSearchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() {
                                      _contactSearchController.clear();
                                      _selectedContact = null;
                                      _filteredContacts = [];
                                      _showContactSuggestions = false;
                                    });
                                  },
                                )
                              : null,
                        ),
                        enabled: widget.contact == null,
                        validator: (value) {
                          if (_selectedContact == null && (value == null || value.trim().isEmpty)) {
                            return 'Please select or create a contact';
                          }
                          return null;
                        },
                        onChanged: (value) {
                          // Trigger search when text changes
                          _onContactSearchChanged();
                        },
                        onTap: () {
                          if (widget.contact == null) {
                            setState(() {
                              _showContactSuggestions = true;
                            });
                          }
                        },
                      ),
                      // Show filtered contacts or create new button
                      if (_showContactSuggestions && widget.contact == null) ...[
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 200),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _filteredContacts.isEmpty
                              ? ListTile(
                                  leading: const Icon(Icons.person_add),
                                  title: const Text('Create new contact'),
                                  subtitle: Text(
                                    _contactSearchController.text.isEmpty
                                        ? 'Type a name to create a new contact'
                                        : 'Create "${_contactSearchController.text}"',
                                  ),
                                  onTap: () async {
                                    final searchText = _contactSearchController.text.trim();
                                    final result = await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) => AddContactScreen(
                                          initialName: searchText.isNotEmpty ? searchText : null,
                                        ),
                                      ),
                                    );
                                    if (result != null && result is Contact && mounted) {
                                      // Reload contacts to get the new one
                                      await _loadContacts();
                                      // Find and select the new contact
                                      final newContact = _contacts.firstWhere(
                                        (c) => c.id == result.id,
                                        orElse: () => result,
                                      );
                                      setState(() {
                                        _selectedContact = newContact;
                                        _contactSearchController.text = newContact.name;
                                        _filteredContacts = [];
                                        _showContactSuggestions = false;
                                      });
                                    }
                                  },
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _filteredContacts.length,
                                  itemBuilder: (context, index) {
                                    final contact = _filteredContacts[index];
                                    return ListTile(
                                      leading: const Icon(Icons.person),
                                      title: Text(
                                        TextUtils.forceLtr(contact.name), // Force LTR for mixed Arabic/English text
                                      ),
                                      onTap: () {
                                        setState(() {
                                          _selectedContact = contact;
                                          _contactSearchController.text = contact.name;
                                          _showContactSuggestions = false;
                                        });
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ],
                  ),
            const SizedBox(height: 16),
            
            // Direction selector - "Give" or "Received"
            Consumer(
              builder: (context, ref, child) {
                final flipColors = ref.watch(flipColorsProvider);
                final isDark = Theme.of(context).brightness == Brightness.dark;
                final giveColor = AppColors.getGiveColor(flipColors, isDark);
                final receivedColor = AppColors.getReceivedColor(flipColors, isDark);
                
                return SegmentedButton<TransactionDirection>(
                  segments: [
                    ButtonSegment(
                      value: TransactionDirection.lent,
                      label: const Text('Give'),
                      icon: Icon(Icons.arrow_upward, color: giveColor),
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
              decoration: const InputDecoration(
                labelText: 'Amount (IQD) *',
                border: OutlineInputBorder(),
                hintText: 'Enter amount',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d,]')),
                TextInputFormatter.withFunction((oldValue, newValue) {
                  // Format the number with commas as user types
                  final formatted = _formatNumber(newValue.text);
                  // Preserve cursor position
                  final cursorOffset = newValue.selection.baseOffset;
                  final newCursorOffset = formatted.length - (oldValue.text.length - cursorOffset);
                  return TextEditingValue(
                    text: formatted,
                    selection: TextSelection.collapsed(
                      offset: newCursorOffset.clamp(0, formatted.length),
                    ),
                  );
                }),
              ],
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Amount is required';
                }
                final parsed = _parseFormattedNumber(value);
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
            const SizedBox(height: 24),
            
            // Save button
            Semantics(
              button: true,
              label: 'Save transaction',
              child: ElevatedButton(
                onPressed: _saving ? null : _saveTransaction,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Transaction'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
