import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';

import '../../../data/models/currency_settings.dart';
import '../../../data/models/money_entry.dart';
import '../../../data/models/transaction_type.dart';
import '../../../data/repositories/mock_money_repository.dart';

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

enum RangeFilterType { all, untilNow, last30Days, month, week, custom }

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({
    super.key,
    required this.repository,
    required this.currencySettings,
    this.onTabChanged,
    this.onRequestEdit,
    this.onRequestDelete,
  });

  final MockMoneyRepository repository;
  final CurrencySettings currencySettings;
  final ValueChanged<TransactionType>? onTabChanged;
  final ValueChanged<MoneyEntry>? onRequestEdit;
  final ValueChanged<MoneyEntry>? onRequestDelete;

  @override
  State<TransactionsPage> createState() => TransactionsPageState();
}

class TransactionsPageState extends State<TransactionsPage>
    with SingleTickerProviderStateMixin {
  CurrencySettings get currencySettings => widget.currencySettings;

  late final TabController _tabController;
  RangeFilterType _filterType = RangeFilterType.untilNow;
  DateTimeRange? _selectedRange;
  String? _customLabel;
  bool _calendarMode = false;
  DateTime _selectedDate = DateTime.now();
  PageController? _calendarController;
  List<DateTime> _calendarMonths = [];
  Set<DateTime> _entryDates = {};
  DateTime? _calendarRangeStart;
  DateTime? _calendarRangeEnd;
  Map<DateTime, int> _calendarRows = {};
  Map<DateTime, _DailyTotals> _dailyTotals = {};
  bool _filterCollapsed = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      widget.onTabChanged?.call(_typeForIndex(_tabController.index));
      setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onTabChanged?.call(_typeForIndex(_tabController.index));
    });
    _setUntilNowRange(initial: true);
    _selectedDate =
        _normalizeDate(_selectedRange?.end ?? DateTime.now());
    _rebuildCalendarData();
  }

  @override
  void didUpdateWidget(covariant TransactionsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository &&
        _filterType == RangeFilterType.untilNow) {
      setState(() {
        _setUntilNowRange();
        _selectedDate =
            _normalizeDate(_selectedRange?.end ?? DateTime.now());
        _rebuildCalendarData();
      });
    } else if (oldWidget.repository != widget.repository) {
      setState(_rebuildCalendarData);
    }
  }

  @override
  void dispose() {
    _calendarController?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void handleEntryAdded(MoneyEntry entry) {
    setState(() {
      _selectedDate = _normalizeDate(entry.date);
      _rebuildCalendarData();
    });
  }

  void handleEntryRemoved(MoneyEntry entry) {
    setState(() {
      _rebuildCalendarData();
      if (_calendarMode && _dailyTotals[_selectedDate] == null) {
        _selectedDate = _normalizeDate(entry.date);
      }
    });
  }

  TransactionType _typeForIndex(int index) {
    switch (index) {
      case 0:
        return TransactionType.income;
      case 1:
        return TransactionType.saving;
      case 2:
        return TransactionType.expense;
      default:
        return TransactionType.income;
    }
  }

  String _formatAmount(double value) {
    final displayValue = currencySettings.toDisplay(value);
    if (displayValue == 0) return '0';
    if (currencySettings.selectedCurrency == Currency.twd) {
      if (displayValue >= 10000) {
        final amount = displayValue / 10000;
        return '${amount.toStringAsFixed(0)}萬';
      }
      if (displayValue >= 1000) {
        final amount = displayValue / 1000;
        return '${amount.toStringAsFixed(0)}千';
      }
      return displayValue.toStringAsFixed(0);
    }
    if (displayValue >= 1000) {
      final amount = displayValue / 1000;
      return '${amount.toStringAsFixed(0)}k';
    }
    return displayValue.toStringAsFixed(0);
  }

  DateTime _normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  void _rebuildCalendarData() {
    _calendarController?.dispose();
    final entries = widget.repository.entries;
    if (entries.isEmpty) {
      _calendarMonths = [];
      _entryDates = {};
      _calendarController = null;
      _calendarRangeStart = null;
      _calendarRangeEnd = null;
      _calendarRows = {};
      return;
    }

    final normalizedEntries =
        entries.map((entry) => _normalizeDate(entry.date)).toList();
    normalizedEntries.sort();
    _entryDates = normalizedEntries.toSet();

    final minDate = normalizedEntries.first;
    final maxDate = normalizedEntries.last;
    final bool useFilterRange = !_calendarMode && _selectedRange != null;
    final rangeStart = useFilterRange ? _selectedRange!.start : minDate;
    final rangeEnd = useFilterRange ? _selectedRange!.end : maxDate;
    _calendarRangeStart = _normalizeDate(rangeStart);
    _calendarRangeEnd = _normalizeDate(rangeEnd);

    if (_calendarRangeStart!.isAfter(_calendarRangeEnd!)) {
      _calendarRangeStart = _calendarRangeEnd;
    }

    if (_selectedDate.isBefore(_calendarRangeStart!)) {
      _selectedDate = _calendarRangeStart!;
    }
    if (_selectedDate.isAfter(_calendarRangeEnd!)) {
      _selectedDate = _calendarRangeEnd!;
    }

    _dailyTotals = {};
    final rangeStartNormalized = _calendarRangeStart!;
    final rangeEndNormalized = _calendarRangeEnd!;
    for (final entry in entries) {
      final normalized = _normalizeDate(entry.date);
      if (normalized.isBefore(rangeStartNormalized) ||
          normalized.isAfter(rangeEndNormalized)) {
        continue;
      }
      final totals =
          _dailyTotals.putIfAbsent(normalized, () => _DailyTotals());
      totals.add(entry);
    }

    final months = <DateTime>[];
    var current = DateTime(_calendarRangeStart!.year, _calendarRangeStart!.month);
    final lastMonth =
        DateTime(_calendarRangeEnd!.year, _calendarRangeEnd!.month);
    _calendarRows = {};
    while (!current.isAfter(lastMonth)) {
      months.add(current);
      _calendarRows[current] = _rowsForMonth(current);
      current = current.month == 12
          ? DateTime(current.year + 1, 1)
          : DateTime(current.year, current.month + 1);
    }
    _calendarMonths = months;

    final initialIndex = months.indexWhere(
      (month) =>
          month.year == _selectedDate.year && month.month == _selectedDate.month,
    );
    final pageIndex = initialIndex >= 0 ? initialIndex : months.length - 1;
    _calendarController = PageController(initialPage: pageIndex);
  }

  int _rowsForMonth(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final startOffset = (firstDay.weekday + 6) % 7;
    final totalCells = startOffset + daysInMonth;
    return (totalCells / 7).ceil();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('列表'),
                icon: Icon(Icons.view_list),
              ),
              ButtonSegment(
                value: true,
                label: Text('日曆'),
                icon: Icon(Icons.calendar_today),
              ),
            ],
            selected: {_calendarMode},
            onSelectionChanged: (selection) {
              setState(() {
                _calendarMode = selection.first;
                if (_calendarMode) {
                  _filterCollapsed = false;
                  _selectedRange = null;
                  _customLabel = null;
                } else {
                  _filterCollapsed = false;
                }
                _rebuildCalendarData();
              });
            },
          ),
        ),
        if (_calendarMode) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '日曆模式顯示全部紀錄，點擊日期切換至列表',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: _buildCalendar(),
            ),
          ),
        ] else ...[
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _filterCollapsed
                ? const SizedBox.shrink()
                : _FilterBar(
                    filterType: _filterType,
                    rangeLabel: _currentRangeLabel(),
                    onFilterSelected: _handleFilterSelected,
                  ),
          ),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '收入'),
              Tab(text: '存錢'),
              Tab(text: '支出'),
            ],
          ),
          Expanded(
            child: NotificationListener<UserScrollNotification>(
              onNotification: (notification) {
                final direction = notification.direction;
                if (direction == ScrollDirection.reverse && !_filterCollapsed) {
                  setState(() => _filterCollapsed = true);
                } else if (direction == ScrollDirection.forward &&
                    _filterCollapsed) {
                  setState(() => _filterCollapsed = false);
                }
                return false;
              },
              child: TabBarView(
                controller: _tabController,
                children: [
                  _TransactionsList(
                    entries: _filteredEntries(TransactionType.income),
                    currencySettings: currencySettings,
                    placeholderFields: const ['來源', '備註'],
                    selectedDate: _calendarMode ? _selectedDate : null,
                    onEdit: widget.onRequestEdit,
                    onDelete: widget.onRequestDelete,
                  ),
                  _TransactionsList(
                    entries: _filteredEntries(TransactionType.saving),
                    currencySettings: currencySettings,
                    placeholderFields: const ['來源', '備註'],
                    selectedDate: _calendarMode ? _selectedDate : null,
                    onEdit: widget.onRequestEdit,
                    onDelete: widget.onRequestDelete,
                  ),
                  _TransactionsList(
                    entries: _filteredEntries(TransactionType.expense),
                    currencySettings: currencySettings,
                    placeholderFields: const ['類別', '備註'],
                    selectedDate: _calendarMode ? _selectedDate : null,
                    onEdit: widget.onRequestEdit,
                    onDelete: widget.onRequestDelete,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<MoneyEntry> _filteredEntries(TransactionType type) {
    final range = _selectedRange;
    return widget.repository.entriesByType(
      type,
      start: range?.start,
      end: range?.end,
    );
  }

  void _handleFilterSelected(RangeFilterType type) {
    if (_calendarMode) {
      return;
    }
    if (type == _filterType && type != RangeFilterType.custom) {
      return;
    }

    switch (type) {
      case RangeFilterType.all:
        setState(() {
          _filterType = type;
          _selectedRange = null;
          _customLabel = null;
          _selectedDate = _normalizeDate(DateTime.now());
          _rebuildCalendarData();
        });
        break;
      case RangeFilterType.untilNow:
        setState(() {
          _filterType = RangeFilterType.untilNow;
          _setUntilNowRange();
          _selectedDate =
              _normalizeDate(_selectedRange?.end ?? DateTime.now());
          _rebuildCalendarData();
        });
        break;
      case RangeFilterType.last30Days:
        final now = DateTime.now();
        final range = DateTimeRange(
          start: DateTime(now.year, now.month, now.day)
              .subtract(const Duration(days: 29)),
          end: DateTime(now.year, now.month, now.day),
        );
        setState(() {
          _filterType = type;
          _selectedRange = range;
          _customLabel = null;
          _selectedDate = _normalizeDate(range.end);
          _rebuildCalendarData();
        });
        break;
      case RangeFilterType.month:
        _selectMonthFromSheet();
        break;
      case RangeFilterType.week:
        _selectWeekFromSheet();
        break;
      case RangeFilterType.custom:
        _pickCustomRange();
        break;
    }
  }

  void _setUntilNowRange({bool initial = false}) {
    final entries = widget.repository.entries;
    if (entries.isEmpty) {
      _selectedRange = null;
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
    _selectedRange = DateTimeRange(start: earliest, end: normalizedToday);
    _customLabel = null;
  }

  Future<void> _selectMonthFromSheet() async {
    final months = _availableMonths();
    if (months.isEmpty) {
      return;
    }

    final context = this.context;
    final selected = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (context) => _SelectionSheet<DateTime>(
        title: '選擇月份',
        items: months,
        itemBuilder: (value) => DateFormat.yMMM('zh_TW').format(value),
        isSelected: (value) =>
            _filterType == RangeFilterType.month &&
            _selectedRange != null &&
            _selectedRange!.start.year == value.year &&
            _selectedRange!.start.month == value.month,
      ),
    );

    if (selected == null) return;

    final start = DateTime(selected.year, selected.month, 1);
    final end = DateTime(selected.year, selected.month + 1, 0);
    setState(() {
      _filterType = RangeFilterType.month;
      _selectedRange = DateTimeRange(start: start, end: end);
      _customLabel = DateFormat.yMMM('zh_TW').format(start);
      _selectedDate = _normalizeDate(end);
      _rebuildCalendarData();
    });
  }

  Future<void> _selectWeekFromSheet() async {
    final weeks = _availableWeeks();
    if (weeks.isEmpty) {
      return;
    }

    final context = this.context;
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
            _filterType == RangeFilterType.week &&
            _selectedRange != null &&
            _selectedRange!.start == value,
      ),
    );

    if (selected == null) return;

    final end = selected.add(const Duration(days: 6));
    setState(() {
      _filterType = RangeFilterType.week;
      _selectedRange = DateTimeRange(start: selected, end: end);
      _customLabel =
          '${DateFormat.Md('zh_TW').format(selected)} - ${DateFormat.Md('zh_TW').format(end)}';
      _selectedDate = _normalizeDate(end);
      _rebuildCalendarData();
    });
  }

  Future<void> _pickCustomRange() async {
    final context = this.context;
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 6)),
            end: DateTime.now(),
          ),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;

    setState(() {
      _filterType = RangeFilterType.custom;
      _selectedRange = DateTimeRange(
        start: DateTime(picked.start.year, picked.start.month, picked.start.day),
        end: DateTime(picked.end.year, picked.end.month, picked.end.day),
      );
      _customLabel =
          '${DateFormat.yMd('zh_TW').format(picked.start)} - ${DateFormat.yMd('zh_TW').format(picked.end)}';
      _selectedDate = _normalizeDate(_selectedRange!.end);
      _rebuildCalendarData();
    });
  }

  String _currentRangeLabel() {
    if (_calendarMode) {
      return '顯示全部';
    }
    switch (_filterType) {
      case RangeFilterType.all:
        return '顯示全部';
      case RangeFilterType.untilNow:
        if (_selectedRange == null) return '顯示全部';
        return '至今：${DateFormat.yMd('zh_TW').format(_selectedRange!.start)} - ${DateFormat.yMd('zh_TW').format(_selectedRange!.end)}';
      case RangeFilterType.last30Days:
        return '最近 30 日';
      case RangeFilterType.month:
      case RangeFilterType.week:
      case RangeFilterType.custom:
        if (_customLabel == null) return '已選日期範圍';
        return '自訂：$_customLabel';
    }
  }

  List<DateTime> _availableMonths() {
    final set = <DateTime>{};
    for (final entry in widget.repository.entries) {
      set.add(DateTime(entry.date.year, entry.date.month));
    }
    final list = set.toList()
      ..sort((a, b) => b.compareTo(a)); // recent first
    return list;
  }

  List<DateTime> _availableWeeks() {
    final set = <DateTime>{};
    for (final entry in widget.repository.entries) {
      final start = entry.date.subtract(Duration(days: entry.date.weekday - 1));
      set.add(DateTime(start.year, start.month, start.day));
    }
    final list = set.toList()
      ..sort((a, b) => b.compareTo(a));
    return list;
  }

  Widget _buildCalendar() {
    if (_calendarController == null ||
        _calendarMonths.isEmpty ||
        _calendarRangeStart == null ||
        _calendarRangeEnd == null) {
      return const Center(child: Text('目前沒有資料可顯示'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxRows = _calendarRows.values.isEmpty
            ? 6
            : _calendarRows.values.reduce(math.max);
        final availableHeight =
            constraints.hasBoundedHeight ? constraints.maxHeight : 520;
        final headerHeight = 132.0;
        final rowHeight =
            ((availableHeight - headerHeight) / maxRows).clamp(84.0, 132.0);

        return PageView.builder(
          controller: _calendarController,
          scrollDirection: Axis.vertical,
          itemCount: _calendarMonths.length,
          onPageChanged: (index) {
            final month = _calendarMonths[index];
            setState(() {
              if (_selectedDate.year != month.year ||
                  _selectedDate.month != month.month) {
                final daysInMonth =
                    DateUtils.getDaysInMonth(month.year, month.month);
                final clampedDay =
                    _selectedDate.day.clamp(1, daysInMonth);
                _selectedDate =
                    _normalizeDate(DateTime(month.year, month.month, clampedDay));
              }
            });
          },
          itemBuilder: (context, index) {
            final month = _calendarMonths[index];
            return _CalendarMonthView(
              month: month,
              selectedDate: _selectedDate,
              rangeStart: _calendarRangeStart!,
              rangeEnd: _calendarRangeEnd!,
              entryDates: _entryDates,
              rowHeight: rowHeight,
              onDateSelected: _handleCalendarDateSelected,
              totalsResolver: (date) => _dailyTotals[date],
              formatAmount: _formatAmount,
            );
          },
        );
      },
    );
  }

  void _handleCalendarDateSelected(DateTime date) {
    final normalized = _normalizeDate(date);
    setState(() {
      _calendarMode = false;
      _filterCollapsed = false;
      _filterType = RangeFilterType.custom;
      _selectedRange = DateTimeRange(start: normalized, end: normalized);
      _customLabel = DateFormat.yMd('zh_TW').format(normalized);
      _selectedDate = normalized;
      _rebuildCalendarData();
    });
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filterType,
    required this.rangeLabel,
    required this.onFilterSelected,
  });

  final RangeFilterType filterType;
  final String rangeLabel;
  final ValueChanged<RangeFilterType> onFilterSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '篩選日期',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _FilterChip(
                  label: '全部',
                  selected: filterType == RangeFilterType.all,
                  onSelected: () => onFilterSelected(RangeFilterType.all),
                ),
                _FilterChip(
                  label: '至今',
                  selected: filterType == RangeFilterType.untilNow,
                  onSelected: () => onFilterSelected(RangeFilterType.untilNow),
                ),
                _FilterChip(
                  label: '最近30日',
                  selected: filterType == RangeFilterType.last30Days,
                  onSelected: () =>
                      onFilterSelected(RangeFilterType.last30Days),
                ),
                _FilterChip(
                  label: '月份',
                  selected: filterType == RangeFilterType.month,
                  onSelected: () => onFilterSelected(RangeFilterType.month),
                ),
                _FilterChip(
                  label: '週',
                  selected: filterType == RangeFilterType.week,
                  onSelected: () => onFilterSelected(RangeFilterType.week),
                ),
                _FilterChip(
                  label: '自訂',
                  selected: filterType == RangeFilterType.custom,
                  onSelected: () => onFilterSelected(RangeFilterType.custom),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              rangeLabel,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarMonthView extends StatelessWidget {
  const _CalendarMonthView({
    required this.month,
    required this.selectedDate,
    required this.rangeStart,
    required this.rangeEnd,
    required this.entryDates,
    required this.rowHeight,
    required this.onDateSelected,
    required this.totalsResolver,
    required this.formatAmount,
  });

  final DateTime month;
  final DateTime selectedDate;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final Set<DateTime> entryDates;
  final double rowHeight;
  final ValueChanged<DateTime> onDateSelected;
  final _DailyTotals? Function(DateTime date) totalsResolver;
  final String Function(double value) formatAmount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weeks = _buildWeeks();
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            DateFormat.yMMMM('zh_TW').format(month),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Row(
            children: weekdays
                .map(
                  (weekday) => Expanded(
                    child: Center(
                      child: Text(
                        weekday,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < weeks.length; i++) ...[
            Row(
              children: weeks[i]
                  .map(
                    (date) => Expanded(
                      child: _CalendarDayCell(
                        date: date,
                        selectedDate: selectedDate,
                        rangeStart: rangeStart,
                        rangeEnd: rangeEnd,
                        entryDates: entryDates,
                        rowHeight: rowHeight,
                        onTap: onDateSelected,
                        totals: date == null ? null : totalsResolver(date),
                        formatAmount: formatAmount,
                      ),
                    ),
                  )
                  .toList(),
            ),
            if (i != weeks.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  List<List<DateTime?>> _buildWeeks() {
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final startOffset = (firstDay.weekday + 6) % 7;

    final days = <DateTime?>[];
    days.addAll(List<DateTime?>.filled(startOffset, null));

    for (var day = 1; day <= daysInMonth; day++) {
      days.add(DateTime(month.year, month.month, day));
    }

    while (days.length % 7 != 0) {
      days.add(null);
    }

    final weeks = <List<DateTime?>>[];
    for (var i = 0; i < days.length; i += 7) {
      weeks.add(days.sublist(i, i + 7));
    }
    return weeks;
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.date,
    required this.selectedDate,
    required this.rangeStart,
    required this.rangeEnd,
    required this.entryDates,
    required this.rowHeight,
    required this.onTap,
    required this.totals,
    required this.formatAmount,
  });

  final DateTime? date;
  final DateTime selectedDate;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final Set<DateTime> entryDates;
  final double rowHeight;
  final ValueChanged<DateTime> onTap;
  final _DailyTotals? totals;
  final String Function(double value) formatAmount;

  @override
  Widget build(BuildContext context) {
    if (date == null) {
      return SizedBox(height: rowHeight);
    }

    final theme = Theme.of(context);
    final isDisabled =
        date!.isBefore(rangeStart) || date!.isAfter(rangeEnd);
    final isSelected = _isSameDay(date!, selectedDate);
    final hasEntry = !isDisabled && entryDates.contains(date);
    final hasTotals = totals?.hasData ?? false;

    final baseStyle = theme.textTheme.bodyMedium;
    final textColor = isDisabled
        ? theme.disabledColor
        : (isSelected ? theme.colorScheme.onPrimary : baseStyle?.color);

    final borderRadius = BorderRadius.circular(12);

    return SizedBox(
      height: rowHeight,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: isDisabled ? null : () => onTap(date!),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 36,
                decoration: BoxDecoration(
                  color:
                      isSelected ? theme.colorScheme.primary : Colors.transparent,
                  borderRadius: borderRadius,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${date!.day}',
                  style: baseStyle?.copyWith(color: textColor),
                ),
              ),
              if (hasTotals) ...[
                const SizedBox(height: 0),
                if (totals!.income > 0)
                  Text(
                    '入 ${formatAmount(totals!.income)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                if (totals!.saving > 0)
                  Text(
                    '存 ${formatAmount(totals!.saving)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                if (totals!.expense > 0)
                  Text(
                    '支 ${formatAmount(totals!.expense)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.error,
                    ),
                  ),
              ] else ...[
                const SizedBox(height: 6),
                SizedBox(
                  height: 6,
                  width: 6,
                  child: hasEntry
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyTotals {
  double income = 0;
  double saving = 0;
  double expense = 0;

  bool get hasData => income > 0 || saving > 0 || expense > 0;

  void add(MoneyEntry entry) {
    switch (entry.type) {
      case TransactionType.income:
        income += entry.amount;
        break;
      case TransactionType.saving:
        saving += entry.amount;
        break;
      case TransactionType.expense:
        expense += entry.amount;
        break;
    }
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
                  trailing:
                      selected ? const Icon(Icons.check, color: Colors.teal) : null,
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
    final theme = Theme.of(context);
    return FilterChip(
      label: Text(
        label,
        style: theme.textTheme.labelSmall,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      selected: selected,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (_) => onSelected(),
    );
  }
}

class _TransactionsList extends StatelessWidget {
  const _TransactionsList({
    required this.entries,
    required this.currencySettings,
    required this.placeholderFields,
    this.selectedDate,
    this.onEdit,
    this.onDelete,
  });

  final List<MoneyEntry> entries;
  final CurrencySettings currencySettings;
  final List<String> placeholderFields;
  final DateTime? selectedDate;
  final ValueChanged<MoneyEntry>? onEdit;
  final ValueChanged<MoneyEntry>? onDelete;

  @override
  Widget build(BuildContext context) {
    final list = selectedDate == null
        ? entries
        : entries.where((entry) => _isSameDay(entry.date, selectedDate!)).toList();

    if (list.isEmpty) {
      return const Center(child: Text('目前沒有資料'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = list[index];
        return Card(
          child: ListTile(
            title: Text(currencySettings.format(entry.amount)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat.yMMMd().format(entry.date)),
                if (entry.source != null)
                  Text('${placeholderFields.first}: ${entry.source}'),
                if (entry.category != null)
                  Text('${placeholderFields.first}: ${entry.category}'),
                if (entry.note != null && entry.note!.isNotEmpty)
                  Text('${placeholderFields.last}: ${entry.note}'),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => onEdit?.call(entry),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => onDelete?.call(entry),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

