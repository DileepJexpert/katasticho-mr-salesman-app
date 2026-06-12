import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../collections/collections_screen.dart';
import '../dashboard/today_dashboard_screen.dart';
import '../dayclose/day_close_screen.dart';
import '../expenses/expenses_screen.dart';
import '../mr/dcr_screen.dart';
import '../mr/tour_plan_screen.dart';
import '../orders/orders_screen.dart';
import '../parties/parties_screen.dart';
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
    OrdersScreen(),
    CollectionsScreen(),
    ExpensesScreen(),
    DayCloseScreen(),
    VanStockScreen(),
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
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.route), label: 'Visits'),
          NavigationDestination(icon: Icon(Icons.storefront), label: 'Parties'),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag),
            label: 'Orders',
          ),
          NavigationDestination(icon: Icon(Icons.payments), label: 'Collect'),
          NavigationDestination(
            icon: Icon(Icons.receipt_long),
            label: 'Expense',
          ),
          NavigationDestination(
            icon: Icon(Icons.nightlight_round),
            label: 'Day Close',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_shipping),
            label: 'Van',
          ),
        ],
      ),
    );
  }
}
