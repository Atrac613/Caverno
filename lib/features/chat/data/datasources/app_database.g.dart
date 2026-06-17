// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ConversationsTable extends Conversations
    with TableInfo<$ConversationsTable, ConversationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    createdAtMs,
    updatedAtMs,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConversationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConversationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConversationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }
}

class ConversationRow extends DataClass implements Insertable<ConversationRow> {
  final String id;
  final String title;
  final int createdAtMs;
  final int updatedAtMs;
  final String payload;
  const ConversationRow({
    required this.id,
    required this.title,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      id: Value(id),
      title: Value(title),
      createdAtMs: Value(createdAtMs),
      updatedAtMs: Value(updatedAtMs),
      payload: Value(payload),
    );
  }

  factory ConversationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConversationRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
      'payload': serializer.toJson<String>(payload),
    };
  }

  ConversationRow copyWith({
    String? id,
    String? title,
    int? createdAtMs,
    int? updatedAtMs,
    String? payload,
  }) => ConversationRow(
    id: id ?? this.id,
    title: title ?? this.title,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    payload: payload ?? this.payload,
  );
  ConversationRow copyWithCompanion(ConversationsCompanion data) {
    return ConversationRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConversationRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, createdAtMs, updatedAtMs, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConversationRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.createdAtMs == this.createdAtMs &&
          other.updatedAtMs == this.updatedAtMs &&
          other.payload == this.payload);
}

class ConversationsCompanion extends UpdateCompanion<ConversationRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<int> createdAtMs;
  final Value<int> updatedAtMs;
  final Value<String> payload;
  final Value<int> rowid;
  const ConversationsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationsCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    required String payload,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       payload = Value(payload);
  static Insertable<ConversationRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<int>? createdAtMs,
    Expression<int>? updatedAtMs,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationsCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<int>? createdAtMs,
    Value<int>? updatedAtMs,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return ConversationsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChatMemoryEntriesTable extends ChatMemoryEntries
    with TableInfo<$ChatMemoryEntriesTable, ChatMemoryEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatMemoryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chat_memory_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<ChatMemoryEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  ChatMemoryEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ChatMemoryEntryRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $ChatMemoryEntriesTable createAlias(String alias) {
    return $ChatMemoryEntriesTable(attachedDatabase, alias);
  }
}

class ChatMemoryEntryRow extends DataClass
    implements Insertable<ChatMemoryEntryRow> {
  final String key;
  final String value;
  const ChatMemoryEntryRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  ChatMemoryEntriesCompanion toCompanion(bool nullToAbsent) {
    return ChatMemoryEntriesCompanion(key: Value(key), value: Value(value));
  }

  factory ChatMemoryEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ChatMemoryEntryRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  ChatMemoryEntryRow copyWith({String? key, String? value}) =>
      ChatMemoryEntryRow(key: key ?? this.key, value: value ?? this.value);
  ChatMemoryEntryRow copyWithCompanion(ChatMemoryEntriesCompanion data) {
    return ChatMemoryEntryRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ChatMemoryEntryRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ChatMemoryEntryRow &&
          other.key == this.key &&
          other.value == this.value);
}

