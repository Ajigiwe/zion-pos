import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/app_database.dart';
import 'package:instrument_pos/features/audit/presentation/audit_card.dart';
import 'package:instrument_pos/features/auth/data/auth_repository.dart';
import 'package:instrument_pos/features/auth/domain/roles.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/auth/presentation/user_providers.dart';
import 'package:instrument_pos/features/settings/presentation/database_backup_card.dart';
import 'package:instrument_pos/features/settings/presentation/low_stock_threshold_card.dart';
import 'package:instrument_pos/features/settings/presentation/printer_settings_card.dart';
import 'package:instrument_pos/features/settings/presentation/receipt_customization_card.dart';
import 'package:instrument_pos/features/settings/presentation/store_profile_card.dart';
import 'package:instrument_pos/features/settings/presentation/theme_settings_card.dart';
import 'package:instrument_pos/features/settings/presentation/network_settings_card.dart';

enum _SettingsCategory {
  all(label: 'All Settings', icon: Icons.grid_view_rounded),
  store(label: 'Store & Receipts', icon: Icons.storefront_outlined),
  printers(label: 'Printers & Hardware', icon: Icons.print_outlined),
  appearance(label: 'Appearance & Themes', icon: Icons.palette_outlined),
  network(label: 'Network & Registers', icon: Icons.lan_outlined),
  users(label: 'Users & Roles', icon: Icons.people_outline_rounded),
  inventory(label: 'Inventory & Backup', icon: Icons.inventory_2_outlined),
  audit(label: 'Audit Log', icon: Icons.security_outlined);

