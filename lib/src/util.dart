import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;

/// Extension with one [toShortString] method.
extension RoleToShortString on types.Role {
  /// Converts enum to the string equal to enum's name.
  String toShortString() => toString().split('.').last;
}

/// Extension with one [toShortString] method.
extension RoomTypeToShortString on types.RoomType {
  /// Converts enum to the string equal to enum's name.
  String toShortString() => toString().split('.').last;
}

/// Fetches user from Firebase and returns a promise.
Future<Map<String, dynamic>> fetchUser(
  FirebaseFirestore instance,
  String userId,
  String usersCollectionName, {
  String? role,
}) async {
  DocumentSnapshot<Map<String, dynamic>>? doc;
  try {
    doc = await instance
        .collection(usersCollectionName)
        .doc(userId)
        .get(const GetOptions(source: Source.cache));
  } on FirebaseException catch (ex) {
    if (ex.code == 'unavailable') {
      doc = await instance
          .collection(usersCollectionName)
          .doc(userId)
          .get(const GetOptions(source: Source.server));
    } else {
      rethrow;
    }
  }
  if (doc.data() == null) {
    return {
      'id': 'DELETE_ACC$userId',
      'firstName': 'Deleted Account',
    };
  }
  if (doc.data() == null) {
    return {
      'id': 'DELETE_ACC_$userId',
      'firstName': 'Deleted Account',
    };
  }
  final data = doc.data()!;

  data['createdAt'] = data['createdAt']?.millisecondsSinceEpoch;
  data['id'] = doc.id;
  if (data['avatar'] != null) {
    data['imageUrl'] = data['avatar']?['imagePath'];
  }
  data['firstName'] = data['name'];
  data['lastSeen'] = data['lastSeen']?.millisecondsSinceEpoch;
  data['role'] = role;
  data['updatedAt'] = data['updatedAt']?.millisecondsSinceEpoch;
  data['metadata'] = {
    'presence': data['presence'],
  };

  return data;
}

/// Returns a list of [types.Room] created from Firebase query.
/// If room has 2 participants, sets correct room name and image.
Future<List<types.Room>> processRoomsQuery(
  User firebaseUser,
  FirebaseFirestore instance,
  QuerySnapshot<Map<String, dynamic>> query,
  String usersCollectionName,
  String roomCollectionName,
) async {
  final futures = query.docs.map(
    (doc) => processRoomDocument(
      doc,
      firebaseUser,
      instance,
      usersCollectionName,
      roomCollectionName,
    ),
  );

  return await Future.wait(futures);
}

/// Returns a [types.Room] created from Firebase document.
Future<types.Room> processRoomDocument(
  DocumentSnapshot<Map<String, dynamic>> doc,
  User firebaseUser,
  FirebaseFirestore instance,
  String usersCollectionName,
  String roomCollectionName,
) async {
  final data = doc.data()!;

  data['createdAt'] = data['createdAt']?.millisecondsSinceEpoch;
  data['id'] = doc.id;
  data['updatedAt'] = data['updatedAt']?.millisecondsSinceEpoch;

  var imageUrl = data['imageUrl'] as String?;
  var name = data['name'] as String?;
  final type = data['type'] as String;
  final userIds = data['userIds'] as List<dynamic>;
  final userRoles = data['userRoles'] as Map<String, dynamic>?;

  final users = await Future.wait(
    userIds.map(
      (userId) => fetchUser(
        instance,
        userId as String,
        usersCollectionName,
        role: userRoles?[userId] as String?,
      ),
    ),
  );

  if (type == types.RoomType.direct.toShortString()) {
    try {
      final otherUser = users.firstWhere(
        (u) => u['id'] != firebaseUser.uid,
      );

      imageUrl = otherUser['imageUrl'] as String?;
      name = '${otherUser['firstName'] ?? ''} ${otherUser['lastName'] ?? ''}'
          .trim();
    } catch (e) {
      // Do nothing if other user is not found, because he should be found.
      // Consider falling back to some default values.
    }
  }

  data['imageUrl'] = imageUrl;
  data['name'] = name;
  data['users'] = users;

  if (data['lastMessages'] != null) {
    final lastMessages = data['lastMessages'].map((lm) {
      final author = users.firstWhere(
        (u) => u['id'] == lm['authorId'],
        orElse: () => {'id': lm['authorId'] as String},
      );

      lm['author'] = author;
      lm['createdAt'] = lm['createdAt']?.millisecondsSinceEpoch;
      lm['id'] = lm['id'] ?? '';
      lm['updatedAt'] = lm['updatedAt']?.millisecondsSinceEpoch;

      return lm;
    }).toList();

    data['lastMessages'] = lastMessages;
  }
  if (data['metadata'] == null) {
    data['metadata'] = Map<String, dynamic>.from({});
  }
  data['metadata']['unreadCount'] = await unreadMessageCount(
    instance,
    roomCollectionName,
    doc.id,
    firebaseUser.uid,
  );

  return types.Room.fromJson(data);
}

Future<int> unreadMessageCount(
  FirebaseFirestore instance,
  String roomCollectionName,
  String roomId,
  String userId,
) async {
  final query = await instance
      .collection(roomCollectionName)
      .doc(roomId)
      .collection('messages')
      .where('authorId', isNotEqualTo: userId)
      .where('status', isEqualTo: 'delivered')
      .count()
      .get();
  return query.count;
}
