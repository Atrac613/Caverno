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

class $ModelUsageDailyTable extends ModelUsageDaily
    with TableInfo<$ModelUsageDailyTable, ModelUsageDailyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ModelUsageDailyTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dayNumberMeta = const VerificationMeta(
    'dayNumber',
  );
  @override
  late final GeneratedColumn<int> dayNumber = GeneratedColumn<int>(
    'day_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endpointIdMeta = const VerificationMeta(
    'endpointId',
  );
  @override
  late final GeneratedColumn<String> endpointId = GeneratedColumn<String>(
    'endpoint_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown'),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _requestCountMeta = const VerificationMeta(
    'requestCount',
  );
  @override
  late final GeneratedColumn<int> requestCount = GeneratedColumn<int>(
    'request_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _errorCountMeta = const VerificationMeta(
    'errorCount',
  );
  @override
  late final GeneratedColumn<int> errorCount = GeneratedColumn<int>(
    'error_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _truncatedCountMeta = const VerificationMeta(
    'truncatedCount',
  );
  @override
  late final GeneratedColumn<int> truncatedCount = GeneratedColumn<int>(
    'truncated_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _promptTokensMeta = const VerificationMeta(
    'promptTokens',
  );
  @override
  late final GeneratedColumn<int> promptTokens = GeneratedColumn<int>(
    'prompt_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _completionTokensMeta = const VerificationMeta(
    'completionTokens',
  );
  @override
  late final GeneratedColumn<int> completionTokens = GeneratedColumn<int>(
    'completion_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalTokensMeta = const VerificationMeta(
    'totalTokens',
  );
  @override
  late final GeneratedColumn<int> totalTokens = GeneratedColumn<int>(
    'total_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _cachedPromptTokensMeta =
      const VerificationMeta('cachedPromptTokens');
  @override
  late final GeneratedColumn<int> cachedPromptTokens = GeneratedColumn<int>(
    'cached_prompt_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _audioPromptTokensMeta = const VerificationMeta(
    'audioPromptTokens',
  );
  @override
  late final GeneratedColumn<int> audioPromptTokens = GeneratedColumn<int>(
    'audio_prompt_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _reasoningTokensMeta = const VerificationMeta(
    'reasoningTokens',
  );
  @override
  late final GeneratedColumn<int> reasoningTokens = GeneratedColumn<int>(
    'reasoning_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _audioCompletionTokensMeta =
      const VerificationMeta('audioCompletionTokens');
  @override
  late final GeneratedColumn<int> audioCompletionTokens = GeneratedColumn<int>(
    'audio_completion_tokens',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _acceptedPredictionTokensMeta =
      const VerificationMeta('acceptedPredictionTokens');
  @override
  late final GeneratedColumn<int> acceptedPredictionTokens =
      GeneratedColumn<int>(
        'accepted_prediction_tokens',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  static const VerificationMeta _rejectedPredictionTokensMeta =
      const VerificationMeta('rejectedPredictionTokens');
  @override
  late final GeneratedColumn<int> rejectedPredictionTokens =
      GeneratedColumn<int>(
        'rejected_prediction_tokens',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: false,
        defaultValue: const Constant(0),
      );
  @override
  List<GeneratedColumn> get $columns => [
    dayNumber,
    model,
    endpointId,
    role,
    label,
    requestCount,
    errorCount,
    truncatedCount,
    durationMs,
    promptTokens,
    completionTokens,
    totalTokens,
    cachedPromptTokens,
    audioPromptTokens,
    reasoningTokens,
    audioCompletionTokens,
    acceptedPredictionTokens,
    rejectedPredictionTokens,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'model_usage_daily';
  @override
  VerificationContext validateIntegrity(
    Insertable<ModelUsageDailyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('day_number')) {
      context.handle(
        _dayNumberMeta,
        dayNumber.isAcceptableOrUnknown(data['day_number']!, _dayNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_dayNumberMeta);
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    } else if (isInserting) {
      context.missing(_modelMeta);
    }
    if (data.containsKey('endpoint_id')) {
      context.handle(
        _endpointIdMeta,
        endpointId.isAcceptableOrUnknown(data['endpoint_id']!, _endpointIdMeta),
      );
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    if (data.containsKey('request_count')) {
      context.handle(
        _requestCountMeta,
        requestCount.isAcceptableOrUnknown(
          data['request_count']!,
          _requestCountMeta,
        ),
      );
    }
    if (data.containsKey('error_count')) {
      context.handle(
        _errorCountMeta,
        errorCount.isAcceptableOrUnknown(data['error_count']!, _errorCountMeta),
      );
    }
    if (data.containsKey('truncated_count')) {
      context.handle(
        _truncatedCountMeta,
        truncatedCount.isAcceptableOrUnknown(
          data['truncated_count']!,
          _truncatedCountMeta,
        ),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('prompt_tokens')) {
      context.handle(
        _promptTokensMeta,
        promptTokens.isAcceptableOrUnknown(
          data['prompt_tokens']!,
          _promptTokensMeta,
        ),
      );
    }
    if (data.containsKey('completion_tokens')) {
      context.handle(
        _completionTokensMeta,
        completionTokens.isAcceptableOrUnknown(
          data['completion_tokens']!,
          _completionTokensMeta,
        ),
      );
    }
    if (data.containsKey('total_tokens')) {
      context.handle(
        _totalTokensMeta,
        totalTokens.isAcceptableOrUnknown(
          data['total_tokens']!,
          _totalTokensMeta,
        ),
      );
    }
    if (data.containsKey('cached_prompt_tokens')) {
      context.handle(
        _cachedPromptTokensMeta,
        cachedPromptTokens.isAcceptableOrUnknown(
          data['cached_prompt_tokens']!,
          _cachedPromptTokensMeta,
        ),
      );
    }
    if (data.containsKey('audio_prompt_tokens')) {
      context.handle(
        _audioPromptTokensMeta,
        audioPromptTokens.isAcceptableOrUnknown(
          data['audio_prompt_tokens']!,
          _audioPromptTokensMeta,
        ),
      );
    }
    if (data.containsKey('reasoning_tokens')) {
      context.handle(
        _reasoningTokensMeta,
        reasoningTokens.isAcceptableOrUnknown(
          data['reasoning_tokens']!,
          _reasoningTokensMeta,
        ),
      );
    }
    if (data.containsKey('audio_completion_tokens')) {
      context.handle(
        _audioCompletionTokensMeta,
        audioCompletionTokens.isAcceptableOrUnknown(
          data['audio_completion_tokens']!,
          _audioCompletionTokensMeta,
        ),
      );
    }
    if (data.containsKey('accepted_prediction_tokens')) {
      context.handle(
        _acceptedPredictionTokensMeta,
        acceptedPredictionTokens.isAcceptableOrUnknown(
          data['accepted_prediction_tokens']!,
          _acceptedPredictionTokensMeta,
        ),
      );
    }
    if (data.containsKey('rejected_prediction_tokens')) {
      context.handle(
        _rejectedPredictionTokensMeta,
        rejectedPredictionTokens.isAcceptableOrUnknown(
          data['rejected_prediction_tokens']!,
          _rejectedPredictionTokensMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    dayNumber,
    model,
    endpointId,
    role,
    label,
  };
  @override
  ModelUsageDailyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ModelUsageDailyRow(
      dayNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}day_number'],
      )!,
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      )!,
      endpointId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}endpoint_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      requestCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}request_count'],
      )!,
      errorCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}error_count'],
      )!,
      truncatedCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}truncated_count'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      promptTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}prompt_tokens'],
      )!,
      completionTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}completion_tokens'],
      )!,
      totalTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_tokens'],
      )!,
      cachedPromptTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cached_prompt_tokens'],
      )!,
      audioPromptTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}audio_prompt_tokens'],
      )!,
      reasoningTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reasoning_tokens'],
      )!,
      audioCompletionTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}audio_completion_tokens'],
      )!,
      acceptedPredictionTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}accepted_prediction_tokens'],
      )!,
      rejectedPredictionTokens: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rejected_prediction_tokens'],
      )!,
    );
  }

  @override
  $ModelUsageDailyTable createAlias(String alias) {
    return $ModelUsageDailyTable(attachedDatabase, alias);
  }
}

