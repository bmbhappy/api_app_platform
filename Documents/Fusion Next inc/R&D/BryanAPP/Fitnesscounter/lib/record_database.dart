import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'record_model.dart';

class RecordDatabase {
  static final RecordDatabase instance = RecordDatabase._init();
  static Database? _database;

  RecordDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('records.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const intType = 'INTEGER NOT NULL';

    await db.execute('''
      CREATE TABLE records (
        id $idType,
        dateTime $textType,
        totalSeconds $intType
      )
    ''');
  }

  Future<int> createRecord(Record record) async {
    final db = await database;
    return await db.insert('records', record.toMap());
  }

  Future<List<Record>> getAllRecords() async {
    final db = await database;
    final result = await db.query(
      'records',
      orderBy: 'dateTime DESC',
    );

    return result.map((map) => Record.fromMap(map)).toList();
  }

  Future<List<Record>> getRecordsByDate(DateTime date) async {
    final db = await database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);

    final result = await db.query(
      'records',
      where: 'dateTime >= ? AND dateTime <= ?',
      whereArgs: [
        startOfDay.toIso8601String(),
        endOfDay.toIso8601String(),
      ],
      orderBy: 'dateTime DESC',
    );

    return result.map((map) => Record.fromMap(map)).toList();
  }

  Future<List<DateTime>> getDatesWithRecords() async {
    final db = await database;
    final allRecords = await getAllRecords();
    
    // 获取所有唯一的日期
    final datesSet = <DateTime>{};
    for (final record in allRecords) {
      final dateOnly = DateTime(
        record.dateTime.year,
        record.dateTime.month,
        record.dateTime.day,
      );
      datesSet.add(dateOnly);
    }
    
    final datesList = datesSet.toList();
    datesList.sort((a, b) => b.compareTo(a)); // 降序排列
    
    return datesList;
  }

  Future<int> deleteRecord(int id) async {
    final db = await database;
    return await db.delete(
      'records',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}

