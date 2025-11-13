import 'package:flutter/material.dart';

import 'data/datasources/hive_data_store.dart';
import 'data/models/category_settings.dart';
import 'data/models/currency_settings.dart';
import 'data/models/goal.dart';
import 'data/repositories/mock_money_repository.dart';
import 'features/transactions/presentation/add_transaction_sheet.dart';
import 'features/dashboard/presentation/dashboard_page.dart';
import 'features/progress/presentation/goal_progress_page.dart';
import 'features/settings/presentation/settings_page.dart';
import 'features/transactions/presentation/transactions_page.dart';
import 'data/models/money_entry.dart';
import 'data/models/transaction_type.dart';

class MoneyTargetApp extends StatefulWidget {
  const MoneyTargetApp({
    super.key,
    required this.initialRepository,
    required this.dataStore,
  });

  final MockMoneyRepository initialRepository;
  final MoneyDataStore dataStore;

  @override
  State<MoneyTargetApp> createState() => _MoneyTargetAppState();
}

class _MoneyTargetAppState extends State<MoneyTargetApp> {
  late MockMoneyRepository _repository;
  late CurrencySettings _currencySettings;
  int _selectedIndex = 0;
  final GlobalKey<TransactionsPageState> _transactionsPageKey =
      GlobalKey<TransactionsPageState>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  TransactionType _currentTransactionType = TransactionType.income;

  @override
  void initState() {
    super.initState();
    _repository = widget.initialRepository;
    _currencySettings = widget.dataStore.currencySettings;
    _pruneFutureEntries();
  }

  Future<void> _pruneFutureEntries() async {
    final cutoff = DateTime(2025, 11, 30, 23, 59, 59);
    final filtered =
        _repository.entries.where((e) => !e.date.isAfter(cutoff)).toList();
    if (filtered.length == _repository.entries.length) return;

    setState(() {
      _repository = _repository.copyWith(entries: filtered);
    });
    await widget.dataStore.saveEntries(filtered);
  }

  Future<void> _updateGoal(Goal goal) async {
    await widget.dataStore.saveGoal(goal);
    if (!mounted) return;
    setState(() {
      _repository = _repository.copyWith(goal: goal);
    });
  }

  Future<void> _updateCategories(CategorySettings settings) async {
    await widget.dataStore.saveCategories(settings);
    if (!mounted) return;
    setState(() {
      _repository = _repository.copyWith(categorySettings: settings);
    });
  }

  Future<void> _addCategoryValue(TransactionType type, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final updated = _repository.categorySettings.addValue(type, trimmed);
    await _updateCategories(updated);
  }

  Future<void> _updateCurrency(CurrencySettings settings) async {
    await widget.dataStore.saveCurrencySettings(settings);
    if (!mounted) return;
    setState(() {
      _currencySettings = settings;
    });
  }

  Future<Map<String, dynamic>> _exportData() {
    return widget.dataStore.exportData();
  }

  Future<void> _importData(Map<String, dynamic> data) async {
    await widget.dataStore.importData(data);
    if (!mounted) return;
    final refreshed = widget.dataStore.toRepository();
    setState(() {
      _repository = refreshed;
      _currencySettings = widget.dataStore.currencySettings;
    });
  }

