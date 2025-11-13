import 'package:hive/hive.dart';

part 'goal.g.dart';

@HiveType(typeId: 0)
class Goal {
  const Goal({
    required this.targetAmount,
    required this.startDate,
    required this.endDate,
  });

  @HiveField(0)
  final double targetAmount;

  @HiveField(1)
  final DateTime startDate;

  @HiveField(2)
  final DateTime endDate;

  int get totalDays => endDate.difference(startDate).inDays + 1;

  int get totalWeeks => (totalDays / 7).ceil();

  int get totalMonths =>
      (endDate.year - startDate.year) * 12 + endDate.month - startDate.month + 1;

  double get requiredDailyAmount =>
      totalDays == 0 ? targetAmount : targetAmount / totalDays;

  double get requiredWeeklyAmount =>
      totalWeeks == 0 ? targetAmount : targetAmount / totalWeeks;

  double get requiredMonthlyAmount =>
      totalMonths == 0 ? targetAmount : targetAmount / totalMonths;

  double expectedAmountUntil(DateTime date) {
    if (date.isBefore(startDate)) {
      return 0;
    }
    final cappedDate = date.isAfter(endDate) ? endDate : date;
    final elapsedDays = cappedDate.difference(startDate).inDays + 1;
    return requiredDailyAmount * elapsedDays;
  }

  double expectedProgressUntil(DateTime date) {
    if (targetAmount == 0) return 0;
    final ratio = expectedAmountUntil(date) / targetAmount;
    return ratio.clamp(0, 1).toDouble();
  }
}

