import 'dart:async';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

// --- FirebaseFirestore اور CollectionReference کا کوڈ وہی پرانا ہے (تبدیل کرنے کی ضرورت نہیں) ---
// صرف Query کلاس اور نیچے DocumentSnapshot کے استعمال کو نوٹ کریں۔

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

  CollectionReference collection(String collectionPath) {
    return CollectionReference(collectionPath, _box);
  }

  DocumentReference doc(String documentPath) {
    return DocumentReference(documentPath, _box);
  }
}

/// **Query Class (Updated with Document Cursors)**
class Query {
  final String path;
  final Box _box;
  final List<bool Function(Map<String, dynamic>)> _filters;
  final String? _orderByField;
  final bool _descending;
  final int? _limit;

  // Cursors
  final List<Object?>? _startAt;
  final List<Object?>? _startAfter;
  final List<Object?>? _endAt;
  final List<Object?>? _endBefore;

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
  }) : _filters = filters ?? [],
       _orderByField = orderByField,
       _descending = descending,
       _limit = limit,
       _startAt = startAt,
       _startAfter = startAfter,
       _endAt = endAt,
       _endBefore = endBefore;

  Query where(
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
    // (Where کی لاجک وہی پرانی ہے جو آپ کے پاس ہے، جگہ بچانے کے لیے یہاں دوبارہ نہیں لکھ رہا)
    // ... Copy exact logic from previous response ...
    final newFilters = List<bool Function(Map<String, dynamic>)>.from(_filters);
    newFilters.add((data) {
      final value = data[field];
      if (isEqualTo != null && value != isEqualTo) return false;
      if (isNotEqualTo != null && value == isNotEqualTo) return false;
      // ... باقی تمام آپریٹرز ...
      return true;
    });
    return _copyWith(filters: newFilters);
  }

  Query orderBy(String field, {bool descending = false}) {
    return _copyWith(orderByField: field, descending: descending);
  }

  Query limit(int limit) {
    return _copyWith(limit: limit);
  }

  // --- Standard Cursors ---
  Query startAt(List<Object?> values) => _copyWith(startAt: values);
  Query startAfter(List<Object?> values) => _copyWith(startAfter: values);
  Query endAt(List<Object?> values) => _copyWith(endAt: values);
  Query endBefore(List<Object?> values) => _copyWith(endBefore: values);

  // --- NEW: Document Cursors (بالکل اصلی فائر بیس کی طرح) ---

  /// Helper to extract cursor values from a DocumentSnapshot
  List<Object?> _valuesFromSnapshot(DocumentSnapshot documentSnapshot) {
    if (_orderByField != null) {
      // اگر آپ نے orderBy("price") کیا ہے تو یہ اس ڈاکومنٹ سے price نکالے گا
      return [documentSnapshot.get(_orderByField)];
    } else {
      // اگر کوئی آرڈر نہیں ہے تو یہ Document ID استعمال کرے گا
      return [documentSnapshot.id];
    }
  }

  /// Starts the query at the provided [DocumentSnapshot].
  Query startAtDocument(DocumentSnapshot documentSnapshot) {
    return startAt(_valuesFromSnapshot(documentSnapshot));
  }

  /// Starts the query after the provided [DocumentSnapshot].
  Query startAfterDocument(DocumentSnapshot documentSnapshot) {
    return startAfter(_valuesFromSnapshot(documentSnapshot));
  }

  /// Ends the query at the provided [DocumentSnapshot].
  Query endAtDocument(DocumentSnapshot documentSnapshot) {
    return endAt(_valuesFromSnapshot(documentSnapshot));
  }

  /// Ends the query before the provided [DocumentSnapshot].
  Query endBeforeDocument(DocumentSnapshot documentSnapshot) {
    return endBefore(_valuesFromSnapshot(documentSnapshot));
  }

  // --- Execution Logic ---
  Future<QuerySnapshot> get() async {
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

    // Apply Cursors (Slicing Logic)
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

    final docs = results.map((data) {
      final id = data['__id__'] as String;
      data.remove('__id__');
      return DocumentSnapshot(id, "$path/$id", data);
    }).toList();

    return QuerySnapshot(docs);
  }

  /// Reads the documents referenced by this query.
  ///
  /// Notifies of documents at the current time and when any changes occur to the documents.
  /// // this Method Returns QuerySnapshot and this class has size
  ///  isEmpty and .docs() wich returns DocumentSnapshot
  /// ```dart
  /// usersRef1.snapshots().listen((snapshot) {
  /// snapshot.docs   => List<DocumentSnapshot>
  /// snapshot.isEmpty
  /// snapshot.size
  /// }
  /// ```

  Stream<QuerySnapshot> snapshots() {
    final controller = StreamController<QuerySnapshot>();
    get().then((snap) => controller.add(snap));

    // Watch box for changes
    final subscription = _box.watch().listen((event) async {
      // Ideally we would check if event.key matches path,
      // but for mock simplicity we re-query.
      final snap = await get();
      controller.add(snap);
    });

    controller.onCancel = () => subscription.cancel();
    return controller.stream;
  }

  // --- Cursor Logic (Slicing) ---
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
      if (index != -1) {
        startIndex = index;
      } else {
        startIndex = sortedResults.length;
      }
    } else if (_startAfter != null && _startAfter.isNotEmpty) {
      final index = sortedResults.indexWhere((doc) {
        final c = compare(doc, _startAfter.first);
        return _descending ? c < 0 : c > 0;
      });
      if (index != -1) {
        startIndex = index;
      } else {
        startIndex = sortedResults.length;
      }
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

  Query _copyWith({
    List<bool Function(Map<String, dynamic>)>? filters,
    String? orderByField,
    bool? descending,
    int? limit,
    List<Object?>? startAt,
    List<Object?>? startAfter,
    List<Object?>? endAt,
    List<Object?>? endBefore,
  }) {
    return Query(
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
    );
  }
}

