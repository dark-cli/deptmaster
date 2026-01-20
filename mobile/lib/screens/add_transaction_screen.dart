import 'package:flutter/material.dart';
import '../utils/text_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../models/contact.dart';
import '../services/local_database_service_v2.dart';
import '../services/dummy_data_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/settings_service.dart';
import '../providers/settings_provider.dart';
import '../utils/app_colors.dart';
import '../utils/theme_colors.dart';
import '../widgets/gradient_background.dart';
import 'add_contact_screen.dart';
import '../utils/bottom_sheet_helper.dart';

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
  bool _loadingContacts = true; // Track loading state

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
      return contact.name.toLowerCase().contains(query) ||
             (contact.username?.toLowerCase().contains(query) ?? false);
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
            _amountController.text = _formatNumber(dataWidget.amount!);
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
    setState(() {
      _loadingContacts = true;
    });
    
    try {
      // Always use local database - never call API from UI
      final contacts = await LocalDatabaseServiceV2.getContacts();
      if (mounted) {
        setState(() {
          _contacts = contacts;
          _loadingContacts = false;
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
      print('Error loading contacts: $e');
      if (mounted) {
        setState(() {
          _loadingContacts = false;
        });
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

  // Parse number to integer (removes commas)
  static int _parseNumber(String value) {
    final digitsOnly = value.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(digitsOnly) ?? 0;
  }

  // Format number with commas using NumberFormat
  static String _formatNumber(int value) {
    return NumberFormat.decimalPattern().format(value);
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

      // Generate UUID for local ID (server expects UUID format)
      final transactionId = DummyDataService.uuid.v4();

      final transaction = Transaction(
        id: transactionId,
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

      // Save to local database (creates event, rebuilds state)
      // Background sync service will handle server communication
      await LocalDatabaseServiceV2.createTransaction(transaction);

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
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Add Transaction'),
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
              tooltip: 'Save Transaction',
            ),
          ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            // Contact search field
            _loadingContacts
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
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _filteredContacts.length + 1, // +1 for "Create new contact"
                            itemBuilder: (context, index) {
                              // Show "Create new contact" option at the end
                              if (index == _filteredContacts.length) {
                                return ListTile(
                                  leading: const Icon(Icons.person_add),
                                  title: const Text('Create new contact'),
                                  subtitle: Text(
                                    _contactSearchController.text.isEmpty
                                        ? 'Type a name to create a new contact'
                                        : 'Create "${_contactSearchController.text}"',
                                  ),
                                  onTap: () async {
                                    final searchText = _contactSearchController.text.trim();
                                    final result = await showScreenAsBottomSheet(
                                      context: context,
                                      screen: AddContactScreen(
                                          initialName: searchText.isNotEmpty ? searchText : null,
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
                                );
                              }
                              
                              // Show filtered contact
                                    final contact = _filteredContacts[index];
                                    return ListTile(
                                      leading: const Icon(Icons.person),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        TextUtils.forceLtr(contact.name), // Force LTR for mixed Arabic/English text
                                      ),
                                    ),
                                    if (contact.username != null && contact.username!.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        '@${contact.username}',
                                        style: TextStyle(
                                          color: ThemeColors.gray(context, shade: 500),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ],
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
