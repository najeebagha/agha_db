import 'dart:async';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

// --- Options Classes ---
class SnapshotOptions {
  const SnapshotOptions();
}

class SetOptions {
  final bool? merge;
  SetOptions({this.merge});
}

// --- FirebaseFirestore Core ---
class FirebaseFirestore {
  static final FirebaseFirestore instance = FirebaseFirestore._();
  final String _boxName = 'firestore_db_core';

  FirebaseFirestore._();

  Future<void> init({String? storagePath}) async {
    if (!Hive.isBoxOpen(_boxName)) {
      if (storagePath != null) {
        await Hive.openBox(_boxName, path: storagePath);
      } else {
        await Hive.openBox(_boxName);
      }
    }
  }

  Box get _box => Hive.box(_boxName);

  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return CollectionReference<Map<String, dynamic>>(collectionPath, _box);
  }

  DocumentReference<Map<String, dynamic>> doc(String documentPath) {
    return DocumentReference<Map<String, dynamic>>(documentPath, _box);
  }
}

/// **Query Class (Fully Loaded: Cursors + Generics + Converters)**
class Query<T extends Object?> {
  final String path;
  final Box _box;
  final List<bool Function(Map<String, dynamic>)> _filters;
  final String? _orderByField;
  final bool _descending;
  final int? _limit;

  // Cursors (User's original requirement)
  final List<Object?>? _startAt;
  final List<Object?>? _startAfter;
  final List<Object?>? _endAt;
  final List<Object?>? _endBefore;

  // Converters
  final T Function(Map<String, dynamic> data, SnapshotOptions? options)?
  _fromFirestore;
  final Map<String, dynamic> Function(T value, SetOptions? options)?
  _toFirestore;

  Query(
    this.path,
    this._box, {
    List<bool Function(Map<String, dynamic>)>? filters,
    String? orderByField,
    bool descending = false,
    int? limit,
    List<Object?>? startAt,
    List<Object?>? startAfter,
    List<Object?>? endAt,
    List<Object?>? endBefore,
    T Function(Map<String, dynamic> data, SnapshotOptions? options)?
    fromFirestore,
    Map<String, dynamic> Function(T value, SetOptions? options)? toFirestore,
  }) : _filters = filters ?? [],
       _orderByField = orderByField,
       _descending = descending,
       _limit = limit,
       _startAt = startAt,
       _startAfter = startAfter,
       _endAt = endAt,
       _endBefore = endBefore,
       _fromFirestore = fromFirestore,
       _toFirestore = toFirestore;

  /// **.withConverter()**
  Query<R> withConverter<R>({
    required R Function(Map<String, dynamic> snapshot, SnapshotOptions? options)
    fromFirestore,
    required Map<String, dynamic> Function(R value, SetOptions? options)
    toFirestore,
  }) {
    return Query<R>(
      path,
      _box,
      filters: _filters,
      orderByField: _orderByField,
      descending: _descending,
      limit: _limit,
      startAt: _startAt,
      startAfter: _startAfter,
      endAt: _endAt,
      endBefore: _endBefore,
      fromFirestore: fromFirestore,
      toFirestore: toFirestore,
    );
  }

  // --- Filtering ---
  Query<T> where(
    String field, {
    Object? isEqualTo,
    Object? isNotEqualTo,
    Object? isLessThan,
    Object? isLessThanOrEqualTo,
    Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo,
    Object? arrayContains,
    List<Object?>? arrayContainsAny,
    List<Object?>? whereIn,
    List<Object?>? whereNotIn,
    bool? isNull,
  }) {
    final newFilters = List<bool Function(Map<String, dynamic>)>.from(_filters);
    newFilters.add((data) {
      final value = data[field];
      if (isEqualTo != null && value != isEqualTo) return false;
      if (isNotEqualTo != null && value == isNotEqualTo) return false;
      if (isLessThan != null && (value == null || value >= isLessThan))
        return false;
      if (isLessThanOrEqualTo != null &&
          (value == null || value > isLessThanOrEqualTo))
        return false;
      if (isGreaterThan != null && (value == null || value <= isGreaterThan))
        return false;
      if (isGreaterThanOrEqualTo != null &&
          (value == null || value < isGreaterThanOrEqualTo))
        return false;
      if (isNull != null && (value == null) != isNull) return false;

      if (arrayContains != null) {
        if (value is! List || !value.contains(arrayContains)) return false;
      }
      if (arrayContainsAny != null) {
        if (value is! List ||
            !value.any((item) => arrayContainsAny.contains(item)))
          return false;
      }
      if (whereIn != null) {
        if (!whereIn.contains(value)) return false;
      }
      if (whereNotIn != null) {
        if (whereNotIn.contains(value)) return false;
      }
      return true;
    });
    return _copyWith(filters: newFilters);
  }

