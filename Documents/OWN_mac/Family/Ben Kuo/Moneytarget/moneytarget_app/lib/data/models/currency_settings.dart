import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

part 'currency_settings.g.dart';

@HiveType(typeId: 4)
enum Currency {
  @HiveField(0)
  twd,
  @HiveField(1)
  aud,
}

@HiveType(typeId: 5)
class CurrencySettings {
  const CurrencySettings({
    required this.selectedCurrency,
    required this.audToTwdRate,
  });

  @HiveField(0)
  final Currency selectedCurrency;

  /// The conversion rate representing how many TWD equal 1 AUD.
  @HiveField(1)
  final double audToTwdRate;

  factory CurrencySettings.defaults() {
    return const CurrencySettings(
      selectedCurrency: Currency.twd,
      audToTwdRate: 20.0,
    );
  }

  CurrencySettings copyWith({
    Currency? selectedCurrency,
    double? audToTwdRate,
  }) {
    return CurrencySettings(
      selectedCurrency: selectedCurrency ?? this.selectedCurrency,
      audToTwdRate: audToTwdRate ?? this.audToTwdRate,
    );
  }

  double toDisplay(double amountTwd) {
    switch (selectedCurrency) {
      case Currency.twd:
        return amountTwd;
      case Currency.aud:
        if (audToTwdRate == 0) return amountTwd;
        return amountTwd / audToTwdRate;
    }
  }

  double toStorage(double amountDisplay) {
    switch (selectedCurrency) {
      case Currency.twd:
        return amountDisplay;
      case Currency.aud:
        return amountDisplay * audToTwdRate;
    }
  }

  NumberFormat get numberFormat {
    switch (selectedCurrency) {
      case Currency.twd:
        return NumberFormat.simpleCurrency(locale: 'zh_TW', decimalDigits: 0);
      case Currency.aud:
        return NumberFormat.currency(locale: 'en_AU', symbol: 'AU\$', decimalDigits: 2);
    }
  }

  String get symbol {
    switch (selectedCurrency) {
      case Currency.twd:
        return 'NT\$';
      case Currency.aud:
        return 'AU\$';
    }
  }

  String format(double amountTwd) {
    final displayValue = toDisplay(amountTwd);
    return numberFormat.format(displayValue);
  }
}
