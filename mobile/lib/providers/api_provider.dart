import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api.dart';
import '../connection_state.dart' show AppConnectionState, ConnectionStateValue;
import '../prefs.dart';
import '../bootstrap.dart';

/// App-scoped API. Api is thin 1:1 to Rust; this provider adds decoding and wires ConnectionState/Prefs.
class AppApi {
  AppApi._();
  static final AppApi _instance = AppApi._();
  /// Singleton access for code that doesn't have [ref] (e.g. inner State classes).
  static AppApi get instance => _instance;
  static String? _cachedWalletId;

  Future<void> login(String username, String password) =>
      Api.login(username, password);
  Future<void> register(String username, String password) =>
      Api.register(username, password);
  Future<void> logout() async {
    await Api.logout();
    await AppConnectionState.disconnectRealtime();
    _cachedWalletId = null;
    AppConnectionState.notifyDataChanged();
    Bootstrap.onLogout?.call();
  }

  Future<bool> isLoggedIn() => Api.isLoggedIn();
  Future<String?> getUserId() => Api.getUserId();
  Future<String?> getToken() => Api.getToken();

  Future<String?> getUsername() => Api.getUsername();

  Future<bool> validateAuth() async {
    try {
      await Api.manualSync();
      AppConnectionState.setSyncError(false);
      AppConnectionState.setAuthIssue(false);
      return true;
    } catch (e) {
      if (e.toString().toLowerCase().contains('debitum_auth_declined')) {
        AppConnectionState.setAuthIssue(true);
        return false;
      }
      AppConnectionState.setSyncError(true);
      return true;
    }
  }

  Future<String?> getCurrentWalletId() async {
    final id = await Api.getCurrentWalletId();
    _cachedWalletId = (id == null || id.isEmpty) ? null : id;
    return id;
  }

  Future<void> setCurrentWalletId(String walletId) async {
    await Api.setCurrentWalletId(walletId);
    _cachedWalletId = walletId;
    AppConnectionState.notifyDataChanged();
    await AppConnectionState.disconnectRealtime();
    AppConnectionState.connectRealtime().catchError((_) {});
  }

  bool get hasWalletSelected =>
      _cachedWalletId != null && _cachedWalletId!.isNotEmpty;

  Future<List<Map<String, dynamic>>> getWallets() async =>
      Api.getWallets();

  Future<Map<String, dynamic>?> createWallet(
          String name, String description) async =>
      Api.createWallet(name, description);

  Future<void> ensureCurrentWallet() async {
    await Api.ensureCurrentWallet();
    final id = await Api.getCurrentWalletId();
    if (id != null && id.isNotEmpty && _cachedWalletId != id) {
      _cachedWalletId = id;
      AppConnectionState.notifyDataChanged();
      await AppConnectionState.disconnectRealtime();
      AppConnectionState.connectRealtime().catchError((_) {});
    }
  }