class ChatMemoryEntriesCompanion extends UpdateCompanion<ChatMemoryEntryRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const ChatMemoryEntriesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatMemoryEntriesCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<ChatMemoryEntryRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatMemoryEntriesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return ChatMemoryEntriesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatMemoryEntriesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EmbeddingsTable extends Embeddings
    with TableInfo<$EmbeddingsTable, EmbeddingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EmbeddingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sourceTypeMeta = const VerificationMeta(
    'sourceType',
  );
  @override
  late final GeneratedColumn<String> sourceType = GeneratedColumn<String>(
    'source_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chunkIndexMeta = const VerificationMeta(
    'chunkIndex',
  );
  @override
  late final GeneratedColumn<int> chunkIndex = GeneratedColumn<int>(
    'chunk_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _dimMeta = const VerificationMeta('dim');
  @override
  late final GeneratedColumn<int> dim = GeneratedColumn<int>(
    'dim',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _vectorMeta = const VerificationMeta('vector');
  @override
  late final GeneratedColumn<Uint8List> vector = GeneratedColumn<Uint8List>(
    'vector',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snippetMeta = const VerificationMeta(
    'snippet',
  );
  @override
  late final GeneratedColumn<String> snippet = GeneratedColumn<String>(
    'snippet',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourceType,
    sourceId,
    chunkIndex,
    model,
    dim,
    vector,
    snippet,
    createdAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'embeddings';
  @override
  VerificationContext validateIntegrity(
    Insertable<EmbeddingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('source_type')) {
      context.handle(
        _sourceTypeMeta,
        sourceType.isAcceptableOrUnknown(data['source_type']!, _sourceTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceTypeMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('chunk_index')) {
      context.handle(
        _chunkIndexMeta,
        chunkIndex.isAcceptableOrUnknown(data['chunk_index']!, _chunkIndexMeta),
      );
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('dim')) {
      context.handle(
        _dimMeta,
        dim.isAcceptableOrUnknown(data['dim']!, _dimMeta),
      );
    }
    if (data.containsKey('vector')) {
      context.handle(
        _vectorMeta,
        vector.isAcceptableOrUnknown(data['vector']!, _vectorMeta),
      );
    } else if (isInserting) {
      context.missing(_vectorMeta);
    }
    if (data.containsKey('snippet')) {
      context.handle(
        _snippetMeta,
        snippet.isAcceptableOrUnknown(data['snippet']!, _snippetMeta),
      );
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EmbeddingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EmbeddingRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sourceType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_type'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      chunkIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chunk_index'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      dim: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}dim'],
      )!,
      vector: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}vector'],
      )!,
      snippet: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snippet'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
    );
  }

  @override
  $EmbeddingsTable createAlias(String alias) {
    return $EmbeddingsTable(attachedDatabase, alias);
  }
}

