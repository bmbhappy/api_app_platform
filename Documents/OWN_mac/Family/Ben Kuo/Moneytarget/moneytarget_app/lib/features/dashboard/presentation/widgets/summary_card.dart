import 'package:flutter/material.dart';

enum SummaryCardLayout {
  list,
  grid,
}

class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.title,
    this.subtitle,
    this.metrics = const [],
    this.child,
    this.layout = SummaryCardLayout.list,
    this.collapsible = false,
    this.initiallyExpanded = true,
  });

  final String title;
  final String? subtitle;
  final List<SummaryMetric> metrics;
  final Widget? child;
  final SummaryCardLayout layout;
  final bool collapsible;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final content = <Widget>[];

    if (metrics.isNotEmpty) {
      content.add(_buildMetrics(context));
    }

    if (child != null) {
      if (content.isNotEmpty) {
        content.add(const SizedBox(height: 16));
      }
      content.add(child!);
    }

    if (collapsible) {
      return Card(
        child: ExpansionTile(
          maintainState: true,
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
          children: [
            if (metrics.isNotEmpty || child != null) ...[
              const SizedBox(height: 12),
              if (metrics.isNotEmpty) _buildMetrics(context),
              if (child != null) ...[
                if (metrics.isNotEmpty) const SizedBox(height: 16),
                child!,
              ],
            ],
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (content.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...content,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetrics(BuildContext context) {
    switch (layout) {
      case SummaryCardLayout.list:
        return Column(
          children: metrics
              .map(
                (metric) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _MetricRow(metric: metric),
                ),
              )
              .toList(),
        );
      case SummaryCardLayout.grid:
        return LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 560 ? 4 : 2;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: metrics.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisExtent: 96,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (context, index) =>
                  _MetricCard(metric: metrics[index]),
            );
          },
        );
    }
  }
}

class SummaryMetric {
  const SummaryMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.metric,
  });

  final SummaryMetric metric;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(metric.label, style: theme.bodyMedium),
        Text(metric.value, style: theme.titleMedium),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.metric,
  });

  final SummaryMetric metric;

  @override
  Widget build(BuildContext context) {
    final baseColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    final tintedColor = baseColor.withValues(
      alpha: (baseColor.a * 0.4).clamp(0.0, 1.0),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tintedColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            metric.label,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            metric.value,
            style: Theme.of(context).textTheme.titleMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