  Query<T> orderBy(String field, {bool descending = false}) {
    return _copyWith(orderByField: field, descending: descending);
  }

  Query<T> limit(int limit) {
    return _copyWith(limit: limit);
  }

  // --- Standard Cursors ---
  Query<T> startAt(List<Object?> values) => _copyWith(startAt: values);
  Query<T> startAfter(List<Object?> values) => _copyWith(startAfter: values);
  Query<T> endAt(List<Object?> values) => _copyWith(endAt: values);
  Query<T> endBefore(List<Object?> values) => _copyWith(endBefore: values);

  // --- Document Cursors ---
  List<Object?> _valuesFromSnapshot(DocumentSnapshot documentSnapshot) {
    if (_orderByField != null) {
      return [documentSnapshot.get(_orderByField)];
    } else {
      return [documentSnapshot.id];
    }
  }

  Query<T> startAtDocument(DocumentSnapshot documentSnapshot) {
    return startAt(_valuesFromSnapshot(documentSnapshot));
  }

  Query<T> startAfterDocument(DocumentSnapshot documentSnapshot) {
    return startAfter(_valuesFromSnapshot(documentSnapshot));
  }

  Query<T> endAtDocument(DocumentSnapshot documentSnapshot) {
    return endAt(_valuesFromSnapshot(documentSnapshot));
  }

  Query<T> endBeforeDocument(DocumentSnapshot documentSnapshot) {
    return endBefore(_valuesFromSnapshot(documentSnapshot));
  }

  // --- Execution Logic ---
  Future<QuerySnapshot<T>> get() async {
    final allKeys = _box.keys.cast<String>().where((key) {
      final segments = key.split('/');
      if (segments.length < 2) return false;
      final parentPath = segments.sublist(0, segments.length - 1).join('/');
      return parentPath == path;
    });

    List<Map<String, dynamic>> results = [];

    for (var key in allKeys) {
      final rawData = _box.get(key);
      if (rawData == null) continue;

      final data = Map<String, dynamic>.from(rawData);
      data['__id__'] = key.split('/').last;

      bool matches = true;
      for (var filter in _filters) {
        if (!filter(data)) {
          matches = false;
          break;
        }
      }
      if (matches) results.add(data);
    }

    // Apply Sort
    if (_orderByField != null) {
      results.sort((a, b) {
        final valA = a[_orderByField];
        final valB = b[_orderByField];
        if (valA == null && valB == null) return 0;
        if (valA == null) return _descending ? 1 : -1;
        if (valB == null) return _descending ? -1 : 1;

        int comparison = valA.toString().compareTo(valB.toString());
        if (valA is Comparable && valB is Comparable) {
          try {
            comparison = valA.compareTo(valB);
          } catch (_) {}
        }
        return _descending ? -comparison : comparison;
      });
    } else {
      results.sort((a, b) => a['__id__'].compareTo(b['__id__']));
    }

    // Apply Cursors
    if (_startAt != null ||
        _startAfter != null ||
        _endAt != null ||
        _endBefore != null) {
      results = _applyCursors(results);
    }

    // Apply Limit
    if (_limit != null && results.length > _limit) {
      results = results.sublist(0, _limit);
    }

    // **Mapping to QueryDocumentSnapshot**
    // اصلی فائر بیس میں Query کا رزلٹ ہمیشہ QueryDocumentSnapshot ہوتا ہے
    // جس کا ڈیٹا null نہیں ہو سکتا۔
    final docs = results.map((data) {
      final id = data['__id__'] as String;
      data.remove('__id__');

      T convertedData;
      if (_fromFirestore != null) {
        convertedData = _fromFirestore(data, const SnapshotOptions());
      } else {
        convertedData = data as T;
      }

      return QueryDocumentSnapshot<T>(id, "$path/$id", convertedData);
    }).toList();

    return QuerySnapshot<T>(docs);
  }

  Stream<QuerySnapshot<T>> snapshots() {
    final controller = StreamController<QuerySnapshot<T>>();
    get().then((snap) => controller.add(snap));
    final subscription = _box.watch().listen((_) async {
      final snap = await get();
      controller.add(snap);
    });
    controller.onCancel = () => subscription.cancel();
    return controller.stream;
  }

