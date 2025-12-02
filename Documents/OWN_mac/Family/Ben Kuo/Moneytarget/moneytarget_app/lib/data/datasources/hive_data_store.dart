import 'package:hive/hive.dart';

import '../models/category_settings.dart';
import '../models/currency_settings.dart';
import '../models/goal.dart';
import '../models/money_entry.dart';
import '../models/transaction_type.dart';
import '../repositories/mock_money_repository.dart';

abstract class MoneyDataStore {
  MockMoneyRepository toRepository();
  Future<void> saveGoal(Goal goal);
  Future<void> saveEntries(Iterable<MoneyEntry> items);
  Future<void> upsertEntry(MoneyEntry entry);
  Future<void> deleteEntry(String id);
  CategorySettings get categories;
  Future<void> saveCategories(CategorySettings settings);
  CurrencySettings get currencySettings;
  Future<void> saveCurrencySettings(CurrencySettings settings);
  Future<Map<String, dynamic>> exportData();
  Future<void> importData(Map<String, dynamic> data);
}

class HiveDataStore implements MoneyDataStore {
  HiveDataStore._(
    this._goalBox,
    this._entryBox,
    this._categoryBox,
    this._currencyBox,
  );

  static const String _goalKey = 'goal';
  static const String _categoryKey = 'categories';
  static const String _currencyKey = 'currency';
  static const String _initializedKey = '_initialized';

  final Box<Goal> _goalBox;
  final Box<MoneyEntry> _entryBox;
  final Box<CategorySettings> _categoryBox;
  final Box<CurrencySettings> _currencyBox;

  static Future<HiveDataStore> load() async {
    final goalBox = await Hive.openBox<Goal>('goal');
    final entryBox = await Hive.openBox<MoneyEntry>('entries');
    final categoryBox = await Hive.openBox<CategorySettings>('category_settings');
    final currencyBox = await Hive.openBox<CurrencySettings>('currency_settings');
    final appSettingsBox = await Hive.openBox('app_settings');

    // 只在第一次安裝時初始化 mock 數據
    // 使用專門的初始化標記，避免刪除資料後重新初始化
    if (!appSettingsBox.containsKey(_initializedKey)) {
      final mock = MockMoneyRepository.generate();
      await goalBox.put(_goalKey, mock.goal);
      await entryBox.clear();
      for (final entry in mock.entries) {
        await entryBox.put(entry.id, entry);
      }
      await categoryBox.put(_categoryKey, mock.categorySettings);
      await currencyBox.put(_currencyKey, CurrencySettings.defaults());
      // 標記已經初始化過
      await appSettingsBox.put(_initializedKey, true);
    } else {
      // 已經初始化過，只檢查並補齊可能缺失的類別和貨幣設置
      if (!categoryBox.containsKey(_categoryKey)) {
        await categoryBox.put(_categoryKey, CategorySettings.defaults());
      }
      if (!currencyBox.containsKey(_currencyKey)) {
        await currencyBox.put(_currencyKey, CurrencySettings.defaults());
      }
    }

    return HiveDataStore._(goalBox, entryBox, categoryBox, currencyBox);
  }

  Goal get goal => _goalBox.get(_goalKey)!;

  List<MoneyEntry> get entries {
    final items = _entryBox.values.toList();
    items.sort((a, b) => a.date.compareTo(b.date));
    return items;
  }

  @override
  CategorySettings get categories =>
      _categoryBox.get(_categoryKey) ?? CategorySettings.defaults();

  @override
  CurrencySettings get currencySettings =>
      _currencyBox.get(_currencyKey) ?? CurrencySettings.defaults();

  @override
  MockMoneyRepository toRepository() {
    return MockMoneyRepository(
      goal: goal,
      entries: entries,
      categorySettings: categories,
    );
  }

  @override
  Future<void> saveGoal(Goal goal) async {
    await _goalBox.put(_goalKey, goal);
  }

  @override
  Future<void> saveEntries(Iterable<MoneyEntry> items) async {
    await _entryBox.clear();
    for (final entry in items) {
      await _entryBox.put(entry.id, entry);
    }
  }

  @override
  Future<void> upsertEntry(MoneyEntry entry) async {
    await _entryBox.put(entry.id, entry);
  }

  @override
  Future<void> deleteEntry(String id) async {
    await _entryBox.delete(id);
  }

  @override
  Future<void> saveCategories(CategorySettings settings) async {
    await _categoryBox.put(_categoryKey, settings);
  }

  @override
  Future<void> saveCurrencySettings(CurrencySettings settings) async {
    await _currencyBox.put(_currencyKey, settings);
  }

  @override
  Future<Map<String, dynamic>> exportData() async {
    return {
      'goal': {
        'targetAmount': goal.targetAmount,
        'startDate': goal.startDate.toIso8601String(),
        'endDate': goal.endDate.toIso8601String(),
      },
      'entries': entries
          .map((entry) => {
                'id': entry.id,
                'type': entry.type.name,
                'amount': entry.amount,
                'date': entry.date.toIso8601String(),
                'source': entry.source,
                'category': entry.category,
                'note': entry.note,
              })
          .toList(),
      'categories': {
        'income': categories.incomeSources,
        'saving': categories.savingSources,
        'expense': categories.expenseCategories,
      },
      'currency': {
        'selected': currencySettings.selectedCurrency.index,
        'audToTwdRate': currencySettings.audToTwdRate,
      },
    };
  }

  @override
  Future<void> importData(Map<String, dynamic> data) async {
    if (data['goal'] case final Map<String, dynamic> goalMap) {
      final importedGoal = Goal(
        targetAmount: (goalMap['targetAmount'] as num).toDouble(),
        startDate: DateTime.parse(goalMap['startDate'] as String),
        endDate: DateTime.parse(goalMap['endDate'] as String),
      );
      await saveGoal(importedGoal);
    }

    if (data['entries'] case final List entriesList) {
      final importedEntries = entriesList.map((raw) {
        final map = raw as Map<String, dynamic>;
        return MoneyEntry(
          id: map['id'] as String,
          type: TransactionType.values
              .firstWhere((element) => element.name == map['type']),
          amount: (map['amount'] as num).toDouble(),
          date: DateTime.parse(map['date'] as String),
          source: map['source'] as String?,
          category: map['category'] as String?,
          note: map['note'] as String?,
        );
      }).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      await saveEntries(importedEntries);
    }

    if (data['categories'] case final Map<String, dynamic> categoriesMap) {
      final importedCategories = CategorySettings(
        incomeSources:
            (categoriesMap['income'] as List).cast<String>(),
        savingSources:
            (categoriesMap['saving'] as List).cast<String>(),
        expenseCategories:
            (categoriesMap['expense'] as List).cast<String>(),
      );
      await saveCategories(importedCategories);
    }

    if (data['currency'] case final Map<String, dynamic> currencyMap) {
      final selectedIndex = currencyMap['selected'] as int? ?? 0;
      final importedCurrency = CurrencySettings(
        selectedCurrency: Currency.values[selectedIndex.clamp(0, Currency.values.length - 1)],
        audToTwdRate: (currencyMap['audToTwdRate'] as num?)?.toDouble() ??
            CurrencySettings.defaults().audToTwdRate,
      );
      await saveCurrencySettings(importedCurrency);
    }
  }
}

