import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 1. GET USER STREAM (List of people to chat with)
  Stream<List<Map<String, dynamic>>> getUsersStream() {
    return _firestore.collection("Users").snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return doc.data();
      }).toList();
    });
  }

  // 2. SEND MESSAGE
  Future<void> sendMessage(String receiverID, message) async {
    final String currentUserID = _auth.currentUser!.uid;
    final String currentUserEmail = _auth.currentUser!.email!;
    final Timestamp timestamp = Timestamp.now();

    Map<String, dynamic> newMessage = {
      'senderID': currentUserID,
      'senderEmail': currentUserEmail,
      'receiverID': receiverID,
      'message': message,
      'timestamp': timestamp,
      'isRead': false,
    };

    List<String> ids = [currentUserID, receiverID];
    ids.sort();
    String chatRoomID = ids.join('_');

    await _firestore
        .collection("chat_rooms")
        .doc(chatRoomID)
        .collection("messages")
        .add(newMessage);
  }

  // 3. GET MESSAGES
  Stream<QuerySnapshot> getMessages(String userID, otherUserID) {
    List<String> ids = [userID, otherUserID];
    ids.sort();
    String chatRoomID = ids.join('_');

    return _firestore
        .collection("chat_rooms")
        .doc(chatRoomID)
        .collection("messages")
        .orderBy("timestamp", descending: false)
        .snapshots();
  }

  // 4. MARK MESSAGES AS READ
  Future<void> markMessagesAsRead(String receiverID) async {
    final String currentUserID = _auth.currentUser!.uid;

    // Calculate ChatRoomID (Same logic as above)
    List<String> ids = [currentUserID, receiverID];
    ids.sort();
    String chatRoomID = ids.join('_');

    // Query: Find messages in this chat sent by the OTHER person (senderID != me)
    // that are currently NOT read.
    final unreadMessagesQuery = _firestore
        .collection("chat_rooms")
        .doc(chatRoomID)
        .collection("messages")
        .where('senderID', isNotEqualTo: currentUserID)
        .where('isRead', isEqualTo: false);

    final snapshot = await unreadMessagesQuery.get();

    // Batch Update: Update all found documents at once
    if (snapshot.docs.isNotEmpty) {
      WriteBatch batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      await batch.commit();
    }
  }
}