  Future<Map<String, dynamic>?> getWallet(String id) async {
    final list = await getWallets();
    try {
      return list.firstWhere((w) => w['id'] == id);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getWalletUsers(String walletId) async =>
      Api.getWalletUsers(walletId);

  Future<List<Map<String, dynamic>>> searchWalletUsers(
          String walletId, String query) async =>
      Api.searchWalletUsers(walletId, query);

  Future<void> addUserToWallet(String walletId, String username) =>
      Api.addUserToWallet(walletId, username);
  Future<String> createWalletInviteCode(String walletId) =>
      Api.createWalletInviteCode(walletId);
  Future<String> joinWalletByCode(String code) => Api.joinWalletByCode(code);
  Future<void> updateWalletUserRole(
          String walletId, String userId, String role) =>
      Api.updateWalletUserRole(walletId, userId, role);
  Future<void> removeWalletUser(String walletId, String userId) =>
      Api.removeWalletUser(walletId, userId);

  Future<List<Map<String, dynamic>>> getWalletUserGroups(String walletId) async =>
      Api.getWalletUserGroups(walletId);

  Future<Map<String, dynamic>> createWalletUserGroup(
          String walletId, String name) async =>
      Api.createWalletUserGroup(walletId, name);
  Future<void> updateWalletUserGroup(
          String walletId, String groupId, String name) =>
      Api.updateWalletUserGroup(walletId, groupId, name);
  Future<void> deleteWalletUserGroup(String walletId, String groupId) =>
      Api.deleteWalletUserGroup(walletId, groupId);
  Future<List<Map<String, dynamic>>> getWalletUserGroupMembers(
          String walletId, String groupId) async =>
      Api.getWalletUserGroupMembers(walletId, groupId);

  Future<void> addWalletUserGroupMember(
          String walletId, String groupId, String userId) =>
      Api.addWalletUserGroupMember(walletId, groupId, userId);
  Future<void> removeWalletUserGroupMember(
          String walletId, String groupId, String userId) =>
      Api.removeWalletUserGroupMember(walletId, groupId, userId);

  Future<List<Map<String, dynamic>>> getWalletContactGroups(
          String walletId) async =>
      Api.getWalletContactGroups(walletId);

  Future<Map<String, dynamic>> createWalletContactGroup(
          String walletId, String name) async =>
      Api.createWalletContactGroup(walletId, name);
  Future<void> updateWalletContactGroup(
          String walletId, String groupId, String name) =>
      Api.updateWalletContactGroup(walletId, groupId, name);
  Future<void> deleteWalletContactGroup(String walletId, String groupId) =>
      Api.deleteWalletContactGroup(walletId, groupId);
  Future<List<Map<String, dynamic>>> getWalletContactGroupMembers(
          String walletId, String groupId) async =>
      Api.getWalletContactGroupMembers(walletId, groupId);

  Future<void> addWalletContactGroupMember(
          String walletId, String groupId, String contactId) =>
      Api.addWalletContactGroupMember(walletId, groupId, contactId);
  Future<void> removeWalletContactGroupMember(
          String walletId, String groupId, String contactId) =>
      Api.removeWalletContactGroupMember(walletId, groupId, contactId);

  Future<List<Map<String, dynamic>>> getWalletPermissionActions(
          String walletId) async =>
      Api.getWalletPermissionActions(walletId);

  Future<List<Map<String, dynamic>>> getWalletPermissionMatrix(
          String walletId) async =>
      Api.getWalletPermissionMatrix(walletId);

  Future<void> putWalletPermissionMatrix(
          String walletId, List<Map<String, dynamic>> entries) =>
      Api.putWalletPermissionMatrix(walletId, entries);

  Future<String> getContacts() => Api.getContacts();
  Future<String> getTransactions() => Api.getTransactions();
  Future<String?> getContact(String id) => Api.getContact(id);
  Future<String?> getTransaction(String id) => Api.getTransaction(id);
  Future<String> createContact({
    required String name,
    String? username,
    String? phone,
    String? email,
    String? notes,
  }) =>
      Api.createContact(
          name: name,
          username: username,
          phone: phone,
          email: email,
          notes: notes);
  Future<void> updateContact({
    required String id,
    required String name,
    String? username,
    String? phone,
    String? email,
    String? notes,
  }) =>
      Api.updateContact(
          id: id,
          name: name,
          username: username,
          phone: phone,
          email: email,
          notes: notes);
  Future<void> deleteContact(String contactId) =>
      Api.deleteContact(contactId);
  Future<String> createTransaction({
    required String contactId,
    required String type,
    required String direction,
    required int amount,
    required String currency,
    String? description,
    required String transactionDate,
    String? dueDate,
  }) =>
      Api.createTransaction(
          contactId: contactId,
          type: type,
          direction: direction,
          amount: amount,
          currency: currency,
          description: description,
          transactionDate: transactionDate,
          dueDate: dueDate);
  Future<void> updateTransaction({
    required String id,
    required String contactId,
    required String type,
    required String direction,
    required int amount,
    required String currency,
    String? description,
    required String transactionDate,
    String? dueDate,
  }) =>
      Api.updateTransaction(
          id: id,
          contactId: contactId,
          type: type,
          direction: direction,
          amount: amount,
          currency: currency,
          description: description,
          transactionDate: transactionDate,
          dueDate: dueDate);
  Future<void> deleteTransaction(String transactionId) =>
      Api.deleteTransaction(transactionId);
  Future<void> undoContactAction(String contactId) =>
      Api.undoContactAction(contactId);
  Future<void> undoTransactionAction(String transactionId) =>
      Api.undoTransactionAction(transactionId);
  Future<void> bulkDeleteContacts(List<String> ids) =>
      Api.bulkDeleteContacts(ids);
  Future<void> bulkDeleteTransactions(List<String> ids) =>
      Api.bulkDeleteTransactions(ids);

  Future<String> getEvents() => Api.getEvents();
  Future<void> manualSync() => Api.manualSync();
  Future<void> connectRealtime() => AppConnectionState.connectRealtime();
  Future<void> refreshConnectionAndSync() async {
    await AppConnectionState.connectRealtime();
    await Api.manualSync();
  }

  Future<Set<String>> getMyPermissionActions(String walletId) async {
    final s = await Api.getMyPermissions(walletId);
    final map = jsonDecode(s) as Map<String, dynamic>?;
    final list = map?['actions'] as List<dynamic>? ?? const [];
    return list.whereType<String>().toSet();
  }

  Future<bool> isBackendConfigured() => Prefs.isBackendConfigured();
  Future<String> getBackendHost() => Prefs.getBackendHost();
  Future<int> getBackendPort() => Prefs.getBackendPort();
  Future<void> setBackendConfig(String host, int port) async {
    await Prefs.setBackendConfig(host, port);
    await Api.setBackendConfig(host, port);
  }

  ConnectionStateValue get connectionState => AppConnectionState.value;
  ValueNotifier<int> get connectionStateRevision => AppConnectionState.revision;
  Future<bool> getDarkMode() => Api.getDarkMode();
  Future<void> setDarkMode(bool enabled) => Api.setDarkMode(enabled);
  bool isPermissionDeniedError(dynamic e) => Api.isPermissionDeniedError(e);
  String? get initError => Bootstrap.initError;
}

final apiProvider = Provider<AppApi>((ref) => AppApi._instance);