class ModelUsageDailyRow extends DataClass
    implements Insertable<ModelUsageDailyRow> {
  /// Local epoch-day, matching `modelUsageDayNumber`.
  final int dayNumber;
  final String model;
  final String endpointId;

  /// `ModelUsageRole.name`; `'unknown'` marks a call site that never set one.
  final String role;

  /// The session-log request label, which names a main-loop recovery path
  /// (`'tool-loop exhaustion recovery'`, ...) — not a role.
  final String label;
  final int requestCount;
  final int errorCount;

  /// Completions that stopped on `finish_reason == 'length'`.
  final int truncatedCount;

  /// Running sum; average latency is `durationMs / requestCount`.
  final int durationMs;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final int cachedPromptTokens;
  final int audioPromptTokens;
  final int reasoningTokens;
  final int audioCompletionTokens;
  final int acceptedPredictionTokens;
  final int rejectedPredictionTokens;
  const ModelUsageDailyRow({
    required this.dayNumber,
    required this.model,
    required this.endpointId,
    required this.role,
    required this.label,
    required this.requestCount,
    required this.errorCount,
    required this.truncatedCount,
    required this.durationMs,
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    required this.cachedPromptTokens,
    required this.audioPromptTokens,
    required this.reasoningTokens,
    required this.audioCompletionTokens,
    required this.acceptedPredictionTokens,
    required this.rejectedPredictionTokens,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['day_number'] = Variable<int>(dayNumber);
    map['model'] = Variable<String>(model);
    map['endpoint_id'] = Variable<String>(endpointId);
    map['role'] = Variable<String>(role);
    map['label'] = Variable<String>(label);
    map['request_count'] = Variable<int>(requestCount);
    map['error_count'] = Variable<int>(errorCount);
    map['truncated_count'] = Variable<int>(truncatedCount);
    map['duration_ms'] = Variable<int>(durationMs);
    map['prompt_tokens'] = Variable<int>(promptTokens);
    map['completion_tokens'] = Variable<int>(completionTokens);
    map['total_tokens'] = Variable<int>(totalTokens);
    map['cached_prompt_tokens'] = Variable<int>(cachedPromptTokens);
    map['audio_prompt_tokens'] = Variable<int>(audioPromptTokens);
    map['reasoning_tokens'] = Variable<int>(reasoningTokens);
    map['audio_completion_tokens'] = Variable<int>(audioCompletionTokens);
    map['accepted_prediction_tokens'] = Variable<int>(acceptedPredictionTokens);
    map['rejected_prediction_tokens'] = Variable<int>(rejectedPredictionTokens);
    return map;
  }

  ModelUsageDailyCompanion toCompanion(bool nullToAbsent) {
    return ModelUsageDailyCompanion(
      dayNumber: Value(dayNumber),
      model: Value(model),
      endpointId: Value(endpointId),
      role: Value(role),
      label: Value(label),
      requestCount: Value(requestCount),
      errorCount: Value(errorCount),
      truncatedCount: Value(truncatedCount),
      durationMs: Value(durationMs),
      promptTokens: Value(promptTokens),
      completionTokens: Value(completionTokens),
      totalTokens: Value(totalTokens),
      cachedPromptTokens: Value(cachedPromptTokens),
      audioPromptTokens: Value(audioPromptTokens),
      reasoningTokens: Value(reasoningTokens),
      audioCompletionTokens: Value(audioCompletionTokens),
      acceptedPredictionTokens: Value(acceptedPredictionTokens),
      rejectedPredictionTokens: Value(rejectedPredictionTokens),
    );
  }

  factory ModelUsageDailyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ModelUsageDailyRow(
      dayNumber: serializer.fromJson<int>(json['dayNumber']),
      model: serializer.fromJson<String>(json['model']),
      endpointId: serializer.fromJson<String>(json['endpointId']),
      role: serializer.fromJson<String>(json['role']),
      label: serializer.fromJson<String>(json['label']),
      requestCount: serializer.fromJson<int>(json['requestCount']),
      errorCount: serializer.fromJson<int>(json['errorCount']),
      truncatedCount: serializer.fromJson<int>(json['truncatedCount']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      promptTokens: serializer.fromJson<int>(json['promptTokens']),
      completionTokens: serializer.fromJson<int>(json['completionTokens']),
      totalTokens: serializer.fromJson<int>(json['totalTokens']),
      cachedPromptTokens: serializer.fromJson<int>(json['cachedPromptTokens']),
      audioPromptTokens: serializer.fromJson<int>(json['audioPromptTokens']),
      reasoningTokens: serializer.fromJson<int>(json['reasoningTokens']),
      audioCompletionTokens: serializer.fromJson<int>(
        json['audioCompletionTokens'],
      ),
      acceptedPredictionTokens: serializer.fromJson<int>(
        json['acceptedPredictionTokens'],
      ),
      rejectedPredictionTokens: serializer.fromJson<int>(
        json['rejectedPredictionTokens'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'dayNumber': serializer.toJson<int>(dayNumber),
      'model': serializer.toJson<String>(model),
      'endpointId': serializer.toJson<String>(endpointId),
      'role': serializer.toJson<String>(role),
      'label': serializer.toJson<String>(label),
      'requestCount': serializer.toJson<int>(requestCount),
      'errorCount': serializer.toJson<int>(errorCount),
      'truncatedCount': serializer.toJson<int>(truncatedCount),
      'durationMs': serializer.toJson<int>(durationMs),
      'promptTokens': serializer.toJson<int>(promptTokens),
      'completionTokens': serializer.toJson<int>(completionTokens),
      'totalTokens': serializer.toJson<int>(totalTokens),
      'cachedPromptTokens': serializer.toJson<int>(cachedPromptTokens),
      'audioPromptTokens': serializer.toJson<int>(audioPromptTokens),
      'reasoningTokens': serializer.toJson<int>(reasoningTokens),
      'audioCompletionTokens': serializer.toJson<int>(audioCompletionTokens),
      'acceptedPredictionTokens': serializer.toJson<int>(
        acceptedPredictionTokens,
      ),
      'rejectedPredictionTokens': serializer.toJson<int>(
        rejectedPredictionTokens,
      ),
    };
  }

  ModelUsageDailyRow copyWith({
    int? dayNumber,
    String? model,
    String? endpointId,
    String? role,
    String? label,
    int? requestCount,
    int? errorCount,
    int? truncatedCount,
    int? durationMs,
    int? promptTokens,
    int? completionTokens,
    int? totalTokens,
    int? cachedPromptTokens,
    int? audioPromptTokens,
    int? reasoningTokens,
    int? audioCompletionTokens,
    int? acceptedPredictionTokens,
    int? rejectedPredictionTokens,
  }) => ModelUsageDailyRow(
    dayNumber: dayNumber ?? this.dayNumber,
    model: model ?? this.model,
    endpointId: endpointId ?? this.endpointId,
    role: role ?? this.role,
    label: label ?? this.label,
    requestCount: requestCount ?? this.requestCount,
    errorCount: errorCount ?? this.errorCount,
    truncatedCount: truncatedCount ?? this.truncatedCount,
    durationMs: durationMs ?? this.durationMs,
    promptTokens: promptTokens ?? this.promptTokens,
    completionTokens: completionTokens ?? this.completionTokens,
    totalTokens: totalTokens ?? this.totalTokens,
    cachedPromptTokens: cachedPromptTokens ?? this.cachedPromptTokens,
    audioPromptTokens: audioPromptTokens ?? this.audioPromptTokens,
    reasoningTokens: reasoningTokens ?? this.reasoningTokens,
    audioCompletionTokens: audioCompletionTokens ?? this.audioCompletionTokens,
    acceptedPredictionTokens:
        acceptedPredictionTokens ?? this.acceptedPredictionTokens,
    rejectedPredictionTokens:
        rejectedPredictionTokens ?? this.rejectedPredictionTokens,
  );
  ModelUsageDailyRow copyWithCompanion(ModelUsageDailyCompanion data) {
    return ModelUsageDailyRow(
      dayNumber: data.dayNumber.present ? data.dayNumber.value : this.dayNumber,
      model: data.model.present ? data.model.value : this.model,
      endpointId: data.endpointId.present
          ? data.endpointId.value
          : this.endpointId,
      role: data.role.present ? data.role.value : this.role,
      label: data.label.present ? data.label.value : this.label,
      requestCount: data.requestCount.present
          ? data.requestCount.value
          : this.requestCount,
      errorCount: data.errorCount.present
          ? data.errorCount.value
          : this.errorCount,
      truncatedCount: data.truncatedCount.present
          ? data.truncatedCount.value
          : this.truncatedCount,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      promptTokens: data.promptTokens.present
          ? data.promptTokens.value
          : this.promptTokens,
      completionTokens: data.completionTokens.present
          ? data.completionTokens.value
          : this.completionTokens,
      totalTokens: data.totalTokens.present
          ? data.totalTokens.value
          : this.totalTokens,
      cachedPromptTokens: data.cachedPromptTokens.present
          ? data.cachedPromptTokens.value
          : this.cachedPromptTokens,
      audioPromptTokens: data.audioPromptTokens.present
          ? data.audioPromptTokens.value
          : this.audioPromptTokens,
      reasoningTokens: data.reasoningTokens.present
          ? data.reasoningTokens.value
          : this.reasoningTokens,
      audioCompletionTokens: data.audioCompletionTokens.present
          ? data.audioCompletionTokens.value
          : this.audioCompletionTokens,
      acceptedPredictionTokens: data.acceptedPredictionTokens.present
          ? data.acceptedPredictionTokens.value
          : this.acceptedPredictionTokens,
      rejectedPredictionTokens: data.rejectedPredictionTokens.present
          ? data.rejectedPredictionTokens.value
          : this.rejectedPredictionTokens,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ModelUsageDailyRow(')
          ..write('dayNumber: $dayNumber, ')
          ..write('model: $model, ')
          ..write('endpointId: $endpointId, ')
          ..write('role: $role, ')
          ..write('label: $label, ')
          ..write('requestCount: $requestCount, ')
          ..write('errorCount: $errorCount, ')
          ..write('truncatedCount: $truncatedCount, ')
          ..write('durationMs: $durationMs, ')
          ..write('promptTokens: $promptTokens, ')
          ..write('completionTokens: $completionTokens, ')
          ..write('totalTokens: $totalTokens, ')
          ..write('cachedPromptTokens: $cachedPromptTokens, ')
          ..write('audioPromptTokens: $audioPromptTokens, ')
          ..write('reasoningTokens: $reasoningTokens, ')
          ..write('audioCompletionTokens: $audioCompletionTokens, ')
          ..write('acceptedPredictionTokens: $acceptedPredictionTokens, ')
          ..write('rejectedPredictionTokens: $rejectedPredictionTokens')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    dayNumber,
    model,
    endpointId,
    role,
    label,
    requestCount,
    errorCount,
    truncatedCount,
    durationMs,
    promptTokens,
    completionTokens,
    totalTokens,
    cachedPromptTokens,
    audioPromptTokens,
    reasoningTokens,
    audioCompletionTokens,
    acceptedPredictionTokens,
    rejectedPredictionTokens,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ModelUsageDailyRow &&
          other.dayNumber == this.dayNumber &&
          other.model == this.model &&
          other.endpointId == this.endpointId &&
          other.role == this.role &&
          other.label == this.label &&
          other.requestCount == this.requestCount &&
          other.errorCount == this.errorCount &&
          other.truncatedCount == this.truncatedCount &&
          other.durationMs == this.durationMs &&
          other.promptTokens == this.promptTokens &&
          other.completionTokens == this.completionTokens &&
          other.totalTokens == this.totalTokens &&
          other.cachedPromptTokens == this.cachedPromptTokens &&
          other.audioPromptTokens == this.audioPromptTokens &&
          other.reasoningTokens == this.reasoningTokens &&
          other.audioCompletionTokens == this.audioCompletionTokens &&
          other.acceptedPredictionTokens == this.acceptedPredictionTokens &&
          other.rejectedPredictionTokens == this.rejectedPredictionTokens);
}

class ModelUsageDailyCompanion extends UpdateCompanion<ModelUsageDailyRow> {
  final Value<int> dayNumber;
  final Value<String> model;
  final Value<String> endpointId;
  final Value<String> role;
  final Value<String> label;
  final Value<int> requestCount;
  final Value<int> errorCount;
  final Value<int> truncatedCount;
  final Value<int> durationMs;
  final Value<int> promptTokens;
  final Value<int> completionTokens;
  final Value<int> totalTokens;
  final Value<int> cachedPromptTokens;
  final Value<int> audioPromptTokens;
  final Value<int> reasoningTokens;
  final Value<int> audioCompletionTokens;
  final Value<int> acceptedPredictionTokens;
  final Value<int> rejectedPredictionTokens;
  final Value<int> rowid;
  const ModelUsageDailyCompanion({
    this.dayNumber = const Value.absent(),
    this.model = const Value.absent(),
    this.endpointId = const Value.absent(),
    this.role = const Value.absent(),
    this.label = const Value.absent(),
    this.requestCount = const Value.absent(),
    this.errorCount = const Value.absent(),
    this.truncatedCount = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.promptTokens = const Value.absent(),
    this.completionTokens = const Value.absent(),
    this.totalTokens = const Value.absent(),
    this.cachedPromptTokens = const Value.absent(),
    this.audioPromptTokens = const Value.absent(),
    this.reasoningTokens = const Value.absent(),
    this.audioCompletionTokens = const Value.absent(),
    this.acceptedPredictionTokens = const Value.absent(),
    this.rejectedPredictionTokens = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ModelUsageDailyCompanion.insert({
    required int dayNumber,
    required String model,
    this.endpointId = const Value.absent(),
    this.role = const Value.absent(),
    this.label = const Value.absent(),
    this.requestCount = const Value.absent(),
    this.errorCount = const Value.absent(),
    this.truncatedCount = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.promptTokens = const Value.absent(),
    this.completionTokens = const Value.absent(),
    this.totalTokens = const Value.absent(),
    this.cachedPromptTokens = const Value.absent(),
    this.audioPromptTokens = const Value.absent(),
    this.reasoningTokens = const Value.absent(),
    this.audioCompletionTokens = const Value.absent(),
    this.acceptedPredictionTokens = const Value.absent(),
    this.rejectedPredictionTokens = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : dayNumber = Value(dayNumber),
       model = Value(model);
  static Insertable<ModelUsageDailyRow> custom({
    Expression<int>? dayNumber,
    Expression<String>? model,
    Expression<String>? endpointId,
    Expression<String>? role,
    Expression<String>? label,
    Expression<int>? requestCount,
    Expression<int>? errorCount,
    Expression<int>? truncatedCount,
    Expression<int>? durationMs,
    Expression<int>? promptTokens,
    Expression<int>? completionTokens,
    Expression<int>? totalTokens,
    Expression<int>? cachedPromptTokens,
    Expression<int>? audioPromptTokens,
    Expression<int>? reasoningTokens,
    Expression<int>? audioCompletionTokens,
    Expression<int>? acceptedPredictionTokens,
    Expression<int>? rejectedPredictionTokens,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (dayNumber != null) 'day_number': dayNumber,
      if (model != null) 'model': model,
      if (endpointId != null) 'endpoint_id': endpointId,
      if (role != null) 'role': role,
      if (label != null) 'label': label,
      if (requestCount != null) 'request_count': requestCount,
      if (errorCount != null) 'error_count': errorCount,
      if (truncatedCount != null) 'truncated_count': truncatedCount,
      if (durationMs != null) 'duration_ms': durationMs,
      if (promptTokens != null) 'prompt_tokens': promptTokens,
      if (completionTokens != null) 'completion_tokens': completionTokens,
      if (totalTokens != null) 'total_tokens': totalTokens,
      if (cachedPromptTokens != null)
        'cached_prompt_tokens': cachedPromptTokens,
      if (audioPromptTokens != null) 'audio_prompt_tokens': audioPromptTokens,
      if (reasoningTokens != null) 'reasoning_tokens': reasoningTokens,
      if (audioCompletionTokens != null)
        'audio_completion_tokens': audioCompletionTokens,
      if (acceptedPredictionTokens != null)
        'accepted_prediction_tokens': acceptedPredictionTokens,
      if (rejectedPredictionTokens != null)
        'rejected_prediction_tokens': rejectedPredictionTokens,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ModelUsageDailyCompanion copyWith({
    Value<int>? dayNumber,
    Value<String>? model,
    Value<String>? endpointId,
    Value<String>? role,
    Value<String>? label,
    Value<int>? requestCount,
    Value<int>? errorCount,
    Value<int>? truncatedCount,
    Value<int>? durationMs,
    Value<int>? promptTokens,
    Value<int>? completionTokens,
    Value<int>? totalTokens,
    Value<int>? cachedPromptTokens,
    Value<int>? audioPromptTokens,
    Value<int>? reasoningTokens,
    Value<int>? audioCompletionTokens,
    Value<int>? acceptedPredictionTokens,
    Value<int>? rejectedPredictionTokens,
    Value<int>? rowid,
  }) {
    return ModelUsageDailyCompanion(
      dayNumber: dayNumber ?? this.dayNumber,
      model: model ?? this.model,
      endpointId: endpointId ?? this.endpointId,
      role: role ?? this.role,
      label: label ?? this.label,
      requestCount: requestCount ?? this.requestCount,
      errorCount: errorCount ?? this.errorCount,
      truncatedCount: truncatedCount ?? this.truncatedCount,
      durationMs: durationMs ?? this.durationMs,
      promptTokens: promptTokens ?? this.promptTokens,
      completionTokens: completionTokens ?? this.completionTokens,
      totalTokens: totalTokens ?? this.totalTokens,
      cachedPromptTokens: cachedPromptTokens ?? this.cachedPromptTokens,
      audioPromptTokens: audioPromptTokens ?? this.audioPromptTokens,
      reasoningTokens: reasoningTokens ?? this.reasoningTokens,
      audioCompletionTokens:
          audioCompletionTokens ?? this.audioCompletionTokens,
      acceptedPredictionTokens:
          acceptedPredictionTokens ?? this.acceptedPredictionTokens,
      rejectedPredictionTokens:
          rejectedPredictionTokens ?? this.rejectedPredictionTokens,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (dayNumber.present) {
      map['day_number'] = Variable<int>(dayNumber.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (endpointId.present) {
      map['endpoint_id'] = Variable<String>(endpointId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (requestCount.present) {
      map['request_count'] = Variable<int>(requestCount.value);
    }
    if (errorCount.present) {
      map['error_count'] = Variable<int>(errorCount.value);
    }
    if (truncatedCount.present) {
      map['truncated_count'] = Variable<int>(truncatedCount.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (promptTokens.present) {
      map['prompt_tokens'] = Variable<int>(promptTokens.value);
    }
    if (completionTokens.present) {
      map['completion_tokens'] = Variable<int>(completionTokens.value);
    }
    if (totalTokens.present) {
      map['total_tokens'] = Variable<int>(totalTokens.value);
    }
    if (cachedPromptTokens.present) {
      map['cached_prompt_tokens'] = Variable<int>(cachedPromptTokens.value);
    }
    if (audioPromptTokens.present) {
      map['audio_prompt_tokens'] = Variable<int>(audioPromptTokens.value);
    }
    if (reasoningTokens.present) {
      map['reasoning_tokens'] = Variable<int>(reasoningTokens.value);
    }
    if (audioCompletionTokens.present) {
      map['audio_completion_tokens'] = Variable<int>(
        audioCompletionTokens.value,
      );
    }
    if (acceptedPredictionTokens.present) {
      map['accepted_prediction_tokens'] = Variable<int>(
        acceptedPredictionTokens.value,
      );
    }
    if (rejectedPredictionTokens.present) {
      map['rejected_prediction_tokens'] = Variable<int>(
        rejectedPredictionTokens.value,
      );
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ModelUsageDailyCompanion(')
          ..write('dayNumber: $dayNumber, ')
          ..write('model: $model, ')
          ..write('endpointId: $endpointId, ')
          ..write('role: $role, ')
          ..write('label: $label, ')
          ..write('requestCount: $requestCount, ')
          ..write('errorCount: $errorCount, ')
          ..write('truncatedCount: $truncatedCount, ')
          ..write('durationMs: $durationMs, ')
          ..write('promptTokens: $promptTokens, ')
          ..write('completionTokens: $completionTokens, ')
          ..write('totalTokens: $totalTokens, ')
          ..write('cachedPromptTokens: $cachedPromptTokens, ')
          ..write('audioPromptTokens: $audioPromptTokens, ')
          ..write('reasoningTokens: $reasoningTokens, ')
          ..write('audioCompletionTokens: $audioCompletionTokens, ')
          ..write('acceptedPredictionTokens: $acceptedPredictionTokens, ')
          ..write('rejectedPredictionTokens: $rejectedPredictionTokens, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $Rag2StoreMetaTable extends Rag2StoreMeta
    with TableInfo<$Rag2StoreMetaTable, Rag2StoreMetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Rag2StoreMetaTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'rag2_store_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<Rag2StoreMetaRow> instance, {
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
  Rag2StoreMetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Rag2StoreMetaRow(
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
  $Rag2StoreMetaTable createAlias(String alias) {
    return $Rag2StoreMetaTable(attachedDatabase, alias);
  }
}

class Rag2StoreMetaRow extends DataClass
    implements Insertable<Rag2StoreMetaRow> {
  final String key;
  final String value;
  const Rag2StoreMetaRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  Rag2StoreMetaCompanion toCompanion(bool nullToAbsent) {
    return Rag2StoreMetaCompanion(key: Value(key), value: Value(value));
  }

  factory Rag2StoreMetaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Rag2StoreMetaRow(
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

  Rag2StoreMetaRow copyWith({String? key, String? value}) =>
      Rag2StoreMetaRow(key: key ?? this.key, value: value ?? this.value);
  Rag2StoreMetaRow copyWithCompanion(Rag2StoreMetaCompanion data) {
    return Rag2StoreMetaRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Rag2StoreMetaRow(')
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
      (other is Rag2StoreMetaRow &&
          other.key == this.key &&
          other.value == this.value);
}

class Rag2StoreMetaCompanion extends UpdateCompanion<Rag2StoreMetaRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const Rag2StoreMetaCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  Rag2StoreMetaCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Rag2StoreMetaRow> custom({
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

  Rag2StoreMetaCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return Rag2StoreMetaCompanion(
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
    return (StringBuffer('Rag2StoreMetaCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $Rag2GenerationsTable extends Rag2Generations
    with TableInfo<$Rag2GenerationsTable, Rag2GenerationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $Rag2GenerationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _projectIdentityMeta = const VerificationMeta(
    'projectIdentity',
  );
  @override
  late final GeneratedColumn<String> projectIdentity = GeneratedColumn<String>(
    'project_identity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _declarationIdentityMeta =
      const VerificationMeta('declarationIdentity');
  @override
  late final GeneratedColumn<String> declarationIdentity =
      GeneratedColumn<String>(
        'declaration_identity',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _schemaNameMeta = const VerificationMeta(
    'schemaName',
  );
  @override
  late final GeneratedColumn<String> schemaName = GeneratedColumn<String>(
    'schema_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contractMeta = const VerificationMeta(
    'contract',
  );
  @override
  late final GeneratedColumn<String> contract = GeneratedColumn<String>(
    'contract',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _generationMeta = const VerificationMeta(
    'generation',
  );
  @override
  late final GeneratedColumn<int> generation = GeneratedColumn<int>(
    'generation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotHashMeta = const VerificationMeta(
    'snapshotHash',
  );
  @override
  late final GeneratedColumn<String> snapshotHash = GeneratedColumn<String>(
    'snapshot_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    projectIdentity,
    declarationIdentity,
    schemaName,
    schemaVersion,
    contract,
    projectId,
    generation,
    snapshotHash,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rag2_generations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Rag2GenerationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('project_identity')) {
      context.handle(
        _projectIdentityMeta,
        projectIdentity.isAcceptableOrUnknown(
          data['project_identity']!,
          _projectIdentityMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_projectIdentityMeta);
    }
    if (data.containsKey('declaration_identity')) {
      context.handle(
        _declarationIdentityMeta,
        declarationIdentity.isAcceptableOrUnknown(
          data['declaration_identity']!,
          _declarationIdentityMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_declarationIdentityMeta);
    }
    if (data.containsKey('schema_name')) {
      context.handle(
        _schemaNameMeta,
        schemaName.isAcceptableOrUnknown(data['schema_name']!, _schemaNameMeta),
      );
    } else if (isInserting) {
      context.missing(_schemaNameMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schema_version']!,
          _schemaVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_schemaVersionMeta);
    }
    if (data.containsKey('contract')) {
      context.handle(
        _contractMeta,
        contract.isAcceptableOrUnknown(data['contract']!, _contractMeta),
      );
    } else if (isInserting) {
      context.missing(_contractMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('generation')) {
      context.handle(
        _generationMeta,
        generation.isAcceptableOrUnknown(data['generation']!, _generationMeta),
      );
    } else if (isInserting) {
      context.missing(_generationMeta);
    }
    if (data.containsKey('snapshot_hash')) {
      context.handle(
        _snapshotHashMeta,
        snapshotHash.isAcceptableOrUnknown(
          data['snapshot_hash']!,
          _snapshotHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotHashMeta);
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
  Set<GeneratedColumn> get $primaryKey => {
    projectIdentity,
    declarationIdentity,
  };
  @override
  Rag2GenerationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Rag2GenerationRow(
      projectIdentity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_identity'],
      )!,
      declarationIdentity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}declaration_identity'],
      )!,
      schemaName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}schema_name'],
      )!,
      schemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_version'],
      )!,
      contract: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contract'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      generation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}generation'],
      )!,
      snapshotHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_hash'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $Rag2GenerationsTable createAlias(String alias) {
    return $Rag2GenerationsTable(attachedDatabase, alias);
  }
}

class Rag2GenerationRow extends DataClass
    implements Insertable<Rag2GenerationRow> {
  final String projectIdentity;
  final String declarationIdentity;
  final String schemaName;
  final int schemaVersion;
  final String contract;
  final String projectId;
  final int generation;
  final String snapshotHash;
  final String payload;
  const Rag2GenerationRow({
    required this.projectIdentity,
    required this.declarationIdentity,
    required this.schemaName,
    required this.schemaVersion,
    required this.contract,
    required this.projectId,
    required this.generation,
    required this.snapshotHash,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['project_identity'] = Variable<String>(projectIdentity);
    map['declaration_identity'] = Variable<String>(declarationIdentity);
    map['schema_name'] = Variable<String>(schemaName);
    map['schema_version'] = Variable<int>(schemaVersion);
    map['contract'] = Variable<String>(contract);
    map['project_id'] = Variable<String>(projectId);
    map['generation'] = Variable<int>(generation);
    map['snapshot_hash'] = Variable<String>(snapshotHash);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  Rag2GenerationsCompanion toCompanion(bool nullToAbsent) {
    return Rag2GenerationsCompanion(
      projectIdentity: Value(projectIdentity),
      declarationIdentity: Value(declarationIdentity),
      schemaName: Value(schemaName),
      schemaVersion: Value(schemaVersion),
      contract: Value(contract),
      projectId: Value(projectId),
      generation: Value(generation),
      snapshotHash: Value(snapshotHash),
      payload: Value(payload),
    );
  }

  factory Rag2GenerationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Rag2GenerationRow(
      projectIdentity: serializer.fromJson<String>(json['projectIdentity']),
      declarationIdentity: serializer.fromJson<String>(
        json['declarationIdentity'],
      ),
      schemaName: serializer.fromJson<String>(json['schemaName']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      contract: serializer.fromJson<String>(json['contract']),
      projectId: serializer.fromJson<String>(json['projectId']),
      generation: serializer.fromJson<int>(json['generation']),
      snapshotHash: serializer.fromJson<String>(json['snapshotHash']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'projectIdentity': serializer.toJson<String>(projectIdentity),
      'declarationIdentity': serializer.toJson<String>(declarationIdentity),
      'schemaName': serializer.toJson<String>(schemaName),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'contract': serializer.toJson<String>(contract),
      'projectId': serializer.toJson<String>(projectId),
      'generation': serializer.toJson<int>(generation),
      'snapshotHash': serializer.toJson<String>(snapshotHash),
      'payload': serializer.toJson<String>(payload),
    };
  }

  Rag2GenerationRow copyWith({
    String? projectIdentity,
    String? declarationIdentity,
    String? schemaName,
    int? schemaVersion,
    String? contract,
    String? projectId,
    int? generation,
    String? snapshotHash,
    String? payload,
  }) => Rag2GenerationRow(
    projectIdentity: projectIdentity ?? this.projectIdentity,
    declarationIdentity: declarationIdentity ?? this.declarationIdentity,
    schemaName: schemaName ?? this.schemaName,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    contract: contract ?? this.contract,
    projectId: projectId ?? this.projectId,
    generation: generation ?? this.generation,
    snapshotHash: snapshotHash ?? this.snapshotHash,
    payload: payload ?? this.payload,
  );
  Rag2GenerationRow copyWithCompanion(Rag2GenerationsCompanion data) {
    return Rag2GenerationRow(
      projectIdentity: data.projectIdentity.present
          ? data.projectIdentity.value
          : this.projectIdentity,
      declarationIdentity: data.declarationIdentity.present
          ? data.declarationIdentity.value
          : this.declarationIdentity,
      schemaName: data.schemaName.present
          ? data.schemaName.value
          : this.schemaName,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      contract: data.contract.present ? data.contract.value : this.contract,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      generation: data.generation.present
          ? data.generation.value
          : this.generation,
      snapshotHash: data.snapshotHash.present
          ? data.snapshotHash.value
          : this.snapshotHash,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Rag2GenerationRow(')
          ..write('projectIdentity: $projectIdentity, ')
          ..write('declarationIdentity: $declarationIdentity, ')
          ..write('schemaName: $schemaName, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('contract: $contract, ')
          ..write('projectId: $projectId, ')
          ..write('generation: $generation, ')
          ..write('snapshotHash: $snapshotHash, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    projectIdentity,
    declarationIdentity,
    schemaName,
    schemaVersion,
    contract,
    projectId,
    generation,
    snapshotHash,
    payload,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Rag2GenerationRow &&
          other.projectIdentity == this.projectIdentity &&
          other.declarationIdentity == this.declarationIdentity &&
          other.schemaName == this.schemaName &&
          other.schemaVersion == this.schemaVersion &&
          other.contract == this.contract &&
          other.projectId == this.projectId &&
          other.generation == this.generation &&
          other.snapshotHash == this.snapshotHash &&
          other.payload == this.payload);
}

class Rag2GenerationsCompanion extends UpdateCompanion<Rag2GenerationRow> {
  final Value<String> projectIdentity;
  final Value<String> declarationIdentity;
  final Value<String> schemaName;
  final Value<int> schemaVersion;
  final Value<String> contract;
  final Value<String> projectId;
  final Value<int> generation;
  final Value<String> snapshotHash;
  final Value<String> payload;
  final Value<int> rowid;
  const Rag2GenerationsCompanion({
    this.projectIdentity = const Value.absent(),
    this.declarationIdentity = const Value.absent(),
    this.schemaName = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.contract = const Value.absent(),
    this.projectId = const Value.absent(),
    this.generation = const Value.absent(),
    this.snapshotHash = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  Rag2GenerationsCompanion.insert({
    required String projectIdentity,
    required String declarationIdentity,
    required String schemaName,
    required int schemaVersion,
    required String contract,
    required String projectId,
    required int generation,
    required String snapshotHash,
    required String payload,
    this.rowid = const Value.absent(),
  }) : projectIdentity = Value(projectIdentity),
       declarationIdentity = Value(declarationIdentity),
       schemaName = Value(schemaName),
       schemaVersion = Value(schemaVersion),
       contract = Value(contract),
       projectId = Value(projectId),
       generation = Value(generation),
       snapshotHash = Value(snapshotHash),
       payload = Value(payload);
  static Insertable<Rag2GenerationRow> custom({
    Expression<String>? projectIdentity,
    Expression<String>? declarationIdentity,
    Expression<String>? schemaName,
    Expression<int>? schemaVersion,
    Expression<String>? contract,
    Expression<String>? projectId,
    Expression<int>? generation,
    Expression<String>? snapshotHash,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (projectIdentity != null) 'project_identity': projectIdentity,
      if (declarationIdentity != null)
        'declaration_identity': declarationIdentity,
      if (schemaName != null) 'schema_name': schemaName,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (contract != null) 'contract': contract,
      if (projectId != null) 'project_id': projectId,
      if (generation != null) 'generation': generation,
      if (snapshotHash != null) 'snapshot_hash': snapshotHash,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  Rag2GenerationsCompanion copyWith({
    Value<String>? projectIdentity,
    Value<String>? declarationIdentity,
    Value<String>? schemaName,
    Value<int>? schemaVersion,
    Value<String>? contract,
    Value<String>? projectId,
    Value<int>? generation,
    Value<String>? snapshotHash,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return Rag2GenerationsCompanion(
      projectIdentity: projectIdentity ?? this.projectIdentity,
      declarationIdentity: declarationIdentity ?? this.declarationIdentity,
      schemaName: schemaName ?? this.schemaName,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      contract: contract ?? this.contract,
      projectId: projectId ?? this.projectId,
      generation: generation ?? this.generation,
      snapshotHash: snapshotHash ?? this.snapshotHash,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (projectIdentity.present) {
      map['project_identity'] = Variable<String>(projectIdentity.value);
    }
    if (declarationIdentity.present) {
      map['declaration_identity'] = Variable<String>(declarationIdentity.value);
    }
    if (schemaName.present) {
      map['schema_name'] = Variable<String>(schemaName.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (contract.present) {
      map['contract'] = Variable<String>(contract.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (generation.present) {
      map['generation'] = Variable<int>(generation.value);
    }
    if (snapshotHash.present) {
      map['snapshot_hash'] = Variable<String>(snapshotHash.value);
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
    return (StringBuffer('Rag2GenerationsCompanion(')
          ..write('projectIdentity: $projectIdentity, ')
          ..write('declarationIdentity: $declarationIdentity, ')
          ..write('schemaName: $schemaName, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('contract: $contract, ')
          ..write('projectId: $projectId, ')
          ..write('generation: $generation, ')
          ..write('snapshotHash: $snapshotHash, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
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
  late final $ModelUsageDailyTable modelUsageDaily = $ModelUsageDailyTable(
    this,
  );
  late final $Rag2StoreMetaTable rag2StoreMeta = $Rag2StoreMetaTable(this);
  late final $Rag2GenerationsTable rag2Generations = $Rag2GenerationsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    conversations,
    chatMemoryEntries,
    embeddings,
    modelUsageDaily,
    rag2StoreMeta,
    rag2Generations,
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
typedef $$ModelUsageDailyTableCreateCompanionBuilder =
    ModelUsageDailyCompanion Function({
      required int dayNumber,
      required String model,
      Value<String> endpointId,
      Value<String> role,
      Value<String> label,
      Value<int> requestCount,
      Value<int> errorCount,
      Value<int> truncatedCount,
      Value<int> durationMs,
      Value<int> promptTokens,
      Value<int> completionTokens,
      Value<int> totalTokens,
      Value<int> cachedPromptTokens,
      Value<int> audioPromptTokens,
      Value<int> reasoningTokens,
      Value<int> audioCompletionTokens,
      Value<int> acceptedPredictionTokens,
      Value<int> rejectedPredictionTokens,
      Value<int> rowid,
    });
typedef $$ModelUsageDailyTableUpdateCompanionBuilder =
    ModelUsageDailyCompanion Function({
      Value<int> dayNumber,
      Value<String> model,
      Value<String> endpointId,
      Value<String> role,
      Value<String> label,
      Value<int> requestCount,
      Value<int> errorCount,
      Value<int> truncatedCount,
      Value<int> durationMs,
      Value<int> promptTokens,
      Value<int> completionTokens,
      Value<int> totalTokens,
      Value<int> cachedPromptTokens,
      Value<int> audioPromptTokens,
      Value<int> reasoningTokens,
      Value<int> audioCompletionTokens,
      Value<int> acceptedPredictionTokens,
      Value<int> rejectedPredictionTokens,
      Value<int> rowid,
    });

class $$ModelUsageDailyTableFilterComposer
    extends Composer<_$AppDatabase, $ModelUsageDailyTable> {
  $$ModelUsageDailyTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get dayNumber => $composableBuilder(
    column: $table.dayNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get endpointId => $composableBuilder(
    column: $table.endpointId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get requestCount => $composableBuilder(
    column: $table.requestCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get errorCount => $composableBuilder(
    column: $table.errorCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get truncatedCount => $composableBuilder(
    column: $table.truncatedCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get promptTokens => $composableBuilder(
    column: $table.promptTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get completionTokens => $composableBuilder(
    column: $table.completionTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalTokens => $composableBuilder(
    column: $table.totalTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cachedPromptTokens => $composableBuilder(
    column: $table.cachedPromptTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get audioPromptTokens => $composableBuilder(
    column: $table.audioPromptTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reasoningTokens => $composableBuilder(
    column: $table.reasoningTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get audioCompletionTokens => $composableBuilder(
    column: $table.audioCompletionTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get acceptedPredictionTokens => $composableBuilder(
    column: $table.acceptedPredictionTokens,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rejectedPredictionTokens => $composableBuilder(
    column: $table.rejectedPredictionTokens,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ModelUsageDailyTableOrderingComposer
    extends Composer<_$AppDatabase, $ModelUsageDailyTable> {
  $$ModelUsageDailyTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get dayNumber => $composableBuilder(
    column: $table.dayNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get endpointId => $composableBuilder(
    column: $table.endpointId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get requestCount => $composableBuilder(
    column: $table.requestCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get errorCount => $composableBuilder(
    column: $table.errorCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get truncatedCount => $composableBuilder(
    column: $table.truncatedCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get promptTokens => $composableBuilder(
    column: $table.promptTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get completionTokens => $composableBuilder(
    column: $table.completionTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalTokens => $composableBuilder(
    column: $table.totalTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cachedPromptTokens => $composableBuilder(
    column: $table.cachedPromptTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get audioPromptTokens => $composableBuilder(
    column: $table.audioPromptTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reasoningTokens => $composableBuilder(
    column: $table.reasoningTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get audioCompletionTokens => $composableBuilder(
    column: $table.audioCompletionTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get acceptedPredictionTokens => $composableBuilder(
    column: $table.acceptedPredictionTokens,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rejectedPredictionTokens => $composableBuilder(
    column: $table.rejectedPredictionTokens,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ModelUsageDailyTableAnnotationComposer
    extends Composer<_$AppDatabase, $ModelUsageDailyTable> {
  $$ModelUsageDailyTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get dayNumber =>
      $composableBuilder(column: $table.dayNumber, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get endpointId => $composableBuilder(
    column: $table.endpointId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<int> get requestCount => $composableBuilder(
    column: $table.requestCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get errorCount => $composableBuilder(
    column: $table.errorCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get truncatedCount => $composableBuilder(
    column: $table.truncatedCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get promptTokens => $composableBuilder(
    column: $table.promptTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get completionTokens => $composableBuilder(
    column: $table.completionTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalTokens => $composableBuilder(
    column: $table.totalTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get cachedPromptTokens => $composableBuilder(
    column: $table.cachedPromptTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get audioPromptTokens => $composableBuilder(
    column: $table.audioPromptTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reasoningTokens => $composableBuilder(
    column: $table.reasoningTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get audioCompletionTokens => $composableBuilder(
    column: $table.audioCompletionTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get acceptedPredictionTokens => $composableBuilder(
    column: $table.acceptedPredictionTokens,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rejectedPredictionTokens => $composableBuilder(
    column: $table.rejectedPredictionTokens,
    builder: (column) => column,
  );
}

class $$ModelUsageDailyTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ModelUsageDailyTable,
          ModelUsageDailyRow,
          $$ModelUsageDailyTableFilterComposer,
          $$ModelUsageDailyTableOrderingComposer,
          $$ModelUsageDailyTableAnnotationComposer,
          $$ModelUsageDailyTableCreateCompanionBuilder,
          $$ModelUsageDailyTableUpdateCompanionBuilder,
          (
            ModelUsageDailyRow,
            BaseReferences<
              _$AppDatabase,
              $ModelUsageDailyTable,
              ModelUsageDailyRow
            >,
          ),
          ModelUsageDailyRow,
          PrefetchHooks Function()
        > {
  $$ModelUsageDailyTableTableManager(
    _$AppDatabase db,
    $ModelUsageDailyTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ModelUsageDailyTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ModelUsageDailyTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ModelUsageDailyTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> dayNumber = const Value.absent(),
                Value<String> model = const Value.absent(),
                Value<String> endpointId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<int> requestCount = const Value.absent(),
                Value<int> errorCount = const Value.absent(),
                Value<int> truncatedCount = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<int> promptTokens = const Value.absent(),
                Value<int> completionTokens = const Value.absent(),
                Value<int> totalTokens = const Value.absent(),
                Value<int> cachedPromptTokens = const Value.absent(),
                Value<int> audioPromptTokens = const Value.absent(),
                Value<int> reasoningTokens = const Value.absent(),
                Value<int> audioCompletionTokens = const Value.absent(),
                Value<int> acceptedPredictionTokens = const Value.absent(),
                Value<int> rejectedPredictionTokens = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ModelUsageDailyCompanion(
                dayNumber: dayNumber,
                model: model,
                endpointId: endpointId,
                role: role,
                label: label,
                requestCount: requestCount,
                errorCount: errorCount,
                truncatedCount: truncatedCount,
                durationMs: durationMs,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                totalTokens: totalTokens,
                cachedPromptTokens: cachedPromptTokens,
                audioPromptTokens: audioPromptTokens,
                reasoningTokens: reasoningTokens,
                audioCompletionTokens: audioCompletionTokens,
                acceptedPredictionTokens: acceptedPredictionTokens,
                rejectedPredictionTokens: rejectedPredictionTokens,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int dayNumber,
                required String model,
                Value<String> endpointId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<int> requestCount = const Value.absent(),
                Value<int> errorCount = const Value.absent(),
                Value<int> truncatedCount = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<int> promptTokens = const Value.absent(),
                Value<int> completionTokens = const Value.absent(),
                Value<int> totalTokens = const Value.absent(),
                Value<int> cachedPromptTokens = const Value.absent(),
                Value<int> audioPromptTokens = const Value.absent(),
                Value<int> reasoningTokens = const Value.absent(),
                Value<int> audioCompletionTokens = const Value.absent(),
                Value<int> acceptedPredictionTokens = const Value.absent(),
                Value<int> rejectedPredictionTokens = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ModelUsageDailyCompanion.insert(
                dayNumber: dayNumber,
                model: model,
                endpointId: endpointId,
                role: role,
                label: label,
                requestCount: requestCount,
                errorCount: errorCount,
                truncatedCount: truncatedCount,
                durationMs: durationMs,
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                totalTokens: totalTokens,
                cachedPromptTokens: cachedPromptTokens,
                audioPromptTokens: audioPromptTokens,
                reasoningTokens: reasoningTokens,
                audioCompletionTokens: audioCompletionTokens,
                acceptedPredictionTokens: acceptedPredictionTokens,
                rejectedPredictionTokens: rejectedPredictionTokens,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ModelUsageDailyTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ModelUsageDailyTable,
      ModelUsageDailyRow,
      $$ModelUsageDailyTableFilterComposer,
      $$ModelUsageDailyTableOrderingComposer,
      $$ModelUsageDailyTableAnnotationComposer,
      $$ModelUsageDailyTableCreateCompanionBuilder,
      $$ModelUsageDailyTableUpdateCompanionBuilder,
      (
        ModelUsageDailyRow,
        BaseReferences<
          _$AppDatabase,
          $ModelUsageDailyTable,
          ModelUsageDailyRow
        >,
      ),
      ModelUsageDailyRow,
      PrefetchHooks Function()
    >;
typedef $$Rag2StoreMetaTableCreateCompanionBuilder =
    Rag2StoreMetaCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$Rag2StoreMetaTableUpdateCompanionBuilder =
    Rag2StoreMetaCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$Rag2StoreMetaTableFilterComposer
    extends Composer<_$AppDatabase, $Rag2StoreMetaTable> {
  $$Rag2StoreMetaTableFilterComposer({
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

class $$Rag2StoreMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $Rag2StoreMetaTable> {
  $$Rag2StoreMetaTableOrderingComposer({
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

class $$Rag2StoreMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $Rag2StoreMetaTable> {
  $$Rag2StoreMetaTableAnnotationComposer({
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

class $$Rag2StoreMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $Rag2StoreMetaTable,
          Rag2StoreMetaRow,
          $$Rag2StoreMetaTableFilterComposer,
          $$Rag2StoreMetaTableOrderingComposer,
          $$Rag2StoreMetaTableAnnotationComposer,
          $$Rag2StoreMetaTableCreateCompanionBuilder,
          $$Rag2StoreMetaTableUpdateCompanionBuilder,
          (
            Rag2StoreMetaRow,
            BaseReferences<
              _$AppDatabase,
              $Rag2StoreMetaTable,
              Rag2StoreMetaRow
            >,
          ),
          Rag2StoreMetaRow,
          PrefetchHooks Function()
        > {
  $$Rag2StoreMetaTableTableManager(_$AppDatabase db, $Rag2StoreMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$Rag2StoreMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$Rag2StoreMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$Rag2StoreMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) =>
                  Rag2StoreMetaCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => Rag2StoreMetaCompanion.insert(
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

typedef $$Rag2StoreMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $Rag2StoreMetaTable,
      Rag2StoreMetaRow,
      $$Rag2StoreMetaTableFilterComposer,
      $$Rag2StoreMetaTableOrderingComposer,
      $$Rag2StoreMetaTableAnnotationComposer,
      $$Rag2StoreMetaTableCreateCompanionBuilder,
      $$Rag2StoreMetaTableUpdateCompanionBuilder,
      (
        Rag2StoreMetaRow,
        BaseReferences<_$AppDatabase, $Rag2StoreMetaTable, Rag2StoreMetaRow>,
      ),
      Rag2StoreMetaRow,
      PrefetchHooks Function()
    >;
typedef $$Rag2GenerationsTableCreateCompanionBuilder =
    Rag2GenerationsCompanion Function({
      required String projectIdentity,
      required String declarationIdentity,
      required String schemaName,
      required int schemaVersion,
      required String contract,
      required String projectId,
      required int generation,
      required String snapshotHash,
      required String payload,
      Value<int> rowid,
    });
typedef $$Rag2GenerationsTableUpdateCompanionBuilder =
    Rag2GenerationsCompanion Function({
      Value<String> projectIdentity,
      Value<String> declarationIdentity,
      Value<String> schemaName,
      Value<int> schemaVersion,
      Value<String> contract,
      Value<String> projectId,
      Value<int> generation,
      Value<String> snapshotHash,
      Value<String> payload,
      Value<int> rowid,
    });

class $$Rag2GenerationsTableFilterComposer
    extends Composer<_$AppDatabase, $Rag2GenerationsTable> {
  $$Rag2GenerationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get projectIdentity => $composableBuilder(
    column: $table.projectIdentity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get declarationIdentity => $composableBuilder(
    column: $table.declarationIdentity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get schemaName => $composableBuilder(
    column: $table.schemaName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contract => $composableBuilder(
    column: $table.contract,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshotHash => $composableBuilder(
    column: $table.snapshotHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$Rag2GenerationsTableOrderingComposer
    extends Composer<_$AppDatabase, $Rag2GenerationsTable> {
  $$Rag2GenerationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get projectIdentity => $composableBuilder(
    column: $table.projectIdentity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get declarationIdentity => $composableBuilder(
    column: $table.declarationIdentity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get schemaName => $composableBuilder(
    column: $table.schemaName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contract => $composableBuilder(
    column: $table.contract,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshotHash => $composableBuilder(
    column: $table.snapshotHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$Rag2GenerationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $Rag2GenerationsTable> {
  $$Rag2GenerationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get projectIdentity => $composableBuilder(
    column: $table.projectIdentity,
    builder: (column) => column,
  );

  GeneratedColumn<String> get declarationIdentity => $composableBuilder(
    column: $table.declarationIdentity,
    builder: (column) => column,
  );

  GeneratedColumn<String> get schemaName => $composableBuilder(
    column: $table.schemaName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contract =>
      $composableBuilder(column: $table.contract, builder: (column) => column);

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<int> get generation => $composableBuilder(
    column: $table.generation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get snapshotHash => $composableBuilder(
    column: $table.snapshotHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$Rag2GenerationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $Rag2GenerationsTable,
          Rag2GenerationRow,
          $$Rag2GenerationsTableFilterComposer,
          $$Rag2GenerationsTableOrderingComposer,
          $$Rag2GenerationsTableAnnotationComposer,
          $$Rag2GenerationsTableCreateCompanionBuilder,
          $$Rag2GenerationsTableUpdateCompanionBuilder,
          (
            Rag2GenerationRow,
            BaseReferences<
              _$AppDatabase,
              $Rag2GenerationsTable,
              Rag2GenerationRow
            >,
          ),
          Rag2GenerationRow,
          PrefetchHooks Function()
        > {
  $$Rag2GenerationsTableTableManager(
    _$AppDatabase db,
    $Rag2GenerationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$Rag2GenerationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$Rag2GenerationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$Rag2GenerationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> projectIdentity = const Value.absent(),
                Value<String> declarationIdentity = const Value.absent(),
                Value<String> schemaName = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<String> contract = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<int> generation = const Value.absent(),
                Value<String> snapshotHash = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => Rag2GenerationsCompanion(
                projectIdentity: projectIdentity,
                declarationIdentity: declarationIdentity,
                schemaName: schemaName,
                schemaVersion: schemaVersion,
                contract: contract,
                projectId: projectId,
                generation: generation,
                snapshotHash: snapshotHash,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String projectIdentity,
                required String declarationIdentity,
                required String schemaName,
                required int schemaVersion,
                required String contract,
                required String projectId,
                required int generation,
                required String snapshotHash,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => Rag2GenerationsCompanion.insert(
                projectIdentity: projectIdentity,
                declarationIdentity: declarationIdentity,
                schemaName: schemaName,
                schemaVersion: schemaVersion,
                contract: contract,
                projectId: projectId,
                generation: generation,
                snapshotHash: snapshotHash,
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

typedef $$Rag2GenerationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $Rag2GenerationsTable,
      Rag2GenerationRow,
      $$Rag2GenerationsTableFilterComposer,
      $$Rag2GenerationsTableOrderingComposer,
      $$Rag2GenerationsTableAnnotationComposer,
      $$Rag2GenerationsTableCreateCompanionBuilder,
      $$Rag2GenerationsTableUpdateCompanionBuilder,
      (
        Rag2GenerationRow,
        BaseReferences<_$AppDatabase, $Rag2GenerationsTable, Rag2GenerationRow>,
      ),
      Rag2GenerationRow,
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
  $$ModelUsageDailyTableTableManager get modelUsageDaily =>
      $$ModelUsageDailyTableTableManager(_db, _db.modelUsageDaily);
  $$Rag2StoreMetaTableTableManager get rag2StoreMeta =>
      $$Rag2StoreMetaTableTableManager(_db, _db.rag2StoreMeta);
  $$Rag2GenerationsTableTableManager get rag2Generations =>
      $$Rag2GenerationsTableTableManager(_db, _db.rag2Generations);
}