class EmbeddingRow extends DataClass implements Insertable<EmbeddingRow> {
  final int id;
  final String sourceType;
  final String sourceId;
  final int chunkIndex;
  final String model;
  final int dim;
  final Uint8List vector;
  final String snippet;
  final int createdAtMs;
  const EmbeddingRow({
    required this.id,
    required this.sourceType,
    required this.sourceId,
    required this.chunkIndex,
    required this.model,
    required this.dim,
    required this.vector,
    required this.snippet,
    required this.createdAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['source_type'] = Variable<String>(sourceType);
    map['source_id'] = Variable<String>(sourceId);
    map['chunk_index'] = Variable<int>(chunkIndex);
    map['model'] = Variable<String>(model);
    map['dim'] = Variable<int>(dim);
    map['vector'] = Variable<Uint8List>(vector);
    map['snippet'] = Variable<String>(snippet);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    return map;
  }

  EmbeddingsCompanion toCompanion(bool nullToAbsent) {
    return EmbeddingsCompanion(
      id: Value(id),
      sourceType: Value(sourceType),
      sourceId: Value(sourceId),
      chunkIndex: Value(chunkIndex),
      model: Value(model),
      dim: Value(dim),
      vector: Value(vector),
      snippet: Value(snippet),
      createdAtMs: Value(createdAtMs),
    );
  }

  factory EmbeddingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EmbeddingRow(
      id: serializer.fromJson<int>(json['id']),
      sourceType: serializer.fromJson<String>(json['sourceType']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      chunkIndex: serializer.fromJson<int>(json['chunkIndex']),
      model: serializer.fromJson<String>(json['model']),
      dim: serializer.fromJson<int>(json['dim']),
      vector: serializer.fromJson<Uint8List>(json['vector']),
      snippet: serializer.fromJson<String>(json['snippet']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sourceType': serializer.toJson<String>(sourceType),
      'sourceId': serializer.toJson<String>(sourceId),
      'chunkIndex': serializer.toJson<int>(chunkIndex),
      'model': serializer.toJson<String>(model),
      'dim': serializer.toJson<int>(dim),
      'vector': serializer.toJson<Uint8List>(vector),
      'snippet': serializer.toJson<String>(snippet),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
    };
  }

  EmbeddingRow copyWith({
    int? id,
    String? sourceType,
    String? sourceId,
    int? chunkIndex,
    String? model,
    int? dim,
    Uint8List? vector,
    String? snippet,
    int? createdAtMs,
  }) => EmbeddingRow(
    id: id ?? this.id,
    sourceType: sourceType ?? this.sourceType,
    sourceId: sourceId ?? this.sourceId,
    chunkIndex: chunkIndex ?? this.chunkIndex,
    model: model ?? this.model,
    dim: dim ?? this.dim,
    vector: vector ?? this.vector,
    snippet: snippet ?? this.snippet,
    createdAtMs: createdAtMs ?? this.createdAtMs,
  );
  EmbeddingRow copyWithCompanion(EmbeddingsCompanion data) {
    return EmbeddingRow(
      id: data.id.present ? data.id.value : this.id,
      sourceType: data.sourceType.present
          ? data.sourceType.value
          : this.sourceType,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      chunkIndex: data.chunkIndex.present
          ? data.chunkIndex.value
          : this.chunkIndex,
      model: data.model.present ? data.model.value : this.model,
      dim: data.dim.present ? data.dim.value : this.dim,
      vector: data.vector.present ? data.vector.value : this.vector,
      snippet: data.snippet.present ? data.snippet.value : this.snippet,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EmbeddingRow(')
          ..write('id: $id, ')
          ..write('sourceType: $sourceType, ')
          ..write('sourceId: $sourceId, ')
          ..write('chunkIndex: $chunkIndex, ')
          ..write('model: $model, ')
          ..write('dim: $dim, ')
          ..write('vector: $vector, ')
          ..write('snippet: $snippet, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sourceType,
    sourceId,
    chunkIndex,
    model,
    dim,
    $driftBlobEquality.hash(vector),
    snippet,
    createdAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EmbeddingRow &&
          other.id == this.id &&
          other.sourceType == this.sourceType &&
          other.sourceId == this.sourceId &&
          other.chunkIndex == this.chunkIndex &&
          other.model == this.model &&
          other.dim == this.dim &&
          $driftBlobEquality.equals(other.vector, this.vector) &&
          other.snippet == this.snippet &&
          other.createdAtMs == this.createdAtMs);
}

class EmbeddingsCompanion extends UpdateCompanion<EmbeddingRow> {
  final Value<int> id;
  final Value<String> sourceType;
  final Value<String> sourceId;
  final Value<int> chunkIndex;
  final Value<String> model;
  final Value<int> dim;
  final Value<Uint8List> vector;
  final Value<String> snippet;
  final Value<int> createdAtMs;
  const EmbeddingsCompanion({
    this.id = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.chunkIndex = const Value.absent(),
    this.model = const Value.absent(),
    this.dim = const Value.absent(),
    this.vector = const Value.absent(),
    this.snippet = const Value.absent(),
    this.createdAtMs = const Value.absent(),
  });
  EmbeddingsCompanion.insert({
    this.id = const Value.absent(),
    required String sourceType,
    required String sourceId,
    this.chunkIndex = const Value.absent(),
    this.model = const Value.absent(),
    this.dim = const Value.absent(),
    required Uint8List vector,
    this.snippet = const Value.absent(),
    this.createdAtMs = const Value.absent(),
  }) : sourceType = Value(sourceType),
       sourceId = Value(sourceId),
       vector = Value(vector);
  static Insertable<EmbeddingRow> custom({
    Expression<int>? id,
    Expression<String>? sourceType,
    Expression<String>? sourceId,
    Expression<int>? chunkIndex,
    Expression<String>? model,
    Expression<int>? dim,
    Expression<Uint8List>? vector,
    Expression<String>? snippet,
    Expression<int>? createdAtMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceType != null) 'source_type': sourceType,
      if (sourceId != null) 'source_id': sourceId,
      if (chunkIndex != null) 'chunk_index': chunkIndex,
      if (model != null) 'model': model,
      if (dim != null) 'dim': dim,
      if (vector != null) 'vector': vector,
      if (snippet != null) 'snippet': snippet,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
    });
  }

  EmbeddingsCompanion copyWith({
    Value<int>? id,
    Value<String>? sourceType,
    Value<String>? sourceId,
    Value<int>? chunkIndex,
    Value<String>? model,
    Value<int>? dim,
    Value<Uint8List>? vector,
    Value<String>? snippet,
    Value<int>? createdAtMs,
  }) {
    return EmbeddingsCompanion(
      id: id ?? this.id,
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      model: model ?? this.model,
      dim: dim ?? this.dim,
      vector: vector ?? this.vector,
      snippet: snippet ?? this.snippet,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sourceType.present) {
      map['source_type'] = Variable<String>(sourceType.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (chunkIndex.present) {
      map['chunk_index'] = Variable<int>(chunkIndex.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (dim.present) {
      map['dim'] = Variable<int>(dim.value);
    }
    if (vector.present) {
      map['vector'] = Variable<Uint8List>(vector.value);
    }
    if (snippet.present) {
      map['snippet'] = Variable<String>(snippet.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EmbeddingsCompanion(')
          ..write('id: $id, ')
          ..write('sourceType: $sourceType, ')
          ..write('sourceId: $sourceId, ')
          ..write('chunkIndex: $chunkIndex, ')
          ..write('model: $model, ')
          ..write('dim: $dim, ')
          ..write('vector: $vector, ')
          ..write('snippet: $snippet, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $ChatMemoryEntriesTable chatMemoryEntries =
      $ChatMemoryEntriesTable(this);
  late final $EmbeddingsTable embeddings = $EmbeddingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    conversations,
    chatMemoryEntries,
    embeddings,
  ];
}

typedef $$ConversationsTableCreateCompanionBuilder =
    ConversationsCompanion Function({
      required String id,
      Value<String> title,
      Value<int> createdAtMs,
      Value<int> updatedAtMs,
      required String payload,
      Value<int> rowid,
    });
typedef $$ConversationsTableUpdateCompanionBuilder =
    ConversationsCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<int> createdAtMs,
      Value<int> updatedAtMs,
      Value<String> payload,
      Value<int> rowid,
    });

class $$ConversationsTableFilterComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConversationsTableOrderingComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConversationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$ConversationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConversationsTable,
          ConversationRow,
          $$ConversationsTableFilterComposer,
          $$ConversationsTableOrderingComposer,
          $$ConversationsTableAnnotationComposer,
          $$ConversationsTableCreateCompanionBuilder,
          $$ConversationsTableUpdateCompanionBuilder,
          (
            ConversationRow,
            BaseReferences<_$AppDatabase, $ConversationsTable, ConversationRow>,
          ),
          ConversationRow,
          PrefetchHooks Function()
        > {
  $$ConversationsTableTableManager(_$AppDatabase db, $ConversationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion(
                id: id,
                title: title,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                Value<String> title = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion.insert(
                id: id,
                title: title,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConversationsTable,
      ConversationRow,
      $$ConversationsTableFilterComposer,
      $$ConversationsTableOrderingComposer,
      $$ConversationsTableAnnotationComposer,
      $$ConversationsTableCreateCompanionBuilder,
      $$ConversationsTableUpdateCompanionBuilder,
      (
        ConversationRow,
        BaseReferences<_$AppDatabase, $ConversationsTable, ConversationRow>,
      ),
      ConversationRow,
      PrefetchHooks Function()
    >;
typedef $$ChatMemoryEntriesTableCreateCompanionBuilder =
    ChatMemoryEntriesCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$ChatMemoryEntriesTableUpdateCompanionBuilder =
    ChatMemoryEntriesCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$ChatMemoryEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $ChatMemoryEntriesTable> {
  $$ChatMemoryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ChatMemoryEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatMemoryEntriesTable> {
  $$ChatMemoryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ChatMemoryEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatMemoryEntriesTable> {
  $$ChatMemoryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$ChatMemoryEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ChatMemoryEntriesTable,
          ChatMemoryEntryRow,
          $$ChatMemoryEntriesTableFilterComposer,
          $$ChatMemoryEntriesTableOrderingComposer,
          $$ChatMemoryEntriesTableAnnotationComposer,
          $$ChatMemoryEntriesTableCreateCompanionBuilder,
          $$ChatMemoryEntriesTableUpdateCompanionBuilder,
          (
            ChatMemoryEntryRow,
            BaseReferences<
              _$AppDatabase,
              $ChatMemoryEntriesTable,
              ChatMemoryEntryRow
            >,
          ),
          ChatMemoryEntryRow,
          PrefetchHooks Function()
        > {
  $$ChatMemoryEntriesTableTableManager(
    _$AppDatabase db,
    $ChatMemoryEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatMemoryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatMemoryEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatMemoryEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ChatMemoryEntriesCompanion(
                key: key,
                value: value,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => ChatMemoryEntriesCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ChatMemoryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ChatMemoryEntriesTable,
      ChatMemoryEntryRow,
      $$ChatMemoryEntriesTableFilterComposer,
      $$ChatMemoryEntriesTableOrderingComposer,
      $$ChatMemoryEntriesTableAnnotationComposer,
      $$ChatMemoryEntriesTableCreateCompanionBuilder,
      $$ChatMemoryEntriesTableUpdateCompanionBuilder,
      (
        ChatMemoryEntryRow,
        BaseReferences<
          _$AppDatabase,
          $ChatMemoryEntriesTable,
          ChatMemoryEntryRow
        >,
      ),
      ChatMemoryEntryRow,
      PrefetchHooks Function()
    >;
typedef $$EmbeddingsTableCreateCompanionBuilder =
    EmbeddingsCompanion Function({
      Value<int> id,
      required String sourceType,
      required String sourceId,
      Value<int> chunkIndex,
      Value<String> model,
      Value<int> dim,
      required Uint8List vector,
      Value<String> snippet,
      Value<int> createdAtMs,
    });
typedef $$EmbeddingsTableUpdateCompanionBuilder =
    EmbeddingsCompanion Function({
      Value<int> id,
      Value<String> sourceType,
      Value<String> sourceId,
      Value<int> chunkIndex,
      Value<String> model,
      Value<int> dim,
      Value<Uint8List> vector,
      Value<String> snippet,
      Value<int> createdAtMs,
    });

class $$EmbeddingsTableFilterComposer
    extends Composer<_$AppDatabase, $EmbeddingsTable> {
  $$EmbeddingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chunkIndex => $composableBuilder(
    column: $table.chunkIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get dim => $composableBuilder(
    column: $table.dim,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get vector => $composableBuilder(
    column: $table.vector,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snippet => $composableBuilder(
    column: $table.snippet,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EmbeddingsTableOrderingComposer
    extends Composer<_$AppDatabase, $EmbeddingsTable> {
  $$EmbeddingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chunkIndex => $composableBuilder(
    column: $table.chunkIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get dim => $composableBuilder(
    column: $table.dim,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get vector => $composableBuilder(
    column: $table.vector,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snippet => $composableBuilder(
    column: $table.snippet,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EmbeddingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EmbeddingsTable> {
  $$EmbeddingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceType => $composableBuilder(
    column: $table.sourceType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<int> get chunkIndex => $composableBuilder(
    column: $table.chunkIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<int> get dim =>
      $composableBuilder(column: $table.dim, builder: (column) => column);

  GeneratedColumn<Uint8List> get vector =>
      $composableBuilder(column: $table.vector, builder: (column) => column);

  GeneratedColumn<String> get snippet =>
      $composableBuilder(column: $table.snippet, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );
}

class $$EmbeddingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EmbeddingsTable,
          EmbeddingRow,
          $$EmbeddingsTableFilterComposer,
          $$EmbeddingsTableOrderingComposer,
          $$EmbeddingsTableAnnotationComposer,
          $$EmbeddingsTableCreateCompanionBuilder,
          $$EmbeddingsTableUpdateCompanionBuilder,
          (
            EmbeddingRow,
            BaseReferences<_$AppDatabase, $EmbeddingsTable, EmbeddingRow>,
          ),
          EmbeddingRow,
          PrefetchHooks Function()
        > {
  $$EmbeddingsTableTableManager(_$AppDatabase db, $EmbeddingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EmbeddingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EmbeddingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EmbeddingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> sourceType = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<int> chunkIndex = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<int> dim = const Value.absent(),
                Value<Uint8List> vector = const Value.absent(),
                Value<String> snippet = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
              }) => EmbeddingsCompanion(
                id: id,
                sourceType: sourceType,
                sourceId: sourceId,
                chunkIndex: chunkIndex,
                model: model,
                dim: dim,
                vector: vector,
                snippet: snippet,
                createdAtMs: createdAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String sourceType,
                required String sourceId,
                Value<int> chunkIndex = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<int> dim = const Value.absent(),
                required Uint8List vector,
                Value<String> snippet = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
              }) => EmbeddingsCompanion.insert(
                id: id,
                sourceType: sourceType,
                sourceId: sourceId,
                chunkIndex: chunkIndex,
                model: model,
                dim: dim,
                vector: vector,
                snippet: snippet,
                createdAtMs: createdAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EmbeddingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EmbeddingsTable,
      EmbeddingRow,
      $$EmbeddingsTableFilterComposer,
      $$EmbeddingsTableOrderingComposer,
      $$EmbeddingsTableAnnotationComposer,
      $$EmbeddingsTableCreateCompanionBuilder,
      $$EmbeddingsTableUpdateCompanionBuilder,
      (
        EmbeddingRow,
        BaseReferences<_$AppDatabase, $EmbeddingsTable, EmbeddingRow>,
      ),
      EmbeddingRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db, _db.conversations);
  $$ChatMemoryEntriesTableTableManager get chatMemoryEntries =>
      $$ChatMemoryEntriesTableTableManager(_db, _db.chatMemoryEntries);
  $$EmbeddingsTableTableManager get embeddings =>
      $$EmbeddingsTableTableManager(_db, _db.embeddings);
}
