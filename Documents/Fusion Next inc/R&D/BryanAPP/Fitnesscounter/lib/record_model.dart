class Record {
  final int? id;
  final DateTime dateTime;
  final int totalSeconds;
  final int minutes;
  final int seconds;

  Record({
    this.id,
    required this.dateTime,
    required this.totalSeconds,
  })  : minutes = totalSeconds ~/ 60,
        seconds = totalSeconds % 60;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'dateTime': dateTime.toIso8601String(),
      'totalSeconds': totalSeconds,
    };
  }

  factory Record.fromMap(Map<String, dynamic> map) {
    return Record(
      id: map['id'] as int?,
      dateTime: DateTime.parse(map['dateTime'] as String),
      totalSeconds: map['totalSeconds'] as int,
    );
  }

  String get formattedDuration {
    if (minutes > 0) {
      return '$minutes 分 $seconds 秒';
    }
    return '$seconds 秒';
  }

  String get formattedTime {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String get formattedDate {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }
}

