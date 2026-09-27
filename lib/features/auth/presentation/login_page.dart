import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instrument_pos/core/database/workstation_config.dart';
import 'package:instrument_pos/features/auth/presentation/session_provider.dart';
import 'package:instrument_pos/features/settings/presentation/network_settings_card.dart';
import 'package:instrument_pos/features/settings/presentation/store_settings_providers.dart';
import 'package:instrument_pos/features/settings/presentation/sync_status_indicator.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref
        .read(sessionProvider.notifier)
        .signIn(
          username: _usernameController.text,
          password: _passwordController.text,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  void _showNetworkSettingsDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Row(
                  children: [
                    const Text(
                      'Station Network Configuration',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(16),
                  child: NetworkSettingsCard(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = ref.watch(storeInfoControllerProvider);
    final config = WorkstationConfig.current;

    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.music_note,
                        size: 44,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        store.name,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${store.address.isEmpty ? '' : '${store.address} · '}'
                        'Sign in to open the register',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Station Network Status Pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: config.isClient
                              ? const Color(0xFFEFF6FF)
                              : (config.isHost
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: config.isClient
                                ? const Color(0xFF93C5FD)
                                : (config.isHost
                                    ? const Color(0xFF86EFAC)
                                    : const Color(0xFFCBD5E1)),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              config.isClient
                                  ? Icons.lan_rounded
                                  : (config.isHost
                                      ? Icons.hub_rounded
                                      : Icons.computer_rounded),
                              size: 14,
                              color: config.isClient
                                  ? const Color(0xFF2563EB)
                                  : (config.isHost
                                      ? const Color(0xFF15803D)
                                      : const Color(0xFF64748B)),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                config.isClient
                                    ? 'Client Station • Host: ${config.hostAddress}:${config.hostPort}'
                                    : (config.isHost
                                        ? 'Host Server • Port ${config.hostPort}'
                                        : 'Standalone Register (Local DB)'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: config.isClient
                                      ? const Color(0xFF1E40AF)
                                      : (config.isHost
                                          ? const Color(0xFF15803D)
                                          : const Color(0xFF475569)),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const SyncStatusIndicator(compact: true),
                      const SizedBox(height: 16),

                      TextField(
                        controller: _usernameController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        onSubmitted: (_) => _signIn(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            tooltip: _obscurePassword ? 'Show Password' : 'Hide Password',
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _busy ? null : _signIn,
                        child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Floating Quick Network Config Button on Login Page
          Positioned(
            bottom: 16,
            right: 16,
            child: TextButton.icon(
              onPressed: _showNetworkSettingsDialog,
              icon: const Icon(Icons.settings_ethernet_rounded, size: 16),
              label: const Text('Network Settings', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}
