// ignore_for_file: unused_import

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api.dart';
import '../models/contact.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../providers/wallet_data_providers.dart';
import '../utils/toast_service.dart';
import '../widgets/gradient_background.dart';

class EditContactScreen extends ConsumerStatefulWidget {
  final Contact contact;
  /// Wallet context when opening from contact list/transactions (ensures group load/save works for members).
  final String? initialWalletId;

  const EditContactScreen({
    super.key,
    required this.contact,
    this.initialWalletId,
  });

  @override
  ConsumerState<EditContactScreen> createState() => _EditContactScreenState();
}

class _EditContactScreenState extends ConsumerState<EditContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _notesController = TextEditingController();
  bool _saving = false;
  String? _walletId;
  List<Map<String, dynamic>> _contactGroups = [];
  Set<String> _contactGroupIds = {};
  Set<String> _initialGroupIds = {};
  bool _groupsLoading = true;
  String? _groupsError;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.contact.name;
    _phoneController.text = widget.contact.phone ?? '';
    _emailController.text = widget.contact.email ?? '';
    _notesController.text = widget.contact.notes ?? '';
    if (widget.initialWalletId != null && widget.initialWalletId!.isNotEmpty) {
      _walletId = widget.initialWalletId;
    }
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    if (kIsWeb) return;
    final currentWalletId = await Api.getCurrentWalletId();
    final walletId = currentWalletId ?? widget.initialWalletId ?? widget.contact.walletId;
    if (walletId == null || walletId.isEmpty || !mounted) return;
    setState(() {
      _walletId = walletId;
      _groupsLoading = true;
      _groupsError = null;
    });
    try {
      final groups = await Api.getWalletContactGroups(walletId);
      final ids = await Api.getContactGroupIdsForContact(walletId, widget.contact.id);
      if (mounted) {
        setState(() {
          _contactGroups = groups;
          _contactGroupIds = ids.toSet();
          _initialGroupIds = ids.toSet();
          _groupsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _groupsError = e.toString();
          _groupsLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _toggleContactGroup(String groupId, bool isSystem) {
    if (isSystem) return;
    setState(() {
      if (_contactGroupIds.contains(groupId)) {
        _contactGroupIds.remove(groupId);
      } else {
        _contactGroupIds.add(groupId);
      }
    });
  }

  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
    });

    try {
      await Api.updateContact(
        id: widget.contact.id,
        name: _nameController.text.trim(),
        username: widget.contact.username,
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        groupIds: !kIsWeb ? _contactGroupIds.toList() : null,
      );

      ref.invalidate(contactsProvider);
      ref.invalidate(transactionsProvider);

      if (mounted) {
        Navigator.of(context).pop(true);
        ToastService.showSuccessFromContext(context, '✅ Contact updated!');
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
          title: const Text('Edit Contact'),
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
            tooltip: 'Update Contact',
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
              const SizedBox(height: 8),
              if (_groupsLoading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_groupsError != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_groupsError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                )
              else
                ..._contactGroups.map((g) {
                  final groupId = g['id'] as String?;
                  final name = g['name'] as String? ?? '';
                  final isSystem = g['is_system'] as bool? ?? false;
                  if (groupId == null) return const SizedBox.shrink();
                  final inGroup = _contactGroupIds.contains(groupId);
                  return CheckboxListTile(
                    value: inGroup,
                    onChanged: isSystem ? null : (v) => _toggleContactGroup(groupId, isSystem),
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