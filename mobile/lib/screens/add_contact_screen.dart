// ignore_for_file: unused_import

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../models/contact.dart';
import '../models/wallet.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/toast_service.dart';
import '../widgets/gradient_background.dart';

class AddContactScreen extends ConsumerStatefulWidget {
  final String? initialName;
  
  const AddContactScreen({super.key, this.initialName});

  @override
  ConsumerState<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<AddContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _notesController = TextEditingController();
  bool _saving = false;
  String? _walletId;
  List<Map<String, dynamic>> _contactGroups = [];
  Set<String> _selectedGroupIds = {};
  bool _groupsLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialName != null) {
      _nameController.text = widget.initialName!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requireWallet();
      _loadGroups();
    });
  }

  Future<void> _loadGroups() async {
    if (kIsWeb) return;
    final walletId = await Api.getCurrentWalletId();
    if (walletId == null || !mounted) return;
    setState(() {
      _walletId = walletId;
      _groupsLoading = true;
    });
    try {
      final groups = await Api.getWalletContactGroups(walletId);
      if (mounted) {
        setState(() {
          _contactGroups = groups;
          _groupsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _groupsLoading = false);
    }
  }

  Future<void> _requireWallet() async {
    if (await Api.getCurrentWalletId() != null) return;
    final list = await Api.getWallets();
    final wallets = list.map((m) => Wallet.fromJson(m)).toList();
    if (wallets.isEmpty && mounted) {
      ToastService.showInfoFromContext(context, 'Create a wallet first to add contacts.');
      Navigator.of(context).pop();
      Navigator.of(context).pushNamed('/create-wallet');
    } else if (wallets.isNotEmpty && mounted) {
      await Api.setCurrentWalletId(wallets.first.id);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
    });

    try {
      final groupIds = _selectedGroupIds.isEmpty ? null : _selectedGroupIds.toList();
      final jsonStr = await Api.createContact(
        name: _nameController.text.trim(),
        username: _usernameController.text.trim().isEmpty ? null : _usernameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        groupIds: groupIds,
      );
      final createdContact = Contact.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
      if (mounted) {
        Navigator.of(context).pop(createdContact);
        ToastService.showSuccessFromContext(context, '✅ Contact created!');
      }
    } catch (e) {
      if (mounted) {
        ToastService.showErrorFromContext(context, 'Error: $e');
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
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Add Contact'),
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
            onPressed: _saving ? null : _saveContact,
            tooltip: 'Save Contact',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Name *',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Name is required';
                }
                return null;
              },
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                hintText: 'English letters and numbers only',
                border: OutlineInputBorder(),
                helperText: 'Optional: English letters and numbers (e.g., Ahmed123)',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            if (!kIsWeb) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Contact groups',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Add this contact to groups (optional). All contacts are in All Contacts.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              if (_groupsLoading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
                )
              else
                ..._contactGroups.map((g) {
                  final groupId = g['id'] as String?;
                  final name = g['name'] as String? ?? '';
                  final isSystem = g['is_system'] as bool? ?? false;
                  if (groupId == null) return const SizedBox.shrink();
                  final selected = _selectedGroupIds.contains(groupId);
                  return CheckboxListTile(
                    value: selected,
                    onChanged: isSystem ? null : (v) => setState(() {
                      if (v == true) {
                        _selectedGroupIds.add(groupId);
                      } else {
                        _selectedGroupIds.remove(groupId);
                      }
                    }),
                    title: Text(name),
                    subtitle: isSystem ? const Text('All contacts (system)', style: TextStyle(fontSize: 12)) : null,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                }),
            ],
          ],
        ),
      ),
      ),
    );
  }
}