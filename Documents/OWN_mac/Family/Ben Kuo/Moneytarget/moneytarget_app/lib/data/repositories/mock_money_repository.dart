import 'dart:math';

import '../models/category_settings.dart';
import '../models/goal.dart';
import '../models/money_entry.dart';
import '../models/transaction_type.dart';

class MockMoneyRepository {
  MockMoneyRepository({
    required this.goal,
    required List<MoneyEntry> entries,
    required this.categorySettings,
  }) : entries = List<MoneyEntry>.unmodifiable(entries);

  final Goal goal;
  final List<MoneyEntry> entries;
  final CategorySettings categorySettings;

  factory MockMoneyRepository.generate() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 5, 1);
    final end = DateTime(now.year, now.month + 6, 0);
    final random = Random(42);

    final goal = Goal(
      targetAmount: 200000,
      startDate: start,
      endDate: end,
    );

    final defaultCategories = CategorySettings.defaults();

    final List<MoneyEntry> entries = [];

    for (int i = 0; i < 24; i++) {
      final date = start.add(Duration(days: random.nextInt(goal.totalDays)));
      entries.add(
        MoneyEntry(
          id: 'income_$i',
          type: TransactionType.income,
          amount: (30000 + random.nextInt(10000)).toDouble(),
          date: date,
          source: defaultCategories.incomeSources[i % defaultCategories.incomeSources.length],
          note: '收入第 ${i + 1} 筆',
        ),
      );
    }

    for (int i = 0; i < 36; i++) {
      final date = start.add(Duration(days: random.nextInt(goal.totalDays)));
      entries.add(
        MoneyEntry(
          id: 'saving_$i',
          type: TransactionType.saving,
          amount: (5000 + random.nextInt(8000)).toDouble(),
          date: date,
          source: defaultCategories.savingSources[i % defaultCategories.savingSources.length],
          note: '存款第 ${i + 1} 筆',
        ),
      );
    }

    for (int i = 0; i < 48; i++) {
      final date = start.add(Duration(days: random.nextInt(goal.totalDays)));
      entries.add(
        MoneyEntry(
          id: 'expense_$i',
          type: TransactionType.expense,
          amount: (1500 + random.nextInt(6000)).toDouble(),
          date: date,
          category:
              defaultCategories.expenseCategories[random.nextInt(defaultCategories.expenseCategories.length)],
          note: '支出第 ${i + 1} 筆',
        ),
      );
    }

    entries.sort((a, b) => a.date.compareTo(b.date));

    return MockMoneyRepository(
      goal: goal,
      entries: entries,
      categorySettings: defaultCategories,
    );
  }

  MockMoneyRepository copyWith({
    Goal? goal,
    List<MoneyEntry>? entries,
    CategorySettings? categorySettings,
  }) {
    return MockMoneyRepository(
      goal: goal ?? this.goal,
      entries: entries ?? this.entries,
      categorySettings: categorySettings ?? this.categorySettings,
    );
  }

  List<String> get incomeSources => categorySettings.incomeSources;

  List<String> get savingSources => categorySettings.savingSources;

  List<String> get expenseCategories => categorySettings.expenseCategories;

  DateTime _normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _isWithinRange(DateTime date, DateTime? start, DateTime? end) {
    final normalizedDate = _normalizeDate(date);
    final normalizedStart = start == null ? null : _normalizeDate(start);
    final normalizedEnd = end == null ? null : _normalizeDate(end);

    if (normalizedStart != null && normalizedDate.isBefore(normalizedStart)) {
      return false;
    }
    if (normalizedEnd != null && normalizedDate.isAfter(normalizedEnd)) {
      return false;
    }
    return true;
  }

  Iterable<MoneyEntry> _filteredEntries(TransactionType? type,
      {DateTime? start, DateTime? end}) sync* {
    for (final entry in entries) {
      if (type != null && entry.type != type) continue;
      if (!_isWithinRange(entry.date, start, end)) continue;
      yield entry;
    }
  }

  double totalByType(
    TransactionType type, {
    DateTime? start,
    DateTime? end,
  }) {
    return _filteredEntries(type, start: start, end: end)
        .fold<double>(0, (prev, element) => prev + element.amount);
  }

  double get totalIncome => totalByType(TransactionType.income);

  double get totalSaving => totalByType(TransactionType.saving);

  double get totalExpense => totalByType(TransactionType.expense);

  double netSavings({DateTime? start, DateTime? end}) =>
      totalByType(TransactionType.saving, start: start, end: end) -
      totalByType(TransactionType.expense, start: start, end: end);

  double get savingsNet => netSavings();

  double get progress => goal.targetAmount == 0
      ? 0
      : (totalSaving / goal.targetAmount).clamp(0, 1);

  double get progressPercentage => progress * 100;

  double get differenceFromGoal => goal.targetAmount - totalSaving;

  Map<DateTime, double> monthlyTotals(
    TransactionType type, {
    DateTime? start,
    DateTime? end,
  }) {
    final map = <DateTime, double>{};
    for (final entry in _filteredEntries(type, start: start, end: end)) {
      final monthKey = DateTime(entry.date.year, entry.date.month);
      map.update(monthKey, (value) => value + entry.amount,
          ifAbsent: () => entry.amount);
    }
    return map;
  }

  Map<DateTime, double> weeklyTotals(
    TransactionType type, {
    DateTime? start,
    DateTime? end,
  }) {
    final map = <DateTime, double>{};
    for (final entry in _filteredEntries(type, start: start, end: end)) {
      final weekStart =
          entry.date.subtract(Duration(days: entry.date.weekday - 1));
      final weekKey = DateTime(weekStart.year, weekStart.month, weekStart.day);
      map.update(weekKey, (value) => value + entry.amount,
          ifAbsent: () => entry.amount);
    }
    return map;
  }

  double averagePerMonth(
    TransactionType type, {
    DateTime? start,
    DateTime? end,
  }) {
    final totals =
        monthlyTotals(type, start: start, end: end).values.toList(growable: false);
    if (totals.isEmpty) return 0;
    return totals.reduce((a, b) => a + b) / totals.length;
  }

  double averagePerWeek(
    TransactionType type, {
    DateTime? start,
    DateTime? end,
  }) {
    final totals =
        weeklyTotals(type, start: start, end: end).values.toList(growable: false);
    if (totals.isEmpty) return 0;
    return totals.reduce((a, b) => a + b) / totals.length;
  }

  Map<String, double> expenseTotalsByCategory({
    DateTime? start,
    DateTime? end,
  }) {
    final map = <String, double>{};
    for (final entry
        in _filteredEntries(TransactionType.expense, start: start, end: end)) {
      final key = entry.category ?? '其他';
      map.update(key, (value) => value + entry.amount,
          ifAbsent: () => entry.amount);
    }
    return map;
  }

  List<MoneyEntry> entriesByType(
    TransactionType type, {
    DateTime? start,
    DateTime? end,
  }) {
    return List<MoneyEntry>.unmodifiable(
      _filteredEntries(type, start: start, end: end),
    );
  }
}

