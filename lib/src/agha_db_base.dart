import 'dart:async';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

/// The entry point for accessing a Firestore.
///
/// You can get an instance by calling [FirebaseFirestore.instance].
class FirebaseFirestore {
  static final FirebaseFirestore instance = FirebaseFirestore._();

  // Internal Box Name
  final String _boxName = 'firestore_db_core';

  FirebaseFirestore._();

  /// **Initialization:**
  ///
  /// - **[storagePath]**: (Optional)
  ///   If Your Are Using `Shelf` `dart cmd apps` `dart project` Apps then
  /// Pass the Database Path like "./my_db" ۔
  ///   for Flutter App it will take the directory of `ApplicationDocumentsDirectory`
  Future<void> init({String? storagePath}) async {
    // باکس کھولیں
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

/// A [Query] refers to a query which you can read or listen to. You can also construct
/// refined [Query] objects by adding filters and ordering.
class Query {
  final String path;
  final Box _box;
  final List<bool Function(Map<String, dynamic>)> _filters;
  final String? _orderByField;
  final bool _descending;
  final int? _limit;

  // --- Cursors ---
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

  /// Creates and returns a new [Query] with additional filter constraints.
  ///
  /// **Example:**
  /// ```dart
  /// // Filter where 'age' is greater than 18
  /// collection.where('age', isGreaterThan: 18);
  /// ```
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
    final newFilters = List<bool Function(Map<String, dynamic>)>.from(_filters);

    newFilters.add((data) {
      final value = data[field];

      // 1. Equality
      if (isEqualTo != null && value != isEqualTo) return false;
      if (isNotEqualTo != null && value == isNotEqualTo) return false;

      // 2. Null Checks
      if (isNull != null) {
        if (isNull && value != null) return false;
        if (!isNull && value == null) return false;
      }

      // 3. Comparison (<, <=, >, >=)
      if (value is Comparable) {
        if (isLessThan != null && value.compareTo(isLessThan) >= 0) {
          return false;
        }
        if (isLessThanOrEqualTo != null &&
            value.compareTo(isLessThanOrEqualTo) > 0) {
          return false;
        }
        if (isGreaterThan != null && value.compareTo(isGreaterThan) <= 0) {
          return false;
        }
        if (isGreaterThanOrEqualTo != null &&
            value.compareTo(isGreaterThanOrEqualTo) < 0) {
          return false;
        }
      } else if (value == null &&
          (isLessThan != null || isGreaterThan != null)) {
        return false; // Null values generally don't match range queries
      }

      // 4. Array Membership
      if (arrayContains != null) {
        if (value is! List || !value.contains(arrayContains)) return false;
      }
      if (arrayContainsAny != null) {
        if (value is! List || !value.any((e) => arrayContainsAny.contains(e))) {
          return false;
        }
      }

      // 5. IN / NOT-IN
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

  /// Creates and returns a new [Query] that's additionally sorted by the specified field.
  Query orderBy(String field, {bool descending = false}) {
    return _copyWith(orderByField: field, descending: descending);
  }

  /// Creates and returns a new [Query] that's limited to the specified number of documents.
  Query limit(int limit) {
    return _copyWith(limit: limit);
  }

  /// Starts the query results at the provided values (inclusive).
  Query startAt(List<Object?> values) {
    return _copyWith(startAt: values);
  }

  /// Starts the query results after the provided values (exclusive).
  Query startAfter(List<Object?> values) {
    return _copyWith(startAfter: values);
  }

  /// Ends the query results at the provided values (inclusive).
  Query endAt(List<Object?> values) {
    return _copyWith(endAt: values);
  }

  /// Ends the query results before the provided values (exclusive).
  /// Note: Firestore uses 'endBefore', so we use that naming convention.
  Query endBefore(List<Object?> values) {
    return _copyWith(endBefore: values);
  }

  /// Executes the query and returns the results as a [QuerySnapshot].
  Future<QuerySnapshot> get() async {
    // Logic to simulate a query scan
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

      // Check Filters
      bool matches = true;
      for (var filter in _filters) {
        if (!filter(data)) {
          matches = false;
          break;
        }
      }

      if (matches) {
        results.add(data);
      }
    }

    // Apply Sort
    if (_orderByField != null) {
      results.sort((a, b) {
        final valA = a[_orderByField];
        final valB = b[_orderByField];

        // Handle sorting nulls safely
        if (valA == null && valB == null) return 0;
        if (valA == null) return _descending ? 1 : -1;
        if (valB == null) return _descending ? -1 : 1;

        int comparison;
        if (valA is Comparable && valB is Comparable) {
          try {
            comparison = valA.compareTo(valB);
          } catch (e) {
            comparison = valA.toString().compareTo(valB.toString());
          }
        } else {
          comparison = valA.toString().compareTo(valB.toString());
        }
        return _descending ? -comparison : comparison;
      });
    } else {
      // If no orderBy is provided, we sort by ID implicitly for cursor stability
      results.sort((a, b) => a['__id__'].compareTo(b['__id__']));
    }

    // Apply Cursors (startAt, startAfter, endAt, endBefore)
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

  // Helper to apply cursor logic on sorted results
  List<Map<String, dynamic>> _applyCursors(
    List<Map<String, dynamic>> sortedResults,
  ) {
    final field = _orderByField ?? '__id__';

    return sortedResults.where((doc) {
      final val = doc[field];

      // Comparison Helper: Returns negative if val < cursor, positive if val > cursor
      int compareWithCursor(Object? cursorVal) {
        if (val == null && cursorVal == null) return 0;
        if (val == null) return _descending ? 1 : -1; // Null logic
        if (cursorVal == null) return _descending ? -1 : 1;

        if (val is Comparable) {
          // We cast cursorVal to dynamic to allow compareTo to try matching types
          return val.compareTo(cursorVal as dynamic);
        }
        return val.toString().compareTo(cursorVal.toString());
      }

      // 1. startAt (Inclusive)
      if (_startAt != null && _startAt.isNotEmpty) {
        final c = compareWithCursor(_startAt.first);
        // If descending: we want val <= cursor. So if val > cursor (c > 0), exclude it.
        // If ascending: we want val >= cursor. So if val < cursor (c < 0), exclude it.
        if (_descending) {
          if (c > 0) return false;
        } else {
          if (c < 0) return false;
        }
      }

      // 2. startAfter (Exclusive)
      if (_startAfter != null && _startAfter.isNotEmpty) {
        final c = compareWithCursor(_startAfter.first);
        // If descending: we want val < cursor. So if val >= cursor (c >= 0), exclude.
        // If ascending: we want val > cursor. So if val <= cursor (c <= 0), exclude.
        if (_descending) {
          if (c >= 0) return false;
        } else {
          if (c <= 0) return false;
        }
      }

      // 3. endAt (Inclusive)
      if (_endAt != null && _endAt.isNotEmpty) {
        final c = compareWithCursor(_endAt.first);
        // If descending: we want val >= cursor. So if val < cursor (c < 0), stop/exclude.
        // If ascending: we want val <= cursor. So if val > cursor (c > 0), stop/exclude.
        if (_descending) {
          if (c < 0) return false;
        } else {
          if (c > 0) return false;
        }
      }

      // 4. endBefore (Exclusive)
      if (_endBefore != null && _endBefore.isNotEmpty) {
        final c = compareWithCursor(_endBefore.first);
        // If descending: we want val > cursor. So if val <= cursor (c <= 0), exclude.
        // If ascending: we want val < cursor. So if val >= cursor (c >= 0), exclude.
        if (_descending) {
          if (c <= 0) return false;
        } else {
          if (c >= 0) return false;
        }
      }

      return true;
    }).toList();
  }

  /// Reads the documents referenced by this query.
  ///
  /// Notifies of documents at the current time and when any changes occur to the documents.
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

  /// Returns the count of documents in the result set of this query.
  Future<AggregateQuerySnapshot> count() async {
    final snapshot = await get();
    return AggregateQuerySnapshot(snapshot.docs.length);
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

/// A [CollectionReference] object can be used for adding documents,
/// getting document references, and querying for documents (using the methods
/// inherited from [Query]).
class CollectionReference extends Query {
  CollectionReference(super.path, super.box);

  /// The ID of the collection.
  String get id => path.split('/').last;

  /// Returns a [DocumentReference] to the parent document of this collection,
  /// or null if this collection is a root collection.
  DocumentReference? get parent {
    final segments = path.split('/');
    if (segments.length <= 1) return null;
    final parentPath = segments.sublist(0, segments.length - 1).join('/');
    return DocumentReference(parentPath, super._box);
  }

  /// Adds a new document to this collection with the specified data,
  /// assigning it a document ID automatically.
  Future<DocumentReference> add(Map<String, dynamic> data) async {
    final newId = const Uuid().v4();
    final docRef = doc(newId);
    await docRef.set(data);
    return docRef;
  }

  /// Returns a [DocumentReference] with the provided path.
  /// If no [path] is provided, an auto-generated ID is used.
  DocumentReference doc([String? pathId]) {
    final docId = pathId ?? const Uuid().v4();
    return DocumentReference("$path/$docId", super._box);
  }
}

/// A [DocumentReference] refers to a document location in a Firestore database
/// and can be used to write, read, or listen to the location.
class DocumentReference {
  final String path;
  final Box _box;

  DocumentReference(this.path, this._box);

  /// The ID of the document within the collection.
  String get id => path.split('/').last;

  /// The Collection this DocumentReference belongs to.
  CollectionReference? get parent {
    final segments = path.split('/');
    if (segments.length <= 1) return null;
    final parentPath = segments.sublist(0, segments.length - 1).join('/');
    return CollectionReference(parentPath, _box);
  }

  /// Gets a [CollectionReference] to a sub-collection of this document.
  CollectionReference collection(String collectionPath) {
    return CollectionReference("$path/$collectionPath", _box);
  }

  /// Sets data on the document, overwriting any existing data.
  /// If the document does not yet exist, it will be created.
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    if (options?.merge == true) {
      await update(data);
    } else {
      await _box.put(path, data);
    }
  }

  /// Updates data on the document. Data will be merged with any existing document data.
  /// If no document exists, this will do nothing (in Mock, it creates/updates implicitly).
  Future<void> update(Map<String, dynamic> data) async {
    final currentData = Map<String, dynamic>.from(_box.get(path) ?? {});
    currentData.addAll(data);
    await _box.put(path, currentData);
  }

  /// Deletes the document from the database.
  Future<void> delete() async {
    await _box.delete(path);
  }

  /// Reads the document referenced by this [DocumentReference].
  Future<DocumentSnapshot> get() async {
    final data = _box.get(path);
    return DocumentSnapshot(
      id,
      path,
      data != null ? Map<String, dynamic>.from(data) : null,
    );
  }

  /// Notifies of document updates at this location.
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

// --- Snapshot & Helper Classes ---

/// A [DocumentSnapshot] contains data read from a document in your Firestore database.
class DocumentSnapshot {
  final String id;
  final String _internalPath;
  final Map<String, dynamic>? _data;

  DocumentSnapshot(this.id, this._internalPath, this._data);

  /// Returns true if the document exists.
  bool get exists => _data != null;

  /// Contains all the data of this document snapshot.
  Map<String, dynamic>? data() => _data;

  /// The [DocumentReference] for the document.
  DocumentReference get reference =>
      FirebaseFirestore.instance.doc(_internalPath);

  /// Gets the value of a specific field from the document.
  dynamic get(String field) => _data?[field];
}

/// A [QuerySnapshot] contains zero or more [DocumentSnapshot] objects.
class QuerySnapshot {
  /// // All Data In 'docs' is in List of DocumentSnapshot
  /// and using for in loop or .map() every DocumentSnapshot has
  /// ```dart
  /// for (var doc in querySnapshot.docs) {
  /// doc.data();  //Map<String, dynamic>
  /// doc.id;
  /// }
  /// ```
  final List<DocumentSnapshot> docs;

  QuerySnapshot(this.docs);

  /// The number of documents in the [QuerySnapshot].
  int get size => docs.length;

  /// True if there are no documents in the [QuerySnapshot].
  bool get isEmpty => docs.isEmpty;
}

/// The result of an aggregate query, such as a count query.
class AggregateQuerySnapshot {
  final int count;
  AggregateQuerySnapshot(this.count);
}

/// Options for [DocumentReference.set].
class SetOptions {
  /// Set to true to merge the new data with any existing document data.
  final bool? merge;
  SetOptions({this.merge});
}
