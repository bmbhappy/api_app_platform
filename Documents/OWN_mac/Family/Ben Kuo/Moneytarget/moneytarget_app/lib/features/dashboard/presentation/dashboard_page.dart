import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../../data/models/currency_settings.dart';
import '../../../data/models/goal.dart';
import '../../../data/models/transaction_type.dart';
import '../../../data/repositories/mock_money_repository.dart';
import 'widgets/summary_card.dart';

enum DashboardRangeFilter { untilNow, month, week, custom }
enum GoalBreakdownInterval { year, month, week }

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.repository, required this.currencySettings});

  final MockMoneyRepository repository;
  final CurrencySettings currencySettings;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  CurrencySettings get currencySettings => widget.currencySettings;

  DashboardRangeFilter _filter = DashboardRangeFilter.untilNow;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  String? _customLabel;
  GoalBreakdownInterval _breakdownInterval = GoalBreakdownInterval.month;
  final Set<String> _visibleTrendMetrics = {'收入', '存款', '支出'};

  @override
  void initState() {
    super.initState();
    _setUntilNowRange();
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository &&
        _filter == DashboardRangeFilter.untilNow) {
      setState(_setUntilNowRange);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final goal = repository.goal;
    final totalSaving = repository.totalSaving;
    final difference = repository.differenceFromGoal;

    final start = _rangeStart;
    final end = _rangeEnd;

    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final cappedToday = normalizedToday.isAfter(goal.endDate)
        ? goal.endDate
        : normalizedToday;
    final effectiveToDateEnd = cappedToday.isBefore(goal.startDate)
        ? goal.startDate
        : cappedToday;
    final expectedToDateAmount =
        goal.expectedAmountUntil(effectiveToDateEnd);
    final actualToDateAmount = repository.totalByType(
      TransactionType.saving,
      start: goal.startDate,
      end: effectiveToDateEnd,
    );
    final expectedTotalProgress =
        goal.expectedProgressUntil(effectiveToDateEnd);
    final toDateCompletion = expectedToDateAmount == 0
        ? 0.0
        : (actualToDateAmount / expectedToDateAmount)
            .clamp(0.0, 2.0);
    final toDateDifference = actualToDateAmount - expectedToDateAmount;

    final incomeMonthlyAvg = repository.averagePerMonth(
      TransactionType.income,
      start: start,
      end: end,
    );
    final savingMonthlyAvg = repository.averagePerMonth(
      TransactionType.saving,
      start: start,
      end: end,
    );
    final expenseMonthlyAvg = repository.averagePerMonth(
      TransactionType.expense,
      start: start,
      end: end,
    );
    final incomeWeeklyAvg = repository.averagePerWeek(
      TransactionType.income,
      start: start,
      end: end,
    );
    final savingWeeklyAvg = repository.averagePerWeek(
      TransactionType.saving,
      start: start,
      end: end,
    );
    final expenseWeeklyAvg = repository.averagePerWeek(
      TransactionType.expense,
      start: start,
      end: end,
    );
    final expenseByCategory = repository.expenseTotalsByCategory(
      start: start,
      end: end,
    );
    final totalIncome = repository.totalByType(
      TransactionType.income,
      start: start,
      end: end,
    );
    final totalSavingFiltered = repository.totalByType(
      TransactionType.saving,
      start: start,
      end: end,
    );
    final totalExpense = repository.totalByType(
      TransactionType.expense,
      start: start,
      end: end,
    );
    final savingsNet = repository.netSavings(
      start: start,
      end: end,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TargetProgressCard(
          goal: goal,
          totalSaving: totalSaving,
          expectedToDateAmount: expectedToDateAmount,
          actualToDateAmount: actualToDateAmount,
          progress: repository.progress,
          totalDifference: difference,
          toDateDifference: toDateDifference,
          currencySettings: currencySettings,
          expectedProgress: expectedTotalProgress,
          toDateCompletion: toDateCompletion,
        ),
        const SizedBox(height: 16),
        _GoalBreakdownSection(
          goal: goal,
          repository: repository,
          interval: _breakdownInterval,
          onIntervalChanged: (interval) {
            setState(() {
              _breakdownInterval = interval;
            });
          },
          currencySettings: currencySettings,
          visibleMetrics: _visibleTrendMetrics,
          onToggleMetric: (metric) {
            setState(() {
              if (_visibleTrendMetrics.contains(metric)) {
                if (_visibleTrendMetrics.length > 1) {
                  _visibleTrendMetrics.remove(metric);
                }
              } else {
                _visibleTrendMetrics.add(metric);
              }
            });
          },
        ),
        const SizedBox(height: 16),
        SummaryCard(
          title: '平均存款需求',
          collapsible: true,
          metrics: [
            SummaryMetric(
              label: '每週平均',
              value: currencySettings.format(goal.requiredWeeklyAmount),
            ),
            SummaryMetric(
              label: '每月平均',
              value: currencySettings.format(goal.requiredMonthlyAmount),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _DashboardFilterBar(
          filter: _filter,
          rangeLabel: _currentRangeLabel(),
          onFilterSelected: _handleFilterSelected,
        ),
        const SizedBox(height: 16),
        SummaryCard(
          title: '累積概況',
          collapsible: true,
          subtitle: '收入 / 存款 / 支出',
          metrics: [
            SummaryMetric(
              label: '收入累積',
              value: currencySettings.format(totalIncome),
            ),
            SummaryMetric(
              label: '存款累積',
              value: currencySettings.format(totalSavingFiltered),
            ),
            SummaryMetric(
              label: '支出累積',
              value: currencySettings.format(totalExpense),
            ),
            SummaryMetric(
              label: '剩餘',
              value: currencySettings.format(totalIncome - totalExpense - totalSavingFiltered),
            ),
          ],
          layout: SummaryCardLayout.grid,
        ),
        const SizedBox(height: 16),
        SummaryCard(
          title: '收入 / 存款 / 支出',
          collapsible: true,
          subtitle: '平均值 (月 / 週)',
          metrics: [
            SummaryMetric(
              label: '收入月平均',
              value: currencySettings.format(incomeMonthlyAvg),
            ),
            SummaryMetric(
              label: '收入週平均',
              value: currencySettings.format(incomeWeeklyAvg),
            ),
            SummaryMetric(
              label: '存款月平均',
              value: currencySettings.format(savingMonthlyAvg),
            ),
            SummaryMetric(
              label: '存款週平均',
              value: currencySettings.format(savingWeeklyAvg),
            ),
            SummaryMetric(
              label: '支出月平均',
              value: currencySettings.format(expenseMonthlyAvg),
            ),
            SummaryMetric(
              label: '支出週平均',
              value: currencySettings.format(expenseWeeklyAvg),
            ),
          ],
          layout: SummaryCardLayout.grid,
        ),
        const SizedBox(height: 16),
        SummaryCard(
          title: '支出分析',
          collapsible: true,
          subtitle: '依類別彙整 (總額: ${currencySettings.format(totalExpense)})',
          child: Column(
            children: expenseByCategory.entries.map((entry) {
              final total = entry.value;
              final ratio =
                  totalExpense == 0 ? 0.0 : total / totalExpense;
              final progressValue =
                  ratio < 0 ? 0.0 : (ratio > 1 ? 1.0 : ratio);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(entry.key),
                    ),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(currencySettings.format(total)),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: progressValue,
                            minHeight: 6,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('${(ratio * 100).toStringAsFixed(1)}%'),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  void _handleFilterSelected(DashboardRangeFilter filter) {
    if (filter == _filter && filter != DashboardRangeFilter.custom) {
      return;
    }

    switch (filter) {
      case DashboardRangeFilter.untilNow:
        setState(() {
          _filter = DashboardRangeFilter.untilNow;
          _setUntilNowRange();
        });
        break;
      case DashboardRangeFilter.month:
        _selectMonth();
        break;
      case DashboardRangeFilter.week:
        _selectWeek();
        break;
      case DashboardRangeFilter.custom:
        _selectCustomRange();
        break;
    }
  }

  void _setUntilNowRange() {
    final entries = widget.repository.entries;
    if (entries.isEmpty) {
      _rangeStart = null;
      _rangeEnd = null;
      _customLabel = null;
      return;
    }
    final earliest = entries
        .map((entry) =>
            DateTime(entry.date.year, entry.date.month, entry.date.day))
        .reduce(
            (value, element) => value.isBefore(element) ? value : element);
    final today = DateTime.now();
    final normalizedToday =
        DateTime(today.year, today.month, today.day);
    _rangeStart = earliest;
    _rangeEnd = normalizedToday;
    _customLabel = null;
  }

  Future<void> _selectMonth() async {
    final months = _availableMonths();
    if (months.isEmpty) {
      return;
    }

    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (context) => _SelectionSheet<DateTime>(
        title: '選擇月份',
        items: months,
        itemBuilder: (value) => DateFormat.yMMM('zh_TW').format(value),
        isSelected: (value) =>
            _filter == DashboardRangeFilter.month &&
            _rangeStart != null &&
            _rangeStart!.year == value.year &&
            _rangeStart!.month == value.month,
      ),
    );

    if (selected == null) return;

    setState(() {
      _filter = DashboardRangeFilter.month;
      _rangeStart = DateTime(selected.year, selected.month, 1);
      _rangeEnd = DateTime(selected.year, selected.month + 1, 0);
      _customLabel = DateFormat.yMMM('zh_TW').format(_rangeStart!);
    });
  }

  Future<void> _selectWeek() async {
    final weeks = _availableWeeks();
    if (weeks.isEmpty) {
      return;
    }

    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (context) => _SelectionSheet<DateTime>(
        title: '選擇週',
        items: weeks,
        itemBuilder: (start) {
          final end = start.add(const Duration(days: 6));
          return '${DateFormat.Md('zh_TW').format(start)} - ${DateFormat.Md('zh_TW').format(end)}';
        },
        isSelected: (value) =>
            _filter == DashboardRangeFilter.week &&
            _rangeStart == value,
      ),
    );

    if (selected == null) return;

    setState(() {
      _filter = DashboardRangeFilter.week;
      _rangeStart = selected;
      _rangeEnd = selected.add(const Duration(days: 6));
      _customLabel =
          '${DateFormat.Md('zh_TW').format(_rangeStart!)} - ${DateFormat.Md('zh_TW').format(_rangeEnd!)}';
    });
  }

  Future<void> _selectCustomRange() async {
    final initialRange = _rangeStart != null && _rangeEnd != null
        ? DateTimeRange(start: _rangeStart!, end: _rangeEnd!)
        : DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 6)),
            end: DateTime.now(),
          );

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    setState(() {
      _filter = DashboardRangeFilter.custom;
      _rangeStart = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _rangeEnd = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
      );
      _customLabel =
          '${DateFormat.yMd('zh_TW').format(_rangeStart!)} - ${DateFormat.yMd('zh_TW').format(_rangeEnd!)}';
    });
  }

  String _currentRangeLabel() {
    switch (_filter) {
      case DashboardRangeFilter.untilNow:
        if (_rangeStart == null || _rangeEnd == null) {
          return '顯示全部';
        }
        return '至今：${DateFormat.yMd('zh_TW').format(_rangeStart!)} - ${DateFormat.yMd('zh_TW').format(_rangeEnd!)}';
      case DashboardRangeFilter.month:
      case DashboardRangeFilter.week:
      case DashboardRangeFilter.custom:
        return _customLabel ?? '已選日期範圍';
    }
  }

  List<DateTime> _availableMonths() {
    final set = <DateTime>{};
    for (final entry in widget.repository.entries) {
      set.add(DateTime(entry.date.year, entry.date.month));
    }
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  List<DateTime> _availableWeeks() {
    final set = <DateTime>{};
    for (final entry in widget.repository.entries) {
      final start =
          entry.date.subtract(Duration(days: entry.date.weekday - 1));
      set.add(DateTime(start.year, start.month, start.day));
    }
    final list = set.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }
}

class TargetProgressCard extends StatelessWidget {
  const TargetProgressCard({
    super.key,
    required this.goal,
    required this.totalSaving,
    required this.expectedToDateAmount,
    required this.actualToDateAmount,
    required this.progress,
    required this.totalDifference,
    required this.toDateDifference,
    required this.currencySettings,
    required this.expectedProgress,
    required this.toDateCompletion,
  });

  final Goal goal;
  final double totalSaving;
  final double expectedToDateAmount;
  final double actualToDateAmount;
  final double progress;
  final double totalDifference;
  final double toDateDifference;
  final CurrencySettings currencySettings;
  final double expectedProgress;
  final double toDateCompletion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clampedProgress = progress.clamp(0.0, 1.0);
    final clampedExpected = expectedProgress.clamp(0.0, 1.0);
    final targetAmountLabel = currencySettings.format(goal.targetAmount);
    final actualLabel = currencySettings.format(totalSaving);
    final expectedLabel = currencySettings.format(expectedToDateAmount);

    final bool behindSchedule = toDateCompletion < 1.0;
    final Color warningColor = theme.colorScheme.error;
    final Color successColor = theme.colorScheme.primary;

    Widget metricRow(String label, String value, {Color? color}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color ?? theme.colorScheme.onSurface,
              ),
            ),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                color: color ?? theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
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
              '目標概況',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '期間：${DateFormat.yMMMd().format(goal.startDate)} - ${DateFormat.yMMMd().format(goal.endDate)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text(
              '目前存款 $actualLabel',
              style: theme.textTheme.titleMedium?.copyWith(
                color: successColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            _GoalProgressBar(
              progress: clampedProgress,
              expectedProgress: clampedExpected,
              targetAmountLabel: targetAmountLabel,
              expectedAmountLabel: expectedLabel,
              actualAmountLabel: actualLabel,
              currencySettings: currencySettings,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ProgressPie(
                  label: '總達成率',
                  value: progress,
                  color: progress >= 1.0
                      ? successColor
                      : theme.colorScheme.secondary,
                ),
                _ProgressPie(
                  label: '至今日達成率',
                  value: toDateCompletion,
                  color: behindSchedule ? warningColor : successColor,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Divider(color: theme.colorScheme.outlineVariant, height: 24),
            Text('整體統計', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            metricRow('目標金額', targetAmountLabel),
            metricRow(
              totalDifference >= 0 ? '總尚需金額' : '總超出金額',
              currencySettings.format(totalDifference.abs()),
            ),
            const SizedBox(height: 16),
            Divider(color: theme.colorScheme.outlineVariant, height: 24),
            Text('至今日', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            metricRow('至今日應存', expectedLabel),
            metricRow(
              toDateDifference >= 0 ? '至今日超出' : '至今日尚差',
              currencySettings.format(toDateDifference.abs()),
              color: toDateDifference >= 0 ? successColor : warningColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalProgressBar extends StatelessWidget {
  const _GoalProgressBar({
    required this.progress,
    required this.expectedProgress,
    required this.targetAmountLabel,
    required this.expectedAmountLabel,
    required this.actualAmountLabel,
    required this.currencySettings,
  });

  final double progress;
  final double expectedProgress;
  final String targetAmountLabel;
  final String expectedAmountLabel;
  final String actualAmountLabel;
  final CurrencySettings currencySettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final barHeight = 36.0;
        final actualWidth = (width * progress).clamp(0.0, width);
        final expectedPosition = (width * expectedProgress).clamp(0.0, width);

        return SizedBox(
          height: 120,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 52,
                child: Container(
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(barHeight / 2),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 52,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: barHeight,
                  width: actualWidth,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(barHeight / 2),
                  ),
                ),
              ),
              Positioned(
                left: expectedPosition - 1,
                top: 40,
                child: Container(
                  width: 2,
                  height: barHeight + 20,
                  color: theme.colorScheme.secondary,
                ),
              ),
              Positioned(
                top: 18,
                right: 0,
                child: Text(
                  '目標 $targetAmountLabel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Positioned(
                top: 100,
                right: 0,
                child: Text(
                  '應存 $expectedAmountLabel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Positioned(
                top: 100,
                left: 0,
                child: Text(
                  '目前 $actualAmountLabel',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProgressPie extends StatelessWidget {
  const _ProgressPie({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayValue = value * 100;
    final indicatorValue = value.clamp(0.0, 1.0);

    return SizedBox(
      width: 100,
      height: 120,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 88,
                height: 88,
                child: CircularProgressIndicator(
                  value: indicatorValue,
                  strokeWidth: 10,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${displayValue.toStringAsFixed(1)}%',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _DashboardFilterBar extends StatelessWidget {
  const _DashboardFilterBar({
    required this.filter,
    required this.rangeLabel,
    required this.onFilterSelected,
  });

  final DashboardRangeFilter filter;
  final String rangeLabel;
  final ValueChanged<DashboardRangeFilter> onFilterSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '資料篩選',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterChip(
                  label: '至今',
                  selected: filter == DashboardRangeFilter.untilNow,
                  onSelected: () => onFilterSelected(
                    DashboardRangeFilter.untilNow,
                  ),
                ),
                _FilterChip(
                  label: '月份',
                  selected: filter == DashboardRangeFilter.month,
                  onSelected: () =>
                      onFilterSelected(DashboardRangeFilter.month),
                ),
                _FilterChip(
                  label: '週',
                  selected: filter == DashboardRangeFilter.week,
                  onSelected: () =>
                      onFilterSelected(DashboardRangeFilter.week),
                ),
                _FilterChip(
                  label: '自訂',
                  selected: filter == DashboardRangeFilter.custom,
                  onSelected: () =>
                      onFilterSelected(DashboardRangeFilter.custom),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(rangeLabel),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

class _SelectionSheet<T> extends StatelessWidget {
  const _SelectionSheet({
    required this.title,
    required this.items,
    required this.itemBuilder,
    required this.isSelected,
  });

  final String title;
  final List<T> items;
  final String Function(T value) itemBuilder;
  final bool Function(T value) isSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Divider(height: 0),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 0),
              itemBuilder: (context, index) {
                final value = items[index];
                final selected = isSelected(value);
                return ListTile(
                  title: Text(itemBuilder(value)),
                  trailing: selected
                      ? const Icon(Icons.check, color: Colors.teal)
                      : null,
                  onTap: () => Navigator.of(context).pop(value),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalBreakdownSection extends StatelessWidget {
  const _GoalBreakdownSection({
    required this.goal,
    required this.repository,
    required this.interval,
    required this.onIntervalChanged,
    required this.currencySettings,
    required this.visibleMetrics,
    required this.onToggleMetric,
  });

  final Goal goal;
  final MockMoneyRepository repository;
  final GoalBreakdownInterval interval;
  final ValueChanged<GoalBreakdownInterval> onIntervalChanged;
  final CurrencySettings currencySettings;
  final Set<String> visibleMetrics;
  final ValueChanged<String> onToggleMetric;

  @override
  Widget build(BuildContext context) {
    final data = _buildBreakdownData();
    final theme = Theme.of(context);
    final locale =
        currencySettings.selectedCurrency == Currency.twd ? 'zh_TW' : 'en_AU';
    final numberFormat = NumberFormat.decimalPattern(locale)
      ..maximumFractionDigits =
          currencySettings.selectedCurrency == Currency.twd ? 0 : 2;

    final requiredAmount = _requiredAmountForInterval();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '收支趨勢',
                  style: theme.textTheme.titleMedium,
                ),
                SegmentedButton<GoalBreakdownInterval>(
                  segments: const [
                    ButtonSegment(
                      value: GoalBreakdownInterval.year,
                      label: Text('年'),
                    ),
                    ButtonSegment(
                      value: GoalBreakdownInterval.month,
                      label: Text('月'),
                    ),
                    ButtonSegment(
                      value: GoalBreakdownInterval.week,
                      label: Text('週'),
                    ),
                  ],
                  selected: {interval},
                  onSelectionChanged: (selection) =>
                      onIntervalChanged(selection.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricToggleChip(
                  label: '收入',
                  color: Colors.blue,
                  selected: visibleMetrics.contains('收入'),
                  onSelected: onToggleMetric,
                ),
                _MetricToggleChip(
                  label: '存款',
                  color: theme.colorScheme.primary,
                  selected: visibleMetrics.contains('存款'),
                  onSelected: onToggleMetric,
                ),
                _MetricToggleChip(
                  label: '支出',
                  color: theme.colorScheme.error,
                  selected: visibleMetrics.contains('支出'),
                  onSelected: onToggleMetric,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (data.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '目前沒有資料可顯示',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              )
            else if (visibleMetrics.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '請至少保留一個趨勢指標顯示',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              )
            else
              SizedBox(
                height: 260,
                child: _GoalBreakdownTrendChart(
                  data: data,
                  numberFormat: numberFormat,
                  currencySettings: currencySettings,
                  theme: theme,
                  requiredAmount: requiredAmount,
                  visibleMetrics: visibleMetrics,
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_BreakdownGroup> _buildBreakdownData() {
    final entries = repository.entries
        .where((entry) =>
            !entry.date.isBefore(goal.startDate) &&
            !entry.date.isAfter(goal.endDate))
        .toList();
    if (entries.isEmpty) return [];

    final map = <String, _BreakdownGroup>{};

    for (final entry in entries) {
      final normalizedDate =
          DateTime(entry.date.year, entry.date.month, entry.date.day);
      late String groupKey;
      late DateTime sortKey;
      late String label;
      late DateTime periodStart;
      late DateTime periodEnd;

      switch (interval) {
        case GoalBreakdownInterval.year:
          groupKey = '${normalizedDate.year}';
          sortKey = DateTime(normalizedDate.year);
          label = '${normalizedDate.year}年';
          periodStart = DateTime(normalizedDate.year, 1, 1);
          periodEnd = DateTime(normalizedDate.year, 12, 31);
          break;
        case GoalBreakdownInterval.month:
          groupKey = '${normalizedDate.year}-${normalizedDate.month}';
          sortKey = DateTime(normalizedDate.year, normalizedDate.month, 1);
          label = DateFormat('yyyy/MM').format(sortKey);
          periodStart = DateTime(normalizedDate.year, normalizedDate.month, 1);
          final nextMonth = normalizedDate.month == 12 ? 1 : normalizedDate.month + 1;
          final nextYear = normalizedDate.month == 12
              ? normalizedDate.year + 1
              : normalizedDate.year;
          periodEnd = DateTime(nextYear, nextMonth, 1)
              .subtract(const Duration(days: 1));
          break;
        case GoalBreakdownInterval.week:
          final weekStart = normalizedDate
              .subtract(Duration(days: normalizedDate.weekday - 1));
          final weekEnd = weekStart.add(const Duration(days: 6));
          groupKey =
              '${weekStart.year}-${weekStart.month}-${weekStart.day}';
          sortKey = weekStart;
          label = DateFormat('MM/dd').format(weekStart);
          periodStart = weekStart;
          periodEnd = weekEnd;
          break;
      }

      final group = map.putIfAbsent(
        groupKey,
        () => _BreakdownGroup(
          label: label,
          sortKey: sortKey,
          periodStart: periodStart,
          periodEnd: periodEnd,
        ),
      );

      switch (entry.type) {
        case TransactionType.income:
          group.income += entry.amount;
          break;
        case TransactionType.saving:
          group.saving += entry.amount;
          break;
        case TransactionType.expense:
          group.expense += entry.amount;
          break;
      }
    }

    final groups = map.values.toList()
      ..sort((a, b) => a.sortKey.compareTo(b.sortKey));

    if (interval == GoalBreakdownInterval.week && groups.length > 12) {
      return groups.sublist(groups.length - 12);
    }

    return groups;
  }

  double _requiredAmountForInterval() {
    switch (interval) {
      case GoalBreakdownInterval.year:
        final years = goal.endDate.year - goal.startDate.year + 1;
        if (years <= 0) {
          return goal.targetAmount;
        }
        return goal.targetAmount / years;
      case GoalBreakdownInterval.month:
        return goal.requiredMonthlyAmount;
      case GoalBreakdownInterval.week:
        return goal.requiredWeeklyAmount;
    }
  }
}

class _GoalBreakdownTrendChart extends StatelessWidget {
  const _GoalBreakdownTrendChart({
    required this.data,
    required this.numberFormat,
    required this.currencySettings,
    required this.theme,
    required this.requiredAmount,
    required this.visibleMetrics,
  });

  final List<_BreakdownGroup> data;
  final NumberFormat numberFormat;
  final CurrencySettings currencySettings;
  final ThemeData theme;
  final double requiredAmount;
  final Set<String> visibleMetrics;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox.shrink();
    }

    final metrics = [
      _TrendMetric(
        label: '收入',
        color: Colors.blue,
        extractor: (group) => group.income,
      ),
      _TrendMetric(
        label: '存款',
        color: theme.colorScheme.primary,
        extractor: (group) => group.saving,
      ),
      _TrendMetric(
        label: '支出',
        color: theme.colorScheme.error,
        extractor: (group) => group.expense,
      ),
    ];

    final activeMetrics = metrics
        .where((metric) => visibleMetrics.contains(metric.label))
        .toList(growable: false);

    if (activeMetrics.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const double horizontalPadding = 32;
        final double baseWidth = data.length <= 1
            ? horizontalPadding * 2
            : horizontalPadding * 2 + 64 * (data.length - 1);
        final double chartWidth = math.max(constraints.maxWidth, baseWidth);
        final savingColor =
            metrics.firstWhere((metric) => metric.label == '存款').color;
        final showAverageLine =
            activeMetrics.any((metric) => metric.label == '存款');

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: chartWidth,
            child: CustomPaint(
              size: Size(chartWidth, 220),
              painter: _TrendLinePainter(
                data: data,
                metrics: activeMetrics,
                numberFormat: numberFormat,
                axisColor: theme.colorScheme.outlineVariant,
                labelStyle:
                    theme.textTheme.labelSmall ?? const TextStyle(fontSize: 11),
                horizontalPadding: horizontalPadding,
                requiredAmount: requiredAmount,
                averageColor: savingColor,
                currencySettings: currencySettings,
                showAverageLine: showAverageLine,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TrendLinePainter extends CustomPainter {
  _TrendLinePainter({
    required this.data,
    required this.metrics,
    required this.numberFormat,
    required this.axisColor,
    required this.labelStyle,
    required this.horizontalPadding,
    required this.requiredAmount,
    required this.averageColor,
    required this.currencySettings,
    required this.showAverageLine,
  });

  final List<_BreakdownGroup> data;
  final List<_TrendMetric> metrics;
  final NumberFormat numberFormat;
  final Color axisColor;
  final TextStyle labelStyle;
  final double horizontalPadding;
  final double requiredAmount;
  final Color averageColor;
  final CurrencySettings currencySettings;
  final bool showAverageLine;

  @override
  void paint(Canvas canvas, Size size) {
    if (metrics.isEmpty) {
      return;
    }
    final maxValue = _maxDataValue();
    final double top = 24;
    final double bottom = size.height - 48;
    final double usableHeight = (bottom - top).clamp(0, double.infinity);
    final double left = horizontalPadding;
    final double right = size.width - horizontalPadding;
    final double step = data.length <= 1
        ? 0
        : (right - left) / (data.length - 1);

    final gridPaint = Paint()
      ..color = axisColor.withValues(alpha: axisColor.a * 0.4)
      ..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final dy = bottom - (usableHeight * i / 4);
      canvas.drawLine(Offset(left, dy), Offset(right, dy), gridPaint);
    }

    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    );

    if (showAverageLine && requiredAmount > 0 && maxValue > 0) {
      final averageRatio = (requiredAmount / maxValue).clamp(0.0, 1.0);
      final averageY = bottom - usableHeight * averageRatio;
      final dashPaint = Paint()
        ..color = averageColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      const dashWidth = 8.0;
      const dashSpace = 4.0;
      var startX = left;
      while (startX < right) {
        final endX = math.min(startX + dashWidth, right);
        canvas.drawLine(Offset(startX, averageY), Offset(endX, averageY), dashPaint);
        startX = endX + dashSpace;
      }

      textPainter.text = TextSpan(
        text:
            '平均存款需求 ${currencySettings.symbol}${numberFormat.format(currencySettings.toDisplay(requiredAmount))}',
        style: labelStyle.copyWith(color: averageColor, fontWeight: FontWeight.w600),
      );
      textPainter.layout();
      final labelOffset = Offset(
        right - textPainter.width,
        averageY - textPainter.height - 6,
      );
      textPainter.paint(canvas, labelOffset);
    }

    for (final metric in metrics) {
      final paint = Paint()
        ..color = metric.color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path();
      final pointPaint = Paint()
        ..color = metric.color
        ..style = PaintingStyle.fill;

      Offset? previousPoint;
      for (var i = 0; i < data.length; i++) {
        final value = metric.extractor(data[i]);
        final ratio = maxValue == 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
        final dx = left + (i * step);
        final dy = bottom - usableHeight * ratio;
        final point = Offset(dx, dy);

        if (previousPoint == null) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
        previousPoint = point;
      }

      if (previousPoint == null) {
        continue;
      }

      canvas.drawPath(path, paint);

      for (var i = 0; i < data.length; i++) {
        final rawValue = metric.extractor(data[i]);
        final displayValue = currencySettings.toDisplay(rawValue);
        final ratio =
            maxValue == 0 ? 0.0 : (rawValue / maxValue).clamp(0.0, 1.0);
        final dx = left + (i * step);
        final dy = bottom - usableHeight * ratio;
        final point = Offset(dx, dy);

        canvas.drawCircle(point, 4, pointPaint);

        textPainter.text = TextSpan(
          text:
              '${currencySettings.symbol}${numberFormat.format(displayValue)}',
          style: labelStyle.copyWith(color: metric.color),
        );
        textPainter.layout();
        final labelOffset = Offset(
          point.dx - textPainter.width / 2,
          point.dy - textPainter.height - 6,
        );
        textPainter.paint(canvas, labelOffset);
      }
    }

    // X-axis labels
    for (var i = 0; i < data.length; i++) {
      final dx = left + (data.length <= 1 ? 0 : i * step);
      textPainter.text = TextSpan(
        text: data[i].label,
        style: labelStyle,
      );
      textPainter.layout();
      final labelOffset = Offset(
        dx - textPainter.width / 2,
        bottom + 8,
      );
      textPainter.paint(canvas, labelOffset);
    }

    // X-axis line
    canvas.drawLine(Offset(left, bottom), Offset(right, bottom), gridPaint);
  }

  double _maxDataValue() {
    double maxValue = 0;
    for (final group in data) {
      for (final metric in metrics) {
        maxValue = math.max(maxValue, metric.extractor(group));
      }
    }
    if (showAverageLine) {
      maxValue = math.max(maxValue, requiredAmount);
    }
    return maxValue <= 0 ? 1 : maxValue;
  }

  @override
  bool shouldRepaint(covariant _TrendLinePainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.metrics != metrics ||
        oldDelegate.horizontalPadding != horizontalPadding;
  }
}

class _BreakdownGroup {
  _BreakdownGroup({
    required this.label,
    required this.sortKey,
    required this.periodStart,
    required this.periodEnd,
  });

  final String label;
  final DateTime sortKey;
  final DateTime periodStart;
  final DateTime periodEnd;
  double income = 0;
  double saving = 0;
  double expense = 0;

  double get maxValue => math.max(income, math.max(saving, expense));
}

class _TrendMetric {
  const _TrendMetric({
    required this.label,
    required this.color,
    required this.extractor,
  });

  final String label;
  final Color color;
  final double Function(_BreakdownGroup group) extractor;
}

class _MetricToggleChip extends StatelessWidget {
  const _MetricToggleChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final Color color;
  final bool selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilterChip(
      label: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      avatar: CircleAvatar(
        backgroundColor: color,
        radius: 6,
      ),
      selected: selected,
      selectedColor: color.withValues(alpha: (color.a * 0.85).clamp(0.0, 1.0)),
      showCheckmark: false,
      onSelected: (_) => onSelected(label),
    );
  }
}