  const _SettingsCategory({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  _SettingsCategory _selectedCategory = _SettingsCategory.all;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final role = user == null ? null : Role.fromStorage(user.role);
    final canManage = role?.can(Permission.manageUsers) ?? false;
    final canConfigure = role?.can(Permission.systemConfig) ?? false;
    final theme = Theme.of(context);

    final categories = [
      _SettingsCategory.all,
      if (canConfigure) _SettingsCategory.store,
      _SettingsCategory.printers,
      if (canConfigure) _SettingsCategory.appearance,
      _SettingsCategory.network,
      _SettingsCategory.users,
      if (canConfigure) _SettingsCategory.inventory,
      if (canManage) _SettingsCategory.audit,
    ];

    final initialIndex = categories.indexOf(_selectedCategory).clamp(0, categories.length - 1);

    return DefaultTabController(
      key: ValueKey('settings_tabs_${categories.length}'),
      length: categories.length,
      initialIndex: initialIndex,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // Page Header
          _buildHeader(theme, role),
          const SizedBox(height: 14),

          // Category Tab Bar
          _buildTabBar(categories),
          const SizedBox(height: 16),

          // Content rendering based on category
          if (_selectedCategory == _SettingsCategory.all) ...[
            _MyAccountCard(user: user, role: role),
            const SizedBox(height: 16),
            _buildUsersCard(canManage, theme),
            if (canManage) ...[
              const SizedBox(height: 16),
              const AuditCard(),
            ],
            if (canConfigure) ...[
              const SizedBox(height: 16),
              const StoreProfileCard(),
            ],
            const SizedBox(height: 16),
            const PrinterSettingsCard(),
            const SizedBox(height: 16),
            const NetworkSettingsCard(),
            if (canConfigure) ...[
              const SizedBox(height: 16),
              const ThemeSettingsCard(),
              const SizedBox(height: 16),
              const ReceiptCustomizationCard(),
              const SizedBox(height: 16),
              const LowStockThresholdCard(),
              const SizedBox(height: 16),
              const DatabaseBackupCard(),
            ],
            const SizedBox(height: 16),
            const RolesReferenceCard(),
          ] else if (_selectedCategory == _SettingsCategory.store && canConfigure) ...[
            const StoreProfileCard(),
            const SizedBox(height: 16),
            const ReceiptCustomizationCard(),
          ] else if (_selectedCategory == _SettingsCategory.printers) ...[
            const PrinterSettingsCard(),
          ] else if (_selectedCategory == _SettingsCategory.appearance && canConfigure) ...[
            const ThemeSettingsCard(),
          ] else if (_selectedCategory == _SettingsCategory.network) ...[
            const NetworkSettingsCard(),
          ] else if (_selectedCategory == _SettingsCategory.users) ...[
            _MyAccountCard(user: user, role: role),
            const SizedBox(height: 16),
            _buildUsersCard(canManage, theme),
            const SizedBox(height: 16),
            const RolesReferenceCard(),
          ] else if (_selectedCategory == _SettingsCategory.inventory && canConfigure) ...[
            const LowStockThresholdCard(),
            const SizedBox(height: 16),
            const DatabaseBackupCard(),
          ] else if (_selectedCategory == _SettingsCategory.audit && canManage) ...[
            const AuditCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, Role? role) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Settings',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                    if (role != null) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F9FF),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFBAE6FD)),
                        ),
                        child: Text(
                          role.label,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0369A1),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Manage store identity, receipt layout, staff roles, stock thresholds and data backups.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(List<_SettingsCategory> categories) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.015),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFFCBD5E1).withOpacity(0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        labelColor: const Color(0xFF0284C7),
        unselectedLabelColor: const Color(0xFF64748B),
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        onTap: (index) {
          setState(() {
            _selectedCategory = categories[index];
          });
        },
        tabs: [
          for (final cat in categories)
            Tab(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(cat.icon, size: 17),
                    const SizedBox(width: 8),
                    Text(cat.label),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUsersCard(bool canManage, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.people_alt_outlined,
                    color: Color(0xFF0284C7),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Users & roles',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Create cashier, manager and owner accounts for this device (§31).',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                if (canManage)
                  FilledButton.icon(
                    onPressed: () => showAddUserDialog(context, ref),
                    icon: const Icon(Icons.person_add, size: 18),
                    label: const Text('Add user'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
              ],
            ),
            if (!canManage)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        size: 18,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Only owners and admins can manage users.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            canManage ? const _UserTable() : const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}

/// The signed-in user's own account summary + password change.
class _MyAccountCard extends StatelessWidget {
  const _MyAccountCard({required this.user, required this.role});

  final User? user;
  final Role? role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF38BDF8), Color(0xFF0284C7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  (user?.displayName.isNotEmpty ?? false)
                      ? user!.displayName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Signed in as ${user?.displayName ?? '—'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${user?.username ?? ''} · ${role?.label ?? '—'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: user == null
                  ? null
                  : () => showChangePasswordDialog(context, user!.id),
              icon: const Icon(Icons.key, size: 16),
              label: const Text('Change password'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF334155),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Static reference documenting every role and its permissions.
class RolesReferenceCard extends StatelessWidget {
  const RolesReferenceCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.badge_outlined,
                    color: Color(0xFF6366F1),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Roles & permissions',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'What each sign-in role can do on this device (§31).',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 12),
            for (final role in Role.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              role.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          Icon(
                            role == Role.owner || role == Role.admin
                                ? Icons.admin_panel_settings_outlined
                                : role == Role.cashier
                                ? Icons.point_of_sale
                                : Icons.badge_outlined,
                            size: 18,
                            color: const Color(0xFF64748B),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        role.description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final permission in Permission.values)
                            if (role.can(permission))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Text(
                                  permission.label,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF334155),
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Opens the password change dialog; the change is applied by the repository.
Future<void> showChangePasswordDialog(
  BuildContext context,
  String userId,
) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (context) => _ChangePasswordDialog(userId: userId),
  );
  if (changed == true && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Password changed.'),
          backgroundColor: Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog({required this.userId});

  final String userId;

  @override
  ConsumerState<_ChangePasswordDialog> createState() =>
      _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _currentController,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Enter your current password'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  helperText: 'At least 6 characters',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value ?? '').length < 6 ? 'At least 6 characters' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value != _newController.text
                    ? 'Passwords do not match'
                    : null,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
          child: Text(_saving ? 'Saving…' : 'Change password'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .changePassword(
            userId: widget.userId,
            currentPassword: _currentController.text,
            newPassword: _newController.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _UserTable extends ConsumerWidget {
  const _UserTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider);
    final currentUser = ref.watch(currentUserProvider);

    return users.when(
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text('Error: $error'),
      data: (items) {
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('No users yet.'),
          );
        }
        return Column(
          children: [
            for (final user in items)
              _UserRow(
                user: user,
                isSelf: user.id == currentUser?.id,
                onToggleActive: (active) =>
                    _toggleActive(context, ref, user, active),
              ),
          ],
        );
      },
    );
  }

  Future<void> _toggleActive(
    BuildContext context,
    WidgetRef ref,
    User user,
    bool active,
  ) async {
    final repo = ref.read(authRepositoryProvider);
    final currentUser = ref.read(currentUserProvider);
    String? error;
    if (user.id == currentUser?.id && !active) {
      error = 'You cannot disable your own account.';
    } else if (!active && user.role == 'OWNER') {
      final owners = await repo.countActiveOwners();
      if (owners <= 1) {
        error = 'You cannot disable the last active owner account.';
      }
    }
    if (error != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error)));
      }
      return;
    }
    await repo.setActive(
      user.id,
      active: active,
      actingUserId: currentUser?.id,
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    required this.isSelf,
    required this.onToggleActive,
  });

  final User user;
  final bool isSelf;
  final ValueChanged<bool> onToggleActive;

  @override
  Widget build(BuildContext context) {
    final role = Role.fromStorage(user.role);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF0284C7).withOpacity(0.12),
          foregroundColor: const Color(0xFF0284C7),
          child: Text(
            user.displayName.isEmpty ? '?' : user.displayName[0].toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        title: Text(
          user.displayName,
          style: user.isActive
              ? const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)
              : TextStyle(color: Theme.of(context).disabledColor, fontSize: 14),
        ),
        subtitle: Text(
          '@${user.username}${isSelf ? '  (you)' : ''}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                role.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF334155),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: user.isActive,
              activeColor: const Color(0xFF0284C7),
              onChanged: onToggleActive,
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the add-user dialog and creates the account on submit.
Future<void> showAddUserDialog(BuildContext context, WidgetRef ref) async {
  final created = await showDialog<bool>(
    context: context,
    builder: (context) => const _AddUserDialog(),
  );
  if (created == true && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('User created.'),
          backgroundColor: Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

class _AddUserDialog extends ConsumerStatefulWidget {
  const _AddUserDialog();

  @override
  ConsumerState<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends ConsumerState<_AddUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  Role _role = Role.cashier;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add user'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _usernameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Username *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Username is required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'Display name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Display name is required'
                      : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Role>(
                  initialValue: _role,
                  decoration: const InputDecoration(
                    labelText: 'Role *',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final role in Role.values)
                      DropdownMenuItem(value: role, child: Text(role.label)),
                  ],
                  onChanged: (value) =>
                      setState(() => _role = value ?? Role.cashier),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password *',
                    helperText: 'At least 6 characters',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final password = value ?? '';
                    if (password.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
          child: Text(_saving ? 'Creating…' : 'Create user'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .createUser(
            username: _usernameController.text,
            displayName: _displayNameController.text,
            role: _role.storageName,
            password: _passwordController.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
