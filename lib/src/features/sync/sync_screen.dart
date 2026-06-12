import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/offline_queue.dart';
import '../../core/storage/offline_queue_provider.dart';
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

  bool _syncing = false;
  List<OfflineAction> _pendingActions = [];
  String? _lastSyncResult;
  Timer? _autoSyncTimer;

  @override
  void initState() {
    super.initState();
    _refreshQueue();
    // Every 30s: if backend reachable and actions pending, auto-process.
    _autoSyncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _autoSync(),
    );
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshQueue() async {
    final items = await ref.read(offlineQueueProvider).items;
    if (mounted) setState(() => _pendingActions = items);
  }

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
      if (mounted) setState(() => _checking = false);
    }
  }

  /// Periodic auto-sync: silently verifies connectivity, then drains the
  /// queue if anything is pending.
  Future<void> _autoSync() async {
    if (!mounted || _syncing) return;
    final session = ref.read(authControllerProvider).session;
    if (session == null || session.isDemo) return;

    final queue = ref.read(offlineQueueProvider);
    if (await queue.pendingCount == 0) {
      await _refreshQueue();
      return;
    }

    // Verify connectivity first so offline timer ticks don't burn retries.
    try {
      await ref.read(apiClientProvider).getMe();
      if (mounted) setState(() => _backendReachable = true);
    } catch (_) {
      if (mounted) setState(() => _backendReachable = false);
      return;
    }

    await _processQueue(showSnack: false);
  }

  Future<void> _processQueue({bool showSnack = true}) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final result = await ref
          .read(offlineQueueProvider)
          .processQueue(ref.read(apiClientProvider));
      final summary =
          '${result.synced} synced'
          '${result.failed > 0 ? ', ${result.failed} failed' : ''}'
          '${result.dropped > 0 ? ', ${result.dropped} dropped' : ''}';
      if (mounted) {
        setState(() => _lastSyncResult = summary);
        if (showSnack) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sync complete: $summary'),
              backgroundColor: result.failed == 0 && result.dropped == 0
                  ? Colors.green
                  : Colors.orange,
            ),
          );
        }
      }
    } catch (_) {
      if (mounted && showSnack) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sync failed')));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
      await _refreshQueue();
    }
  }

  Future<void> _deleteAction(OfflineAction action) async {
    await ref.read(offlineQueueProvider).remove(action.id);
    await _refreshQueue();
  }

  String _actionLabel(String type) {
    return switch (type) {
      'CHECK_IN' => 'Check In',
      'CHECK_OUT' => 'Check Out',
      'RECORD_ORDER' => 'Record Order',
      'RECORD_COLLECTION' => 'Record Collection',
      'EXPENSE' => 'Expense',
      _ => type,
    };
  }

  IconData _actionIcon(String type) {
    return switch (type) {
      'CHECK_IN' => Icons.location_on,
      'CHECK_OUT' => Icons.logout,
      'RECORD_ORDER' => Icons.shopping_cart,
      'RECORD_COLLECTION' => Icons.payments,
      'EXPENSE' => Icons.receipt_long,
      _ => Icons.pending_actions,
    };
  }

  String _formatCreatedAt(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final local = parsed.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month} $h:$m';
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
      subtitle: 'Backend connectivity and offline action queue.',
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

        // Offline queue card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.cloud_upload,
                      color: _pendingActions.isEmpty
                          ? Colors.green
                          : Colors.orange,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _pendingActions.isEmpty
                            ? 'Offline queue: empty'
                            : 'Offline queue: ${_pendingActions.length} pending',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_lastSyncResult != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Last sync: $_lastSyncResult',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  'Pending actions sync automatically every 30 seconds when '
                  'the backend is reachable.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: (_syncing || _pendingActions.isEmpty)
                      ? null
                      : _processQueue,
                  icon: _syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync, size: 18),
                  label: Text(_syncing ? 'Syncing…' : 'Sync Now'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Pending actions list
        if (_pendingActions.isNotEmpty) ...[
          Text(
            'Pending Actions',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          ..._pendingActions.map(
            (action) => Card(
              child: ListTile(
                dense: true,
                leading: Icon(
                  _actionIcon(action.type),
                  color: theme.colorScheme.primary,
                ),
                title: Text(
                  _actionLabel(action.type),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  action.retryCount > 0
                      ? 'Queued ${_formatCreatedAt(action.createdAt)} · '
                            '${action.retryCount} failed '
                            '${action.retryCount == 1 ? 'attempt' : 'attempts'}'
                      : 'Queued ${_formatCreatedAt(action.createdAt)}',
                ),
                trailing: IconButton(
                  tooltip: 'Discard',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _deleteAction(action),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

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
