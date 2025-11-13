import 'package:hive/hive.dart';

import 'transaction_type.dart';

part 'money_entry.g.dart';

@HiveType(typeId: 2)
class MoneyEntry {
  const MoneyEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    this.category,
    this.source,
    this.note,
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final TransactionType type;

  @HiveField(2)
  final double amount;

  @HiveField(3)
  final DateTime date;

  @HiveField(4)
  final String? category;

  @HiveField(5)
  final String? source;

  @HiveField(6)
  final String? note;
}

