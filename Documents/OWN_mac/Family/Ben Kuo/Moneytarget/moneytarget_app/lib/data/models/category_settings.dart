import 'package:hive/hive.dart';

import 'transaction_type.dart';

part 'category_settings.g.dart';

@HiveType(typeId: 3)
class CategorySettings {
  const CategorySettings({
    required this.incomeSources,
    required this.savingSources,
    required this.expenseCategories,
  });

  @HiveField(0)
  final List<String> incomeSources;

  @HiveField(1)
  final List<String> savingSources;

  @HiveField(2)
  final List<String> expenseCategories;

  factory CategorySettings.defaults() {
    return const CategorySettings(
      incomeSources: ['薪資', '獎金', '投資', '其他'],
      savingSources: ['薪資撥入', '額外存款', '轉帳'],
      expenseCategories: ['居住', '食物', '交通', '衣物', '娛樂', '醫療', '償還'],
    );
  }

  CategorySettings copyWith({
    List<String>? incomeSources,
    List<String>? savingSources,
    List<String>? expenseCategories,
  }) {
    return CategorySettings(
      incomeSources: incomeSources ?? this.incomeSources,
      savingSources: savingSources ?? this.savingSources,
      expenseCategories: expenseCategories ?? this.expenseCategories,
    );
  }

  CategorySettings addValue(TransactionType type, String value) {
    switch (type) {
      case TransactionType.income:
        return copyWith(
          incomeSources: _addToList(incomeSources, value),
        );
      case TransactionType.saving:
        return copyWith(
          savingSources: _addToList(savingSources, value),
        );
      case TransactionType.expense:
        return copyWith(
          expenseCategories: _addToList(expenseCategories, value),
        );
    }
  }

  static List<String> _addToList(List<String> source, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return source;
    if (source.contains(trimmed)) return source;
    return [...source, trimmed];
  }
}
