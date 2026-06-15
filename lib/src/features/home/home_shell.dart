import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../auth/auth_controller.dart';
import '../collections/collections_screen.dart';
import '../dashboard/today_dashboard_screen.dart';
import '../dayclose/day_close_screen.dart';
import '../expenses/expenses_screen.dart';
import '../mr/dcr_screen.dart';
import '../mr/tour_plan_screen.dart';
import '../orders/orders_screen.dart';
import '../parties/parties_screen.dart';
import '../shared/field_widgets.dart';
import '../sync/sync_screen.dart';
import '../van/van_stock_screen.dart';
import '../visits/visits_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  final _pages = const [
    TodayDashboardScreen(),
    VisitsScreen(),
    PartiesScreen(),
    _MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).session;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Katasticho Field'),
            Text(
              '${session?.fullName ?? 'Field user'} · ${session?.role ?? ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Tour Plan',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TourPlanScreen(),
                ),
              );
            },
            icon: const Icon(Icons.calendar_month),
          ),
          IconButton(
            tooltip: 'Daily Report',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DcrScreen(),
                ),
              );
            },
            icon: const Icon(Icons.assignment_outlined),
          ),
          IconButton(
            tooltip: 'Sync',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Sync')),
                    body: const SyncScreen(),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.route), label: 'Visits'),
          NavigationDestination(icon: Icon(Icons.storefront), label: 'Parties'),
          NavigationDestination(icon: Icon(Icons.apps), label: 'More'),
        ],
      ),
    );
  }
}

/// A single destination on the "More" tab — links to a feature screen that no
/// longer has its own bottom-nav slot.
class _MoreLink {
  const _MoreLink({
    required this.icon,
    required this.label,
    required this.builder,
  });

  final IconData icon;
  final String label;
  final WidgetBuilder builder;
}

/// The "More" tab: a flat, scrollable list of everything displaced from the
/// bottom navigation. Tapping an entry pushes that feature's existing screen
/// wrapped in a Scaffold/AppBar.
class _MoreScreen extends StatelessWidget {
  const _MoreScreen();

  @override
  Widget build(BuildContext context) {
    const operations = <_MoreLink>[
      _MoreLink(
        icon: Icons.shopping_bag,
        label: 'Orders',
        builder: _ordersBuilder,
      ),
      _MoreLink(
        icon: Icons.payments,
        label: 'Collections',
        builder: _collectionsBuilder,
      ),
      _MoreLink(
        icon: Icons.receipt_long,
        label: 'Expenses',
        builder: _expensesBuilder,
      ),
      _MoreLink(
        icon: Icons.local_shipping,
        label: 'Van Stock',
        builder: _vanBuilder,
      ),
      _MoreLink(
        icon: Icons.nightlight_round,
        label: 'Day Close',
        builder: _dayCloseBuilder,
      ),
    ];

    const reporting = <_MoreLink>[
      _MoreLink(
        icon: Icons.calendar_month,
        label: 'Tour Plan',
        builder: _tourPlanBuilder,
      ),
      _MoreLink(
        icon: Icons.assignment_outlined,
        label: 'Daily Report (DCR)',
        builder: _dcrBuilder,
      ),
      _MoreLink(
        icon: Icons.sync,
        label: 'Sync',
        builder: _syncBuilder,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        const SectionLabel('Operations'),
        FlatList(
          children: [
            for (var i = 0; i < operations.length; i++)
              _moreRow(context, operations[i], last: i == operations.length - 1),
          ],
        ),
        const SectionLabel('Reporting & Sync'),
        FlatList(
          children: [
            for (var i = 0; i < reporting.length; i++)
              _moreRow(context, reporting[i], last: i == reporting.length - 1),
          ],
        ),
      ],
    );
  }

  Widget _moreRow(BuildContext context, _MoreLink link, {required bool last}) {
    return FieldRow(
      divider: !last,
      leading: Icon(link.icon, color: FieldUi.muted),
      title: link.label,
      trailing: const Icon(Icons.chevron_right, color: FieldUi.muted),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: link.builder),
      ),
    );
  }
}

// Top-level builders so they can live in a `const` [_MoreLink] list. Each wraps
// the feature's existing screen in a Scaffold/AppBar for back navigation.
Widget _ordersBuilder(BuildContext context) => const _MorePage(
      title: 'Orders',
      child: OrdersScreen(),
    );
Widget _collectionsBuilder(BuildContext context) => const _MorePage(
      title: 'Collections',
      child: CollectionsScreen(),
    );
Widget _expensesBuilder(BuildContext context) => const _MorePage(
      title: 'Expenses',
      child: ExpensesScreen(),
    );
Widget _vanBuilder(BuildContext context) => const _MorePage(
      title: 'Van Stock',
      child: VanStockScreen(),
    );
Widget _dayCloseBuilder(BuildContext context) => const _MorePage(
      title: 'Day Close',
      child: DayCloseScreen(),
    );
Widget _tourPlanBuilder(BuildContext context) => const TourPlanScreen();
Widget _dcrBuilder(BuildContext context) => const DcrScreen();
Widget _syncBuilder(BuildContext context) => const _MorePage(
      title: 'Sync',
      child: SyncScreen(),
    );

/// Wraps a tab body screen (which has no Scaffold/AppBar of its own) in a
/// Scaffold + AppBar so it works as a pushed route.
class _MorePage extends StatelessWidget {
  const _MorePage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
    );
  }
}
