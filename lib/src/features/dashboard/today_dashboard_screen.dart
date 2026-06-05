import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../field/field_sample_data.dart';
import '../shared/field_widgets.dart';

class TodayDashboardScreen extends ConsumerWidget {
  const TodayDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).session;

    return PageScaffold(
      title: 'Today',
      subtitle: session?.isDemo == true
          ? 'Demo route for manufacturer MR + distributor salesman workflows.'
          : '${session?.orgName ?? 'Organisation'} field workspace.',
      children: [
        const Row(
          children: [
            Expanded(
              child: MetricTile(
                icon: Icons.route,
                label: 'Planned visits',
                value: '3',
                tint: Color(0xFF2563EB),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: MetricTile(
                icon: Icons.payments,
                label: 'Due to collect',
                value: '₹90.9k',
                tint: Color(0xFF059669),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            Expanded(
              child: MetricTile(
                icon: Icons.shopping_bag,
                label: 'Orders',
                value: '0',
                tint: Color(0xFFF59E0B),
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: MetricTile(
                icon: Icons.sync,
                label: 'Sync queue',
                value: '3',
                tint: Color(0xFF7C3AED),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Next visits',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ...sampleVisits.map(
          (visit) => Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          visit.party.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(visit.window),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(visit.objective),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Chip(
                        avatar: const Icon(Icons.place, size: 16),
                        label: Text(visit.party.area),
                      ),
                      const SizedBox(width: 8),
                      ActionChip(
                        avatar: const Icon(Icons.flag, size: 16),
                        label: const Text('Check in'),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
