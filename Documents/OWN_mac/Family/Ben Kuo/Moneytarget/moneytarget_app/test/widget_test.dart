// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:moneytarget_app/app.dart';
import 'package:moneytarget_app/data/datasources/hive_data_store.dart';
import 'package:moneytarget_app/data/models/category_settings.dart';
import 'package:moneytarget_app/data/models/currency_settings.dart';
import 'package:moneytarget_app/data/models/goal.dart';
import 'package:moneytarget_app/data/models/money_entry.dart';
import 'package:moneytarget_app/data/models/transaction_type.dart';
import 'package:moneytarget_app/data/repositories/mock_money_repository.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting('zh_TW', null);
  });

  testWidgets('App loads dashboard tab by default', (tester) async {
    final repository = MockMoneyRepository.generate();
    final dataStore = _InMemoryDataStore(repository);

    await tester.pumpWidget(
      MoneyTargetApp(
        initialRepository: repository,
        dataStore: dataStore,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('儀表板'), findsWidgets);
    expect(find.text('記錄'), findsWidgets);
    expect(find.text('設定'), findsWidgets);
  });
}

class _InMemoryDataStore implements MoneyDataStore {
  _InMemoryDataStore(this._repository)
      : _categories = _repository.categorySettings,
        _currencySettings = CurrencySettings.defaults();

  MockMoneyRepository _repository;
  CategorySettings _categories;
  CurrencySettings _currencySettings;

  @override
  Future<void> deleteEntry(String id) async {
    final updatedEntries =
        _repository.entries.where((entry) => entry.id != id).toList();
    _repository = _repository.copyWith(entries: updatedEntries);
  }

  @override
  Future<void> saveEntries(Iterable<MoneyEntry> items) async {
    _repository = _repository.copyWith(entries: items.toList());
  }

  @override
  Future<void> saveGoal(Goal goal) async {
    _repository = _repository.copyWith(goal: goal);
  }

  @override
  MockMoneyRepository toRepository() => _repository;

  @override
  Future<void> upsertEntry(MoneyEntry entry) async {
    final entries = _repository.entries.toList();
    final index = entries.indexWhere((element) => element.id == entry.id);
    if (index >= 0) {
      entries[index] = entry;
    } else {
      entries.add(entry);
    }
    _repository = _repository.copyWith(entries: entries);
  }

  @override
  CategorySettings get categories => _categories;

  @override
  Future<void> saveCategories(CategorySettings settings) async {
    _categories = settings;
    _repository = _repository.copyWith(categorySettings: settings);
  }

  @override
  CurrencySettings get currencySettings => _currencySettings;

  @override
  Future<void> saveCurrencySettings(CurrencySettings settings) async {
    _currencySettings = settings;
  }

  @override
  Future<Map<String, dynamic>> exportData() async {
    return {
      'goal': {
        'targetAmount': _repository.goal.targetAmount,
        'startDate': _repository.goal.startDate.toIso8601String(),
        'endDate': _repository.goal.endDate.toIso8601String(),
      },
      'entries': _repository.entries
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
        'income': _categories.incomeSources,
        'saving': _categories.savingSources,
        'expense': _categories.expenseCategories,
      },
      'currency': {
        'selected': _currencySettings.selectedCurrency.index,
        'audToTwdRate': _currencySettings.audToTwdRate,
      },
    };
  }

  @override
  Future<void> importData(Map<String, dynamic> data) async {
    if (data['goal'] case final Map<String, dynamic> goalMap) {
      _repository = _repository.copyWith(
        goal: Goal(
          targetAmount: (goalMap['targetAmount'] as num).toDouble(),
          startDate: DateTime.parse(goalMap['startDate'] as String),
          endDate: DateTime.parse(goalMap['endDate'] as String),
        ),
      );
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
      _repository = _repository.copyWith(entries: importedEntries);
    }

    if (data['categories'] case final Map<String, dynamic> categoriesMap) {
      _categories = CategorySettings(
        incomeSources:
            (categoriesMap['income'] as List).cast<String>(),
        savingSources:
            (categoriesMap['saving'] as List).cast<String>(),
        expenseCategories:
            (categoriesMap['expense'] as List).cast<String>(),
      );
      _repository = _repository.copyWith(categorySettings: _categories);
    }

    if (data['currency'] case final Map<String, dynamic> currencyMap) {
      final selectedIndex = currencyMap['selected'] as int? ?? 0;
      _currencySettings = CurrencySettings(
        selectedCurrency: Currency.values[selectedIndex
            .clamp(0, Currency.values.length - 1)],
        audToTwdRate:
            (currencyMap['audToTwdRate'] as num?)?.toDouble() ?? 20.0,
      );
    }
  }
}
