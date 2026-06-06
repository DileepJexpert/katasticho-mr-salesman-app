import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../shared/field_widgets.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  bool _checking = false;
  bool? _backendReachable;
  String? _lastChecked;

  Future<void> _checkConnection() async {
    setState(() => _checking = true);
    try {
      final session = ref.read(authControllerProvider).session;
      if (session == null || session.isDemo) {
        setState(() => _backendReachable = false);
        return;
      }
      await ref.read(apiClientProvider).getMe();
      setState(() {
        _backendReachable = true;
        _lastChecked = TimeOfDay.now().format(context);
      });
    } catch (_) {
      setState(() {
        _backendReachable = false;
        _lastChecked = TimeOfDay.now().format(context);
      });
    } finally {
      setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(authControllerProvider).session;

    final statusColor = _backendReachable == null
        ? Colors.grey
        : _backendReachable!
        ? Colors.green
        : Colors.red;
    final statusLabel = _backendReachable == null
        ? 'Not checked'
        : _backendReachable!
        ? 'Connected'
        : 'Unreachable';

    return PageScaffold(
      title: 'Sync',
      subtitle: 'Check backend connectivity and session status.',
      children: [
        // Connection status card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Backend: $statusLabel',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                if (_lastChecked != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Last checked: $_lastChecked',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _checking ? null : _checkConnection,
                  icon: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_find, size: 18),
                  label: Text(_checking ? 'Checking…' : 'Check Connection'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Session info
        if (session != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Session',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _InfoRow(label: 'Name', value: session.fullName),
                  _InfoRow(label: 'Role', value: session.role),
                  _InfoRow(label: 'Org', value: session.orgName),
                  _InfoRow(
                    label: 'Industry',
                    value: session.industry.isNotEmpty ? session.industry : '—',
                  ),
                  _InfoRow(
                    label: 'Mode',
                    value: session.isDemo ? 'Demo' : 'Live',
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),

        // Note about offline
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'This app currently requires an active connection. Offline sync (queue-based) will be added in a future release.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
