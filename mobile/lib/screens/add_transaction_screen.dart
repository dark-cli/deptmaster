// ignore_for_file: unused_import

import 'dart:convert';
import 'package:flutter/material.dart';
import '../api.dart';
import '../utils/text_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/transaction.dart';
import '../models/contact.dart';
import '../models/wallet.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../providers/settings_provider.dart';
import '../providers/wallet_data_providers.dart';
import '../utils/app_colors.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_service.dart';
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
  bool _amountHasText = false;
  
  Contact? _selectedContact;
  TransactionDirection _direction = TransactionDirection.owed;
  DateTime _selectedDate = DateTime.now();
  DateTime? _dueDate;
  bool _dueDateSwitchEnabled = false; // Switch state for due date
  bool _isClosingTransaction = false; // Track if this is a closing transaction
  bool _saving = false;
  List<Contact> _contacts = [];
  List<Contact> _filteredContacts = [];
  bool _showContactSuggestions = false;
  bool _loadingContacts = true; // Track loading state
  ProviderSubscription<AsyncValue<List<Contact>>>? _contactsSub;
  String? _contactsLoadError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _prefillData();
    _contactSearchController.addListener(_onContactSearchChanged);
    _amountController.addListener(_onAmountChanged);
    _descriptionController.addListener(_onDescriptionChanged);
    _amountHasText = _amountController.text.isNotEmpty;
    _isClosingTransaction = _descriptionController.text.startsWith('Close:');
    WidgetsBinding.instance.addPostFrameCallback((_) => _requireWallet());

    // Keep local suggestion lists in sync with provider (no direct refetch loops).
    _contactsSub = ref.listenManual<AsyncValue<List<Contact>>>(contactsProvider, (previous, next) {
      if (!mounted) return;
      if (next.hasError) {
        setState(() {
          _contactsLoadError = next.error.toString();
          _loadingContacts = false;
        });
        return;
      }
      final contacts = next.valueOrNull;
      if (contacts == null) return;

      setState(() {
        _contacts = contacts;
        _loadingContacts = next.isLoading && contacts.isEmpty;
        _contactsLoadError = null;

        // If contact is provided, keep it selected (but update instance from latest list if possible).
        if (widget.contact != null && _contacts.isNotEmpty) {
          _selectedContact = _contacts.firstWhere(
            (c) => c.id == widget.contact!.id,
            orElse: () => widget.contact!,
          );
          _contactSearchController.text = _selectedContact?.name ?? '';
          _showContactSuggestions = false;
          _filteredContacts = [];
        }
      });

      // Update suggestions if user is searching.
      _onContactSearchChanged();
    }, fireImmediately: true);
  }

  Future<void> _requireWallet() async {
    if (await Api.getCurrentWalletId() != null) return;
    final list = await Api.getWallets();
    final wallets = list.map((m) => Wallet.fromJson(m)).toList();
    if (wallets.isEmpty && mounted) {
      ToastService.showInfoFromContext(context, 'Create a wallet first to add transactions.');
      Navigator.of(context).pop();
      Navigator.of(context).pushNamed('/create-wallet');
    } else if (wallets.isNotEmpty && mounted) {
      await Api.setCurrentWalletId(wallets.first.id);
    }
  }

  void _onAmountChanged() {
    setState(() {
      _amountHasText = _amountController.text.isNotEmpty;
    });
  }

  void _onDescriptionChanged() {
    setState(() {
      _isClosingTransaction = _descriptionController.text.startsWith('Close:');
      if (_isClosingTransaction) {
        // Disable due date when closing transaction
        _dueDateSwitchEnabled = false;
        _dueDate = null;
      }
    });
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
            // If description starts with "Close:", disable due date (it's a closing transaction)
            final isClosing = dataWidget.description!.startsWith('Close:');
            if (isClosing) {
              _dueDateSwitchEnabled = false;
              _dueDate = null;
              _isClosingTransaction = true;
            }
          }
        });
      }
    }
  }

  Future<void> _loadSettings() async {
    final defaultDir = await Api.getDefaultDirection();
    final defaultDueDateSwitch = await Api.getDefaultDueDateSwitch();
    final defaultDays = await Api.getDefaultDueDateDays();
    
    if (mounted) {
      setState(() {
        // Only set default direction if not pre-filled
        // Default: 'received' maps to TransactionDirection.owed, 'give' maps to TransactionDirection.lent
        if (widget is! AddTransactionScreenWithData || 
            (widget as AddTransactionScreenWithData).direction == null) {
          _direction = defaultDir == 'received' 
              ? TransactionDirection.owed 
              : TransactionDirection.lent;
        }
        _dueDateSwitchEnabled = defaultDueDateSwitch;
        if (defaultDueDateSwitch) {
          _dueDate = DateTime.now().add(Duration(days: defaultDays));
        }
      });
    }
  }

  void _requestContactsRefresh() {
    ref.invalidate(contactsProvider);
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
      ToastService.showInfoFromContext(context, 'Please select a contact');
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final amountText = _amountController.text.trim();
      final amount = _parseNumber(amountText);

      final jsonStr = await Api.createTransaction(
        contactId: _selectedContact!.id,
        type: 'money',
        direction: _direction == TransactionDirection.owed ? 'owed' : 'lent',
        amount: amount,
        currency: 'IQD',
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        transactionDate: _selectedDate.toIso8601String().split('T')[0],
        dueDate: _dueDateSwitchEnabled && _dueDate != null ? _dueDate!.toIso8601String().split('T')[0] : null,
      );
      final created = Transaction.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

      if (mounted) {
        Navigator.of(context).pop(true);
        ToastService.showUndoWithErrorHandlingFromContext(
          context: context,
          message: '✅ Transaction created!',
          onUndo: () => Api.undoTransactionAction(created.id),
          successMessage: 'Transaction undone',
        );
      }
    } catch (e) {
      // Use showError instead of showErrorFromContext to avoid deactivated widget errors
      // The context might be deactivated by the time the error occurs
      if (mounted) {
        try {
          ToastService.showErrorFromContext(context, 'Error: $e');
        } catch (_) {
          // If context is deactivated, use global error handler
          ToastService.showError('Error: $e');
        }
      } else {
        // Widget is not mounted, use global error handler
        ToastService.showError('Error: $e');
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
    _contactsSub?.close();
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _descriptionController.removeListener(_onDescriptionChanged);
    _descriptionController.dispose();
    _contactSearchController.removeListener(_onContactSearchChanged);
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
                : _contactsLoadError != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Error loading contacts: $_contactsLoadError', style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 8),
                          ElevatedButton(
                            onPressed: _requestContactsRefresh,
                            child: const Text('Retry'),
                          ),
                        ],
                      )
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
                                      setState(() {
                                        _selectedContact = result;
                                        _contactSearchController.text = result.name;
                                        _filteredContacts = [];
                                        _showContactSuggestions = false;
                                      });
                                      _requestContactsRefresh();
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
            
            // Direction selector - Simple radio buttons for "Gave" or "Received"
            Consumer(
              builder: (context, ref, child) {
                final flipColors = ref.watch(flipColorsProvider);
                final isDark = Theme.of(context).brightness == Brightness.dark;
                // Standardized: Received (owed) = red, Gave (lent) = green
                final gaveColor = AppColors.getGiveColor(flipColors, isDark);
                final receivedColor = AppColors.getReceivedColor(flipColors, isDark);
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RadioListTile<TransactionDirection>(
                      title: Row(
                        children: [
                          Icon(Icons.arrow_upward, color: gaveColor, size: 20),
                          const SizedBox(width: 8),
                          Text('Gave', style: TextStyle(color: gaveColor)),
                        ],
                      ),
                      value: TransactionDirection.lent,
                      groupValue: _direction,
                      onChanged: (TransactionDirection? value) {
                        if (value != null) {
                          setState(() {
                            _direction = value;
                          });
                        }
                      },
                    ),
                    RadioListTile<TransactionDirection>(
                      title: Row(
                        children: [
                          Icon(Icons.arrow_downward, color: receivedColor, size: 20),
                          const SizedBox(width: 8),
                          Text('Received', style: TextStyle(color: receivedColor)),
                        ],
                      ),
                      value: TransactionDirection.owed,
                      groupValue: _direction,
                      onChanged: (TransactionDirection? value) {
                        if (value != null) {
                          setState(() {
                            _direction = value;
                          });
                        }
                      },
                    ),
                  ],
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
                hintText: 'Enter amount',
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
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (value) {
                // Enter key pressed - save and finish
                _saveTransaction();
              },
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
              onChanged: _isClosingTransaction 
                  ? null // Disable switch when closing transaction
                  : (value) async {
                      setState(() {
                        _dueDateSwitchEnabled = value;
                      });
                      if (value && _dueDate == null) {
                        // Set default due date when switch is turned on
                        final defaultDays = await Api.getDefaultDueDateDays();
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
              secondary: _dueDateSwitchEnabled && !_isClosingTransaction
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