  Future<void> _addEntry(MoneyEntry entry) async {
    final updatedEntries = [..._repository.entries, entry]
      ..sort((a, b) => a.date.compareTo(b.date));
    setState(() {
      _repository = _repository.copyWith(entries: updatedEntries);
    });
    await widget.dataStore.upsertEntry(entry);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _transactionsPageKey.currentState?.handleEntryAdded(entry);
    });
  }

  Future<void> _updateEntry(MoneyEntry entry) async {
    final updatedEntries = _repository.entries.toList();
    final index = updatedEntries.indexWhere((e) => e.id == entry.id);
    if (index == -1) return;
    updatedEntries[index] = entry;
    updatedEntries.sort((a, b) => a.date.compareTo(b.date));

    setState(() {
      _repository = _repository.copyWith(entries: updatedEntries);
    });
    await widget.dataStore.upsertEntry(entry);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _transactionsPageKey.currentState?.handleEntryAdded(entry);
    });
  }

  Future<void> _deleteEntry(MoneyEntry entry) async {
    final updatedEntries =
        _repository.entries.where((e) => e.id != entry.id).toList();
    setState(() {
      _repository = _repository.copyWith(entries: updatedEntries);
    });
    await widget.dataStore.deleteEntry(entry.id);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _transactionsPageKey.currentState?.handleEntryRemoved(entry);
    });
  }

  Future<void> _showAddEntrySheet([MoneyEntry? entry]) async {
    final scaffoldContext = _scaffoldKey.currentContext;
    if (scaffoldContext == null) return;

    final result = await showModalBottomSheet<MoneyEntry>(
      context: scaffoldContext,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (context) => AddTransactionSheet(
        initialType: entry?.type ?? _currentTransactionType,
        initialEntry: entry,
        incomeSources: _repository.incomeSources,
        savingSources: _repository.savingSources,
        expenseCategories: _repository.expenseCategories,
        onCreateCategory: _addCategoryValue,
        currencySettings: _currencySettings,
      ),
    );
    if (result != null) {
      if (entry == null) {
        await _addEntry(result);
      } else {
        await _updateEntry(result);
      }
    }
  }

  Future<void> _confirmDelete(MoneyEntry entry) async {
    final scaffoldContext = _scaffoldKey.currentContext;
    if (scaffoldContext == null) return;

    final shouldDelete = await showDialog<bool>(
      context: scaffoldContext,
      builder: (context) => AlertDialog(
        title: const Text('刪除紀錄'),
        content: const Text('確認要刪除這筆紀錄嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (shouldDelete == true) {
      await _deleteEntry(entry);
    }
  }

  @override
  Widget build(BuildContext context) {
                return MaterialApp(
                  title: 'MoneyTarget',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Text(_titleForIndex(_selectedIndex)),
        ),
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            DashboardPage(
              repository: _repository,
              currencySettings: _currencySettings,
            ),
            GoalProgressPage(
              repository: _repository,
              currencySettings: _currencySettings,
            ),
            TransactionsPage(
              key: _transactionsPageKey,
              repository: _repository,
              currencySettings: _currencySettings,
              onTabChanged: (type) {
                _currentTransactionType = type;
              },
              onRequestEdit: (entry) => _showAddEntrySheet(entry),
              onRequestDelete: _confirmDelete,
            ),
            SettingsPage(
              repository: _repository,
              onUpdateGoal: _updateGoal,
              onUpdateCategories: _updateCategories,
              currencySettings: _currencySettings,
              onUpdateCurrency: _updateCurrency,
              onExportData: _exportData,
              onImportData: _importData,
            ),
          ],
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: _selectedIndex == 2
            ? FloatingActionButton.extended(
                onPressed: () => _showAddEntrySheet(),
                icon: const Icon(Icons.add),
                label: const Text('新增紀錄'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: '儀表板',
            ),
            NavigationDestination(
              icon: Icon(Icons.stacked_line_chart_outlined),
              selectedIcon: Icon(Icons.stacked_line_chart),
              label: '達標',
            ),
            NavigationDestination(
              icon: Icon(Icons.list_alt_outlined),
              selectedIcon: Icon(Icons.list_alt),
              label: '記錄',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: '設定',
            ),
          ],
          onDestinationSelected: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
        ),
      ),
    );
  }

  String _titleForIndex(int index) {
    switch (index) {
      case 0:
        return '儀表板';
      case 1:
        return '達標狀況';
      case 2:
        return '記錄';
      case 3:
        return '設定';
      default:
                    return 'MoneyTarget';
    }
  }
}

