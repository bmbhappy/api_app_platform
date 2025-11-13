import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/models/currency_settings.dart';
import '../../../data/models/transaction_type.dart';
import '../../../data/repositories/mock_money_repository.dart';

class GoalProgressPage extends StatefulWidget {
  const GoalProgressPage({
    super.key,
    required this.repository,
    required this.currencySettings,
  });

  final MockMoneyRepository repository;
  final CurrencySettings currencySettings;

  @override
  State<GoalProgressPage> createState() => _GoalProgressPageState();
}

class _GoalProgressPageState extends State<GoalProgressPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurface,
              indicatorColor: Theme.of(context).colorScheme.primary,
              tabs: const [
                Tab(text: '月份'),
                Tab(text: '週次'),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _MonthlyProgressView(
                repository: widget.repository,
                currencySettings: widget.currencySettings,
              ),
              _WeeklyProgressView(
                repository: widget.repository,
                currencySettings: widget.currencySettings,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MonthlyProgressView extends StatelessWidget {
  const _MonthlyProgressView({
    required this.repository,
    required this.currencySettings,
  });

  final MockMoneyRepository repository;
  final CurrencySettings currencySettings;

  @override
  Widget build(BuildContext context) {
    final goal = repository.goal;
    final now = DateTime.now();
    final end = goal.endDate.isBefore(now) ? goal.endDate : now;
    final months = _generateMonths(goal.startDate, end);
    final monthTotals =
        repository.monthlyTotals(TransactionType.saving, start: goal.startDate, end: end);
    final requiredMonthly = goal.requiredMonthlyAmount;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: months.length,
      itemBuilder: (context, index) {
        final month = months[index];
        final total = monthTotals[month] ?? 0;
        final difference = total - requiredMonthly;
        final achieved = total >= requiredMonthly;
        return _ProgressTile(
          title: DateFormat.yMMMM('zh_TW').format(month),
          detail:
              '目標 ${currencySettings.format(requiredMonthly)}｜實際 ${currencySettings.format(total)}',
          statusText: achieved ? '達標' : '未達標',
          differenceText: achieved
              ? '+${currencySettings.format(difference)}'
              : '-${currencySettings.format(difference.abs())}',
          achieved: achieved,
        );
      },
    );
  }

  List<DateTime> _generateMonths(DateTime start, DateTime end) {
    final months = <DateTime>[];
    var current = DateTime(start.year, start.month);
    final endMonth = DateTime(end.year, end.month);
    while (!current.isAfter(endMonth)) {
      months.add(current);
      if (current.month == 12) {
        current = DateTime(current.year + 1, 1);
      } else {
        current = DateTime(current.year, current.month + 1);
      }
    }
    return months;
  }
}

class _WeeklyProgressView extends StatelessWidget {
  const _WeeklyProgressView({
    required this.repository,
    required this.currencySettings,
  });

  final MockMoneyRepository repository;
  final CurrencySettings currencySettings;

  @override
  Widget build(BuildContext context) {
    final goal = repository.goal;
    final now = DateTime.now();
    final end = goal.endDate.isBefore(now) ? goal.endDate : now;
    final weeks = _generateWeeks(goal.startDate, end);
    final weekTotals =
        repository.weeklyTotals(TransactionType.saving, start: goal.startDate, end: end);
    final requiredWeekly = goal.requiredWeeklyAmount;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: weeks.length,
      itemBuilder: (context, index) {
        final startOfWeek = weeks[index];
        final total = weekTotals[startOfWeek] ?? 0;
        final endOfWeek = startOfWeek.add(const Duration(days: 6));
        final difference = total - requiredWeekly;
        final achieved = total >= requiredWeekly;
        return _ProgressTile(
          title:
              '${DateFormat.Md('zh_TW').format(startOfWeek)} - ${DateFormat.Md('zh_TW').format(endOfWeek)}',
          detail:
              '目標 ${currencySettings.format(requiredWeekly)}｜實際 ${currencySettings.format(total)}',
          statusText: achieved ? '達標' : '未達標',
          differenceText: achieved
              ? '+${currencySettings.format(difference)}'
              : '-${currencySettings.format(difference.abs())}',
          achieved: achieved,
        );
      },
    );
  }

  List<DateTime> _generateWeeks(DateTime start, DateTime end) {
    final weeks = <DateTime>[];
    var current =
        start.subtract(Duration(days: start.weekday - 1));
    final endWeek =
        end.subtract(Duration(days: end.weekday - 1));
    while (!current.isAfter(endWeek)) {
      weeks.add(DateTime(current.year, current.month, current.day));
      current = current.add(const Duration(days: 7));
    }
    return weeks;
  }
}

class _ProgressTile extends StatelessWidget {
  const _ProgressTile({
    required this.title,
    required this.detail,
    required this.statusText,
    required this.differenceText,
    required this.achieved,
  });

  final String title;
  final String detail;
  final String statusText;
  final String differenceText;
  final bool achieved;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = achieved ? colorScheme.secondary : colorScheme.error;
    final backgroundColor = achieved
        ? colorScheme.secondaryContainer
        : colorScheme.errorContainer.withValues(
            alpha:
                (colorScheme.errorContainer.a * 0.15).clamp(0.0, 1.0),
          );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(
                  label: Text(statusText),
                  backgroundColor: statusColor.withValues(
                    alpha: (statusColor.a * 0.12).clamp(0.0, 1.0),
                  ),
                  labelStyle: TextStyle(color: statusColor),
                ),
                Text(
                  differenceText,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: statusColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