// CollectionReference, DocumentReference, etc... (No changes needed)
class CollectionReference extends Query {
  CollectionReference(super.path, super.box);
  String get id => path.split('/').last;
  DocumentReference? get parent {
    final segments = path.split('/');
    if (segments.length <= 1) return null;
    final parentPath = segments.sublist(0, segments.length - 1).join('/');
    return DocumentReference(parentPath, super._box);
  }

  Future<DocumentReference> add(Map<String, dynamic> data) async {
    final newId = const Uuid().v4();
    final docRef = doc(newId);
    await docRef.set(data);
    return docRef;
  }

  DocumentReference doc([String? pathId]) {
    final docId = pathId ?? const Uuid().v4();
    return DocumentReference("$path/$docId", super._box);
  }
}

class DocumentReference {
  final String path;
  final Box _box;
  DocumentReference(this.path, this._box);
  String get id => path.split('/').last;
  CollectionReference? get parent {
    final segments = path.split('/');
    if (segments.length <= 1) return null;
    final parentPath = segments.sublist(0, segments.length - 1).join('/');
    return CollectionReference(parentPath, _box);
  }

  CollectionReference collection(String collectionPath) =>
      CollectionReference("$path/$collectionPath", _box);
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    if (options?.merge == true) {
      await update(data);
    } else {
      await _box.put(path, data);
    }
  }

  Future<void> update(Map<String, dynamic> data) async {
    final currentData = Map<String, dynamic>.from(_box.get(path) ?? {});
    currentData.addAll(data);
    await _box.put(path, currentData);
  }

  Future<void> delete() async => await _box.delete(path);
  Future<DocumentSnapshot> get() async {
    final data = _box.get(path);
    return DocumentSnapshot(
      id,
      path,
      data != null ? Map<String, dynamic>.from(data) : null,
    );
  }

  Stream<DocumentSnapshot> snapshots() {
    final controller = StreamController<DocumentSnapshot>();
    get().then((snap) => controller.add(snap));
    final subscription = _box.watch(key: path).listen((event) async {
      final snap = await get();
      controller.add(snap);
    });
    controller.onCancel = () => subscription.cancel();
    return controller.stream;
  }
}

class DocumentSnapshot {
  final String id;
  final String _internalPath;
  final Map<String, dynamic>? _data;
  DocumentSnapshot(this.id, this._internalPath, this._data);
  bool get exists => _data != null;
  Map<String, dynamic>? data() => _data;
  DocumentReference get reference =>
      FirebaseFirestore.instance.doc(_internalPath);
  dynamic get(String field) => _data?[field];
}

class QuerySnapshot {
  final List<DocumentSnapshot> docs;
  QuerySnapshot(this.docs);
  int get size => docs.length;
  bool get isEmpty => docs.isEmpty;
}

class AggregateQuerySnapshot {
  final int count;
  AggregateQuerySnapshot(this.count);
}

class SetOptions {
  final bool? merge;
  SetOptions({this.merge});
}
