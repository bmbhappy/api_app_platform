// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'money_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MoneyEntryAdapter extends TypeAdapter<MoneyEntry> {
  @override
  final int typeId = 2;

  @override
  MoneyEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MoneyEntry(
      id: fields[0] as String,
      type: fields[1] as TransactionType,
      amount: fields[2] as double,
      date: fields[3] as DateTime,
      category: fields[4] as String?,
      source: fields[5] as String?,
      note: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, MoneyEntry obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.date)
      ..writeByte(4)
      ..write(obj.category)
      ..writeByte(5)
      ..write(obj.source)
      ..writeByte(6)
      ..write(obj.note);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoneyEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
