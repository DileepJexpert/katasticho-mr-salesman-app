import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../field/field_models.dart';

class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: FieldUi.muted),
          ),
        ],
        const SizedBox(height: 14),
        ...children,
      ],
    );
  }
}

// ── Flat / compact primitives ────────────────────────────────────────────────

/// A small uppercase section label for flat sections (no card).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: FieldUi.muted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// One metric in a [MetricStrip].
class MetricItem {
  const MetricItem(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;
}

/// A single bordered strip of compact KPIs separated by vertical dividers —
/// replaces a column/grid of metric cards.
class MetricStrip extends StatelessWidget {
  const MetricStrip({super.key, required this.items});
  final List<MetricItem> items;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      children.add(Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                it.value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: it.color ?? FieldUi.ink,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                it.label,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: FieldUi.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ));
      if (i != items.length - 1) {
        children.add(const SizedBox(
          height: 38,
          child: VerticalDivider(width: 1),
        ));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(FieldUi.radius),
        border: Border.all(color: FieldUi.hairline),
      ),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: children),
      ),
    );
  }
}

/// A dense, flat list row with an optional bottom divider — for timeline/list
/// screens instead of one card per item.
class FieldRow extends StatelessWidget {
  const FieldRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.divider = true,
    this.dense = false,
  });

  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final row = InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: dense ? 8 : 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: FieldUi.muted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
    if (!divider) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [row, const Divider(height: 1)],
    );
  }
}

/// A thin status/action strip (e.g. attendance) — tinted, single line + action.
class StatusStrip extends StatelessWidget {
  const StatusStrip({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
    this.action,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(FieldUi.radius),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// A flat, bordered container that wraps a list of [FieldRow]s as one section.
class FlatList extends StatelessWidget {
  const FlatList({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(FieldUi.radius),
        border: Border.all(color: FieldUi.hairline),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// Flat row variant of [PartyCard] for contact lists.
class PartyRow extends StatelessWidget {
  const PartyRow({super.key, required this.party, this.trailing, this.onTap});
  final FieldParty party;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FieldRow(
      onTap: onTap,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: _partyColor(party.type).withValues(alpha: 0.14),
        foregroundColor: _partyColor(party.type),
        child: Icon(_partyIcon(party.type), size: 18),
      ),
      title: party.name,
      subtitle: '${party.area} · ${_partyLabel(party.type)} · ${party.lastVisitText}',
      trailing: trailing ?? const Icon(Icons.chevron_right, color: FieldUi.muted),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PartyCard extends StatelessWidget {
  const PartyCard({super.key, required this.party, this.trailing});

  final FieldParty party;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: _partyColor(party.type).withValues(alpha: 0.14),
              foregroundColor: _partyColor(party.type),
              child: Icon(_partyIcon(party.type)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    party.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text('${party.area} · ${_partyLabel(party.type)}'),
                  const SizedBox(height: 4),
                  Text(
                    '${party.priority} · Last visit ${party.lastVisitText}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            trailing ?? const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

String partyLabel(PartyType type) => _partyLabel(type);

String _partyLabel(PartyType type) {
  return switch (type) {
    PartyType.doctor => 'Doctor',
    PartyType.hospital => 'Hospital',
    PartyType.clinic => 'Clinic',
    PartyType.chemist => 'Chemist',
    PartyType.retailer => 'Retailer',
    PartyType.distributor => 'Distributor',
    PartyType.stockist => 'Stockist',
  };
}

IconData _partyIcon(PartyType type) {
  return switch (type) {
    PartyType.doctor => Icons.medical_services,
    PartyType.hospital => Icons.local_hospital,
    PartyType.clinic => Icons.health_and_safety,
    PartyType.chemist => Icons.local_pharmacy,
    PartyType.retailer => Icons.storefront,
    PartyType.distributor => Icons.warehouse,
    PartyType.stockist => Icons.inventory_2,
  };
}

Color _partyColor(PartyType type) {
  return switch (type) {
    PartyType.doctor => const Color(0xFF2563EB),
    PartyType.hospital => const Color(0xFFDC2626),
    PartyType.clinic => const Color(0xFF7C3AED),
    PartyType.chemist => const Color(0xFF059669),
    PartyType.retailer => const Color(0xFFF59E0B),
    PartyType.distributor => const Color(0xFF0891B2),
    PartyType.stockist => const Color(0xFF475569),
  };
}
