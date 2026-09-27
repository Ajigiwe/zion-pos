import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/app_restart.dart';
import 'package:instrument_pos/core/database/lan_database_client.dart';
import 'package:instrument_pos/core/database/lan_database_server.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/settings/domain/network_settings.dart';
import 'package:instrument_pos/features/settings/presentation/network_settings_providers.dart';

class NetworkSettingsCard extends ConsumerStatefulWidget {
  const NetworkSettingsCard({super.key});

  @override
  ConsumerState<NetworkSettingsCard> createState() =>
      _NetworkSettingsCardState();
}

class _NetworkSettingsCardState extends ConsumerState<NetworkSettingsCard> {
  late TextEditingController _hostPortController;
  late TextEditingController _clientAddressController;
  late TextEditingController _clientPortController;
  late TextEditingController _pinController;

  bool _testingConnection = false;
  LanPingResult? _pingResult;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(networkSettingsControllerProvider);
    _hostPortController =
        TextEditingController(text: settings.hostPort.toString());
    _clientAddressController =
        TextEditingController(text: settings.remoteHostAddress);
    _clientPortController =
        TextEditingController(text: settings.remoteHostPort.toString());
    _pinController = TextEditingController(text: settings.securityPin);
  }

  @override
  void dispose() {
    _hostPortController.dispose();
    _clientAddressController.dispose();
    _clientPortController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _testPing() async {
    setState(() {
      _testingConnection = true;
      _pingResult = null;
    });

    final host = _clientAddressController.text.trim();
    final port = int.tryParse(_clientPortController.text.trim()) ?? 4242;

    final result = await LanDatabaseClient.testConnection(host, port);
    if (!mounted) return;

    setState(() {
      _testingConnection = false;
      _pingResult = result;
    });
  }

  void _saveHostConfig() {
    final user = ref.read(currentUserProvider);
    final port = int.tryParse(_hostPortController.text.trim()) ?? 4242;
    ref.read(networkSettingsControllerProvider.notifier).updateHostConfig(
          port: port,
          securityPin: _pinController.text.trim(),
          actingUserId: user?.id ?? '',
        );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Host station configuration updated & server restarted'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _saveClientConfig() async {
    final user = ref.read(currentUserProvider);
    final host = _clientAddressController.text.trim();
    final port = int.tryParse(_clientPortController.text.trim()) ?? 4242;

    setState(() => _testingConnection = true);
    final ping = await LanDatabaseClient.testConnection(host, port);
    if (!mounted) return;
    setState(() {
      _testingConnection = false;
      _pingResult = ping;
    });

    if (!ping.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot reach Host at $host:$port (${ping.errorMessage})'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
      return;
    }

    await ref.read(networkSettingsControllerProvider.notifier).updateClientConfig(
          hostAddress: host,
          port: port,
          securityPin: _pinController.text.trim(),
          actingUserId: user?.id ?? '',
        );

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 48),
        title: const Text('Connected to Host Station!'),
        content: Text(
          'This terminal is now linked to the Main Host at $host:$port (latency: ${ping.latencyMs}ms).\n\n'
          'The application will now open the Login screen so you can sign in with your store credentials on the shared database.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Proceed to Login'),
          ),
        ],
      ),
    );

    appRestartCount.value++;
  }

  @override
  Widget build(BuildContext context) {
    final networkSettings = ref.watch(networkSettingsControllerProvider);
    final localIpsAsync = ref.watch(localIpAddressesProvider);
    final server = ref.watch(lanDatabaseServerProvider);
    final user = ref.watch(currentUserProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.lan_rounded,
                    color: colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Multi-Register & LAN Database Sharing',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Share a single real-time database across multiple POS stations and back-office PCs over your local store network.',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 18),

            // Station Mode Header
            Text(
              'STATION ROLE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 10),

            // Mode Selector Cards
            Row(
              children: [
                Expanded(
                  child: _buildModeCard(
                    mode: NetworkStationMode.standalone,
                    title: 'Standalone',
                    subtitle: 'Single PC local database',
                    icon: Icons.computer_rounded,
                    isSelected: networkSettings.isStandalone,
                    onTap: () => ref
                        .read(networkSettingsControllerProvider.notifier)
                        .setMode(
                          NetworkStationMode.standalone,
                          actingUserId: user?.id ?? '',
                        ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildModeCard(
                    mode: NetworkStationMode.host,
                    title: 'Main Host',
                    subtitle: 'Hosts store database on LAN',
                    icon: Icons.hub_rounded,
                    isSelected: networkSettings.isHost,
                    onTap: () => ref
                        .read(networkSettingsControllerProvider.notifier)
                        .setMode(
                          NetworkStationMode.host,
                          actingUserId: user?.id ?? '',
                        ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildModeCard(
                    mode: NetworkStationMode.client,
                    title: 'Terminal Client',
                    subtitle: 'Connects to Main Host',
                    icon: Icons.point_of_sale_rounded,
                    isSelected: networkSettings.isClient,
                    onTap: () => ref
                        .read(networkSettingsControllerProvider.notifier)
                        .setMode(
                          NetworkStationMode.client,
                          actingUserId: user?.id ?? '',
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Mode Specific Configuration Panels
            if (networkSettings.isStandalone) ...[
              _buildStandalonePanel(isDark, colorScheme),
            ] else if (networkSettings.isHost) ...[
              _buildHostPanel(isDark, colorScheme, localIpsAsync, server),
            ] else if (networkSettings.isClient) ...[
              _buildClientPanel(isDark, colorScheme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required NetworkStationMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withOpacity(0.08)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? colorScheme.primary : const Color(0xFFE2E8F0),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? colorScheme.primary
                      : (isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B)),
                ),
                const Spacer(),
                if (isSelected)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? colorScheme.primary : null,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStandalonePanel(bool isDark, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: Color(0xFF0284C7),
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Standalone Local Database Active',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                SizedBox(height: 2),
                Text(
                  'All sales, inventory, and settings are saved locally on this machine with maximum performance.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostPanel(
    bool isDark,
    ColorScheme colorScheme,
    AsyncValue<List<String>> localIpsAsync,
    LanDatabaseServer server,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status & Connected Clients
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF86EFAC)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF16A34A),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'HOST SERVER RUNNING',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              ValueListenableBuilder<int>(
                valueListenable: server.activeClientsNotifier,
                builder: (context, count, _) {
                  return Text(
                    '$count Secondary Terminal${count == 1 ? '' : 's'} Connected',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // IP Addresses for Secondary Terminals
          Text(
            'Host LAN Connection Address (Enter this on Terminal PCs):',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 8),

          localIpsAsync.when(
            loading: () => const Text('Detecting local LAN IP addresses…'),
            error: (err, _) => Text('Error detecting IP: $err'),
            data: (ips) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ip in ips)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$ip:${_hostPortController.text}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          tooltip: 'Copy IP',
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: ip));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Copied $ip to clipboard'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Host Port & PIN Config
          Row(
            children: [
              SizedBox(
                width: 140,
                child: TextField(
                  controller: _hostPortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Server Port',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _pinController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Security PIN (Optional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _saveHostConfig,
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text('Update Host'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 16),

          // Connected Clients Section
          Row(
            children: [
              const Icon(Icons.devices_rounded, size: 18, color: Color(0xFF64748B)),
              const SizedBox(width: 8),
              const Text(
                'CONNECTED TERMINALS & WORKSTATIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Color(0xFF64748B),
                ),
              ),
              const Spacer(),
              ValueListenableBuilder<List<ConnectedClientSession>>(
                valueListenable: server.connectedClientsNotifier,
                builder: (context, clients, _) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: clients.isNotEmpty
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${clients.length} Online',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: clients.isNotEmpty
                            ? const Color(0xFF15803D)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          ValueListenableBuilder<List<ConnectedClientSession>>(
            valueListenable: server.connectedClientsNotifier,
            builder: (context, clients, _) {
              if (clients.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.device_hub_rounded,
                        size: 20,
                        color: isDark
                            ? const Color(0xFF64748B)
                            : const Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'No secondary terminals connected yet. When cashiers connect from other PCs, their stations will appear here in real time.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  for (final client in clients)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF0F172A)
                            : const Color(0xFFFFFFFF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.point_of_sale_rounded,
                              size: 18,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      client.stationName,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'ACTIVE',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF15803D),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'IP: ${client.remoteIp}  •  Connected ${client.connectedDurationString}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.link_off_rounded,
                              size: 18,
                              color: Color(0xFFDC2626),
                            ),
                            tooltip: 'Disconnect Terminal',
                            onPressed: () async {
                              await server.disconnectClient(client.id);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Disconnected ${client.stationName}',
                                    ),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildClientPanel(bool isDark, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Connect to Main Host Station',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Enter the IP address shown on your Main Host PC to sync all sales, stock, and catalog items in real time.',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 16),

          // IP, Port, PIN
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _clientAddressController,
                  decoration: const InputDecoration(
                    labelText: 'Host IP Address',
                    hintText: 'e.g. 192.168.1.15',
                    prefixIcon: Icon(Icons.computer_rounded),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 1,
                child: TextField(
                  controller: _clientPortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    hintText: '4242',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _pinController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Security PIN',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Test Connection & Save Action Row
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _testingConnection ? null : _testPing,
                icon: _testingConnection
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_find_rounded, size: 16),
                label: Text(
                  _testingConnection ? 'Testing…' : 'Test Connection',
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _saveClientConfig,
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Save & Connect'),
              ),
            ],
          ),

          if (_pingResult != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _pingResult!.success
                    ? const Color(0xFFF0FDF4)
                    : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _pingResult!.success
                      ? const Color(0xFFBBF7D0)
                      : const Color(0xFFFECACA),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _pingResult!.success
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    color: _pingResult!.success
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _pingResult!.success
                          ? 'Successfully reached Host Station (${_pingResult!.latencyMs}ms latency). Ready for multi-station sync.'
                          : 'Connection failed: ${_pingResult!.errorMessage}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _pingResult!.success
                            ? const Color(0xFF166534)
                            : const Color(0xFF991B1B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
