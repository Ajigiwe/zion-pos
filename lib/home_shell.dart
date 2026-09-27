import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/features/auth/domain/roles.dart';
import 'package:instrument_pos/features/settings/presentation/store_settings_providers.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/dashboard/presentation/dashboard_page.dart';
import 'package:instrument_pos/features/dashboard/presentation/low_stock_badge.dart';
import 'package:instrument_pos/features/auth/presentation/user_management_page.dart';
import 'package:instrument_pos/features/imports/presentation/imports_page.dart';
import 'package:instrument_pos/features/inventory/presentation/inventory_page.dart';
import 'package:instrument_pos/features/products/presentation/product_edit_page.dart';
import 'package:instrument_pos/features/refunds/presentation/refunds_page.dart';
import 'package:instrument_pos/features/sales/presentation/sales_page.dart';
import 'package:instrument_pos/features/products/presentation/products_page.dart';
import 'package:instrument_pos/features/reports/presentation/reports_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// The app opens on the till — that is the page staff use all day. The
  /// Dashboard entry stays at the top of the sidebar.
  static const int _dashboardSectionIndex = 0;
  static const int _salesSectionIndex = 3;
  int _selectedIndex = _salesSectionIndex;

  static const _sections = [
    _Section(icon: Icons.space_dashboard_outlined, label: 'Dashboard'),
    _Section(icon: Icons.inventory_2_outlined, label: 'Products'),
    _Section(icon: Icons.warehouse_outlined, label: 'Inventory'),
    _Section(icon: Icons.point_of_sale_outlined, label: 'Sales'),
    _Section(icon: Icons.receipt_long_outlined, label: 'Refunds'),
    _Section(icon: Icons.upload_file_outlined, label: 'Imports'),
    _Section(icon: Icons.groups_outlined, label: 'Customers'),
    _Section(icon: Icons.assessment_outlined, label: 'Reports'),
    _Section(icon: Icons.settings_outlined, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 216,
            child: Material(
              color: colorScheme.surfaceContainerLow,
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.music_note, color: colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Consumer(
                              builder: (context, ref, _) => Text(
                                ref.watch(storeInfoControllerProvider).name,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _sections.length,
                        itemBuilder: (context, index) {
                          final section = _sections[index];
                          final selected = index == _selectedIndex;
                          return ListTile(
                            selected: selected,
                            selectedTileColor: colorScheme.secondaryContainer,
                            leading: Icon(section.icon),
                            title: Text(section.label),
                            // Live low-stock count on the Dashboard entry.
                            trailing: index == _dashboardSectionIndex
                                ? const LowStockBadge()
                                : null,
                            shape: const RoundedRectangleBorder(),
                            onTap: () => setState(() => _selectedIndex = index),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Consumer(
                      builder: (context, ref, _) {
                        final user = ref.watch(currentUserProvider);
                        final role = user == null
                            ? null
                            : Role.fromStorage(user.role);
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.account_circle_outlined),
                          title: Text(
                            user?.displayName ?? 'Signed out',
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: role == null ? null : Text(role.label),
                          trailing: user == null
                              ? null
                              : IconButton(
                                  tooltip: 'Sign out',
                                  icon: const Icon(Icons.logout),
                                  onPressed: () => ref
                                      .read(sessionProvider.notifier)
                                      .signOut(),
                                ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: SafeArea(
              child: switch (_selectedIndex) {
                0 => DashboardPage(
                  onOpenInventory: () => setState(() => _selectedIndex = 2),
                ),
                1 => const ProductsPage(),
                2 => const InventoryPage(),
                3 => const SalesPage(),
                4 => const RefundsPage(),
                5 => const ImportsPage(),
                6 => const _PlaceholderPage(
                  icon: Icons.groups_outlined,
                  label: 'Customers',
                ),
                7 => const ReportsPage(),
                8 => const SettingsPage(),
                _ => const _PlaceholderPage(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                ),
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _selectedIndex == 1
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ProductEditPage(productId: null),
                ),
              ),
              icon: const Icon(Icons.add),
              label: const Text('New Product'),
            )
          : null,
    );
  }
}

class _Section {
  const _Section({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(label, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Coming in a later phase',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
