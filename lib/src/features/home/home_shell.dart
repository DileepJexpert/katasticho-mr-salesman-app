import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../dashboard/today_dashboard_screen.dart';
import '../mr/dcr_screen.dart';
import '../mr/rcpa_screen.dart';
import '../mr/tour_plan_screen.dart';
import '../orders/orders_screen.dart';
import '../parties/parties_screen.dart';
import '../sync/sync_screen.dart';
import '../visits/visits_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  final _pages = const [
    VisitsScreen(),
    OrdersScreen(),
    PartiesScreen(),
    TodayDashboardScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).session;
    final isPharma = session?.isPharma == true;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFE6F4F1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF0B6B5E).withValues(alpha: 0.2)),
              ),
              child: const Center(
                child: Text(
                  'K',
                  style: TextStyle(
                    color: Color(0xFF0B6B5E),
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Katasticho Field',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${session?.fullName ?? 'Field Rep'} · ${session?.orgName ?? 'Moonford Pharma'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (isPharma)
            IconButton(
              tooltip: 'Prescription Audits (RCPA)',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RcpaScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.analytics_outlined, size: 22),
            ),
          IconButton(
            tooltip: isPharma ? 'Tour Plan' : 'Route Plan',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const TourPlanScreen(),
                ),
              );
            },
            icon: const Icon(Icons.calendar_month_outlined, size: 22),
          ),
          IconButton(
            tooltip: 'Daily Call Report (DCR)',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DcrScreen(),
                ),
              );
            },
            icon: const Icon(Icons.assignment_outlined, size: 22),
          ),
          IconButton(
            tooltip: 'Sync Offline Records',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Offline Sync')),
                    body: const SyncScreen(),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.sync, size: 22),
          ),
          IconButton(
            tooltip: 'Sign Out',
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout, size: 22),
          ),
        ],
      ),
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.alt_route_outlined),
            selectedIcon: Icon(Icons.alt_route, color: Color(0xFF0B6B5E)),
            label: 'My Route',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon: Icon(Icons.shopping_bag, color: Color(0xFF0B6B5E)),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront, color: Color(0xFF0B6B5E)),
            label: 'Parties 360',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard, color: Color(0xFF0B6B5E)),
            label: 'Workspace',
          ),
        ],
      ),
    );
  }
}