  // --- Cursor Helper (The Logic you wanted to keep) ---
  List<Map<String, dynamic>> _applyCursors(
    List<Map<String, dynamic>> sortedResults,
  ) {
    if (sortedResults.isEmpty) return sortedResults;

    final field = _orderByField ?? '__id__';
    int startIndex = 0;
    int endIndex = sortedResults.length;

    int compare(Map<String, dynamic> doc, Object? cursorVal) {
      final val = doc[field];
      if (val == null && cursorVal == null) return 0;
      if (val == null) return _descending ? 1 : -1;
      if (cursorVal == null) return _descending ? -1 : 1;
      if (val is Comparable) return val.compareTo(cursorVal as dynamic);
      return val.toString().compareTo(cursorVal.toString());
    }

    if (_startAt != null && _startAt.isNotEmpty) {
      final index = sortedResults.indexWhere((doc) {
        final c = compare(doc, _startAt.first);
        return _descending ? c <= 0 : c >= 0;
      });
      startIndex = (index != -1) ? index : sortedResults.length;
    } else if (_startAfter != null && _startAfter.isNotEmpty) {
      final index = sortedResults.indexWhere((doc) {
        final c = compare(doc, _startAfter.first);
        return _descending ? c < 0 : c > 0;
      });
      startIndex = (index != -1) ? index : sortedResults.length;
    }

    if (_endAt != null && _endAt.isNotEmpty) {
      final index = sortedResults.indexWhere((doc) {
        final c = compare(doc, _endAt.first);
        return _descending ? c < 0 : c > 0;
      });
      if (index != -1) endIndex = index;
    } else if (_endBefore != null && _endBefore.isNotEmpty) {
      final index = sortedResults.indexWhere((doc) {
        final c = compare(doc, _endBefore.first);
        return _descending ? c <= 0 : c >= 0;
      });
      if (index != -1) endIndex = index;
    }

    if (startIndex >= sortedResults.length) return [];
    if (endIndex < startIndex) return [];
    if (endIndex > sortedResults.length) endIndex = sortedResults.length;

    return sortedResults.sublist(startIndex, endIndex);
  }

  Query<T> _copyWith({
    List<bool Function(Map<String, dynamic>)>? filters,
    String? orderByField,
    bool? descending,
    int? limit,
    List<Object?>? startAt,
    List<Object?>? startAfter,
    List<Object?>? endAt,
    List<Object?>? endBefore,
    T Function(Map<String, dynamic> data, SnapshotOptions? options)?
    fromFirestore,
    Map<String, dynamic> Function(T value, SetOptions? options)? toFirestore,
  }) {
    return Query<T>(
      path,
      _box,
      filters: filters ?? _filters,
      orderByField: orderByField ?? _orderByField,
      descending: descending ?? _descending,
      limit: limit ?? _limit,
      startAt: startAt ?? _startAt,
      startAfter: startAfter ?? _startAfter,
      endAt: endAt ?? _endAt,
      endBefore: endBefore ?? _endBefore,
      fromFirestore: fromFirestore ?? _fromFirestore,
      toFirestore: toFirestore ?? _toFirestore,
    );
  }
}

/// **CollectionReference**
class CollectionReference<T extends Object?> extends Query<T> {
  CollectionReference(
    super.path,
    super.box, {
    super.fromFirestore,
    super.toFirestore,
  });

  @override
  CollectionReference<R> withConverter<R>({
    required R Function(Map<String, dynamic> snapshot, SnapshotOptions? options)
    fromFirestore,
    required Map<String, dynamic> Function(R value, SetOptions? options)
    toFirestore,
  }) {
    return CollectionReference<R>(
      path,
      _box,
      fromFirestore: fromFirestore,
      toFirestore: toFirestore,
    );
  }

  DocumentReference<T> doc([String? pathId]) {
    final docId = pathId ?? const Uuid().v4();
    return DocumentReference<T>(
      "$path/$docId",
      _box,
      fromFirestore: _fromFirestore,
      toFirestore: _toFirestore,
    );
  }

  Future<DocumentReference<T>> add(T data) async {
    final docRef = doc();
    await docRef.set(data);
    return docRef;
  }
}

/// **DocumentReference**
class DocumentReference<T extends Object?> {
  final String path;
  final Box _box;
  final T Function(Map<String, dynamic> data, SnapshotOptions? options)?
  _fromFirestore;
  final Map<String, dynamic> Function(T value, SetOptions? options)?
  _toFirestore;

