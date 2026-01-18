// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TransactionAdapter extends TypeAdapter<Transaction> {
  @override
  final int typeId = 1;

  @override
  Transaction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Transaction(
      id: fields[0] as String,
      contactId: fields[1] as String,
      type: fields[2] as TransactionType,
      direction: fields[3] as TransactionDirection,
      amount: fields[4] as int,
      currency: fields[5] as String,
      description: fields[6] as String?,
      transactionDate: fields[7] as DateTime,
      dueDate: fields[12] as DateTime?,
      imagePaths: (fields[8] as List).cast<String>(),
      createdAt: fields[9] as DateTime,
      updatedAt: fields[10] as DateTime,
      isSynced: fields[11] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Transaction obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.contactId)
      ..writeByte(2)
      ..write(obj.type)
      ..writeByte(3)
      ..write(obj.direction)
      ..writeByte(4)
      ..write(obj.amount)
      ..writeByte(5)
      ..write(obj.currency)
      ..writeByte(6)
      ..write(obj.description)
      ..writeByte(7)
      ..write(obj.transactionDate)
      ..writeByte(12)
      ..write(obj.dueDate)
      ..writeByte(8)
      ..write(obj.imagePaths)
      ..writeByte(9)
      ..write(obj.createdAt)
      ..writeByte(10)
      ..write(obj.updatedAt)
      ..writeByte(11)
      ..write(obj.isSynced);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TransactionTypeAdapter extends TypeAdapter<TransactionType> {
  @override
  final int typeId = 2;

  @override
  TransactionType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TransactionType.money;
      case 1:
        return TransactionType.item;
      default:
        return TransactionType.money;
    }
  }

  @override
  void write(BinaryWriter writer, TransactionType obj) {
    switch (obj) {
      case TransactionType.money:
        writer.writeByte(0);
        break;
      case TransactionType.item:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TransactionDirectionAdapter extends TypeAdapter<TransactionDirection> {
  @override
  final int typeId = 3;

  @override
  TransactionDirection read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TransactionDirection.owed;
      case 1:
        return TransactionDirection.lent;
      default:
        return TransactionDirection.owed;
    }
  }

  @override
  void write(BinaryWriter writer, TransactionDirection obj) {
    switch (obj) {
      case TransactionDirection.owed:
        writer.writeByte(0);
        break;
      case TransactionDirection.lent:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionDirectionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
