import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'data/datasources/hive_data_store.dart';
import 'data/models/category_settings.dart';
import 'data/models/currency_settings.dart';
import 'data/models/goal.dart';
import 'data/models/money_entry.dart';
import 'data/models/transaction_type.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_TW', null);
  await Hive.initFlutter();
  Hive.registerAdapter(GoalAdapter());
  Hive.registerAdapter(TransactionTypeAdapter());
  Hive.registerAdapter(MoneyEntryAdapter());
  Hive.registerAdapter(CategorySettingsAdapter());
  Hive.registerAdapter(CurrencyAdapter());
  Hive.registerAdapter(CurrencySettingsAdapter());

  final dataStore = await HiveDataStore.load();
  final repository = dataStore.toRepository();

  runApp(
    MoneyTargetApp(
      initialRepository: repository,
      dataStore: dataStore,
    ),
  );
}
