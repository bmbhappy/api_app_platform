import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'record_model.dart';
import 'record_database.dart';

class RecordCalendarView extends StatefulWidget {
  const RecordCalendarView({super.key});

  @override
  State<RecordCalendarView> createState() => _RecordCalendarViewState();
}

class _RecordCalendarViewState extends State<RecordCalendarView> {
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.month;
  List<Record> _records = [];
  List<DateTime> _datesWithRecords = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final records = await RecordDatabase.instance.getRecordsByDate(_selectedDay);
      final dates = await RecordDatabase.instance.getDatesWithRecords();
      
      if (mounted) {
        setState(() {
          _records = records;
          _datesWithRecords = dates;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool _isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  List<DateTime> _getEventsForDay(DateTime day) {
    // 只返回有记录标记的日期，不需要返回完整日期列表
    final hasRecord = _datesWithRecords.any((date) => _isSameDay(date, day));
    return hasRecord ? [day] : [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('运动记录'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          // 日历视图
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            selectedDayPredicate: (day) => _isSameDay(_selectedDay, day),
            eventLoader: _getEventsForDay,
            onDaySelected: (selectedDay, focusedDay) {
              if (!_isSameDay(_selectedDay, selectedDay)) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
                _loadRecords();
              }
            },
            onFormatChanged: (format) {
              if (_calendarFormat != format) {
                setState(() {
                  _calendarFormat = format;
                });
              }
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            calendarStyle: CalendarStyle(
              outsideDaysVisible: false,
              todayDecoration: BoxDecoration(
                color: Colors.blue.shade100,
                shape: BoxShape.circle,
              ),
              selectedDecoration: const BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              markerDecoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
              markersMaxCount: 1,
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: true,
              titleCentered: true,
              formatButtonShowsNext: false,
              formatButtonDecoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(8),
              ),
              formatButtonTextStyle: const TextStyle(
                color: Colors.white,
              ),
            ),
          ),
          
          const Divider(height: 1),
          
          // 记录列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inbox,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '${DateFormat('yyyy年MM月dd日').format(_selectedDay)}\n没有记录',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Column(
                        children: [
                          // 日期标题
                          Container(
                            padding: const EdgeInsets.all(16),
                            color: Colors.blue.shade50,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.today,
                                  color: Colors.blue.shade700,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat('yyyy年MM月dd日').format(_selectedDay),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade700,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_records.length} 条记录',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          // 记录列表
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _records.length,
                              itemBuilder: (context, index) {
                                final record = _records[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  elevation: 2,
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.blue.shade100,
                                      child: Icon(
                                        Icons.fitness_center,
                                        color: Colors.blue.shade700,
                                      ),
                                    ),
                                    title: Text(
                                      record.formattedDuration,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      record.formattedTime,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      color: Colors.red.shade300,
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('删除记录'),
                                            content: const Text('确定要删除这条记录吗？'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(context)
                                                        .pop(false),
                                                child: const Text('取消'),
                                              ),
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(context)
                                                        .pop(true),
                                                style: TextButton.styleFrom(
                                                  foregroundColor: Colors.red,
                                                ),
                                                child: const Text('删除'),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (confirm == true && record.id != null) {
                                          try {
                                            await RecordDatabase.instance
                                                .deleteRecord(record.id!);
                                            _loadRecords();
                                            if (mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content: Text('记录已删除'),
                                                  duration:
                                                      Duration(seconds: 1),
                                                ),
                                              );
                                            }
                                          } catch (e) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content: Text('删除失败'),
                                                  duration:
                                                      Duration(seconds: 1),
                                                ),
                                              );
                                            }
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}