  DocumentReference(
    this.path,
    this._box, {
    T Function(Map<String, dynamic> data, SnapshotOptions? options)?
    fromFirestore,
    Map<String, dynamic> Function(T value, SetOptions? options)? toFirestore,
  }) : _fromFirestore = fromFirestore,
       _toFirestore = toFirestore;

  String get id => path.split('/').last;

  DocumentReference<R> withConverter<R>({
    required R Function(Map<String, dynamic> snapshot, SnapshotOptions? options)
    fromFirestore,
    required Map<String, dynamic> Function(R value, SetOptions? options)
    toFirestore,
  }) {
    return DocumentReference<R>(
      path,
      _box,
      fromFirestore: fromFirestore,
      toFirestore: toFirestore,
    );
  }

  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    return CollectionReference<Map<String, dynamic>>(
      "$path/$collectionPath",
      _box,
    );
  }

  Future<void> set(T data, [SetOptions? options]) async {
    Map<String, dynamic> rawData;
    if (_toFirestore != null) {
      rawData = _toFirestore(data, options);
    } else {
      rawData = data as Map<String, dynamic>;
    }

    if (options?.merge == true) {
      final existing = _box.get(path);
      final Map<String, dynamic> currentData = existing != null
          ? Map<String, dynamic>.from(existing)
          : {};
      currentData.addAll(rawData);
      await _box.put(path, currentData);
    } else {
      await _box.put(path, rawData);
    }
  }

  Future<void> update(Map<String, dynamic> data) async {
    final currentData = Map<String, dynamic>.from(_box.get(path) ?? {});
    currentData.addAll(data);
    await _box.put(path, currentData);
  }

  Future<void> delete() async => await _box.delete(path);

  Future<DocumentSnapshot<T>> get() async {
    final rawData = _box.get(path);
    T? convertedData;
    if (rawData != null) {
      final map = Map<String, dynamic>.from(rawData);
      convertedData = (_fromFirestore != null)
          ? _fromFirestore(map, const SnapshotOptions())
          : map as T;
    }
    return DocumentSnapshot<T>(id, path, convertedData);
  }

  Stream<DocumentSnapshot<T>> snapshots() {
    final controller = StreamController<DocumentSnapshot<T>>();
    get().then((snap) => controller.add(snap));
    final subscription = _box.watch(key: path).listen((event) async {
      final snap = await get();
      controller.add(snap);
    });
    controller.onCancel = () => subscription.cancel();
    return controller.stream;
  }
}

/// **DocumentSnapshot (Base Class)**
/// اس میں ڈیٹا نل ہو سکتا ہے (کیونکہ ہو سکتا ہے ڈاکومنٹ موجود ہی نہ ہو)
class DocumentSnapshot<T extends Object?> {
  final String id;
  final String _internalPath;
  final T? _data;

  DocumentSnapshot(this.id, this._internalPath, this._data);

  bool get exists => _data != null;

  /// Returns the data or null if not exists
  T? data() => _data;

  DocumentReference<T> get reference => FirebaseFirestore.instance
      .doc(_internalPath)
      .withConverter<T>(
        fromFirestore: (snapshot, _) =>
            snapshot as dynamic, // Simplified for mock
        toFirestore: (value, _) => value as Map<String, dynamic>,
      ); // نوٹ: یہ ایک سادہ ریفرنس ہے

  dynamic get(String field) {
    if (_data is Map) return (_data as Map)[field];
    return null;
  }
}

/// **QueryDocumentSnapshot (New Addition)**
/// یہ ہمیشہ Query کے رزلٹ میں آتا ہے، اس لیے اس کا ڈیٹا کبھی نل نہیں ہوتا
class QueryDocumentSnapshot<T extends Object?> extends DocumentSnapshot<T> {
  QueryDocumentSnapshot(super.id, super.internalPath, T super.data);

  /// Overridden to return T (non-nullable) because it surely exists
  @override
  T data() {
    return super.data()!;
  }
}

/// **QuerySnapshot (Updated)**
/// اب یہ QueryDocumentSnapshot کی لسٹ رکھتا ہے
class QuerySnapshot<T extends Object?> {
  final List<QueryDocumentSnapshot<T>> docs;

  QuerySnapshot(this.docs);

  int get size => docs.length;
  bool get isEmpty => docs.isEmpty;
}
