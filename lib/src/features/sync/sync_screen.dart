import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
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
    final session = ref.watch(authControllerProvider).session;

    final statusColor = _backendReachable == null
        ? FieldUi.muted
        : _backendReachable!
        ? Colors.green
        : Colors.red;
    final statusLabel = _backendReachable == null
        ? 'Not checked'
        : _backendReachable!
        ? 'Connected'
        : 'Unreachable';

    final pendingText = _pendingActions.isEmpty
        ? 'Queue empty'
        : '${_pendingActions.length} pending';
    final statusLineParts = <String>[
      pendingText,
      'Backend $statusLabel',
      if (_lastChecked != null) 'Checked $_lastChecked',
      if (_lastSyncResult != null) 'Last sync: $_lastSyncResult',
    ];

    return PageScaffold(
      title: 'Sync',
      subtitle: 'Backend connectivity and offline action queue.',
      children: [
        // Compact status header.
        StatusStrip(
          icon: _pendingActions.isEmpty
              ? Icons.cloud_done
              : Icons.cloud_upload,
          color: statusColor,
          text: statusLineParts.join(' · '),
          action: TextButton.icon(
            onPressed: _checking ? null : _checkConnection,
            icon: _checking
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find, size: 16),
            label: Text(_checking ? 'Checking…' : 'Check'),
          ),
        ),
        const SizedBox(height: 12),

        // Single primary action.
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
          label: Text(_syncing ? 'Syncing…' : 'Sync now'),
        ),
        const SizedBox(height: 6),
        Text(
          'Pending actions sync automatically every 30 seconds when the '
          'backend is reachable.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: FieldUi.muted),
        ),

        // Pending-queue items as flat rows.
        const SectionLabel('Pending actions'),
        if (_pendingActions.isEmpty)
          _EmptyHint(
            icon: Icons.cloud_done,
            text: 'Nothing queued — everything is synced.',
          )
        else
          FlatList(
            children: [
              for (var i = 0; i < _pendingActions.length; i++)
                FieldRow(
                  divider: i != _pendingActions.length - 1,
                  leading: Icon(
                    _actionIcon(_pendingActions[i].type),
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: _actionLabel(_pendingActions[i].type),
                  subtitle: _pendingActions[i].retryCount > 0
                      ? 'Queued ${_formatCreatedAt(_pendingActions[i].createdAt)} · '
                            '${_pendingActions[i].retryCount} failed '
                            '${_pendingActions[i].retryCount == 1 ? 'attempt' : 'attempts'}'
                      : 'Queued ${_formatCreatedAt(_pendingActions[i].createdAt)}',
                  trailing: IconButton(
                    tooltip: 'Discard',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _deleteAction(_pendingActions[i]),
                  ),
                ),
            ],
          ),

        // Session info as flat rows.
        if (session != null) ...[
          const SectionLabel('Session'),
          FlatList(
            children: [
              _SessionRow(label: 'Name', value: session.fullName),
              _SessionRow(label: 'Role', value: session.role),
              _SessionRow(label: 'Org', value: session.orgName),
              _SessionRow(
                label: 'Industry',
                value: session.industry.isNotEmpty ? session.industry : '—',
              ),
              _SessionRow(
                label: 'Mode',
                value: session.isDemo ? 'Demo' : 'Live',
                divider: false,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.label,
    required this.value,
    this.divider = true,
  });
  final String label;
  final String value;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    return FieldRow(
      dense: true,
      divider: divider,
      title: value,
      trailing: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: FieldUi.muted),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, size: 32, color: FieldUi.muted),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: FieldUi.muted),
          ),
        ],
      ),
    );
  }
}
