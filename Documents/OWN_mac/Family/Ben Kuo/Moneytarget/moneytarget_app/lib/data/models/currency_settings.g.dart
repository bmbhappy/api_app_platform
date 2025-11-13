// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'currency_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CurrencySettingsAdapter extends TypeAdapter<CurrencySettings> {
  @override
  final int typeId = 5;

  @override
  CurrencySettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CurrencySettings(
      selectedCurrency: fields[0] as Currency,
      audToTwdRate: fields[1] as double,
    );
  }

  @override
  void write(BinaryWriter writer, CurrencySettings obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.selectedCurrency)
      ..writeByte(1)
      ..write(obj.audToTwdRate);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CurrencySettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class CurrencyAdapter extends TypeAdapter<Currency> {
  @override
  final int typeId = 4;

  @override
  Currency read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return Currency.twd;
      case 1:
        return Currency.aud;
      default:
        return Currency.twd;
    }
  }

  @override
  void write(BinaryWriter writer, Currency obj) {
    switch (obj) {
      case Currency.twd:
        writer.writeByte(0);
        break;
      case Currency.aud:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CurrencyAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
