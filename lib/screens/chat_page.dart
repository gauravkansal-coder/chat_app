import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChatPage extends StatefulWidget {
  // Make these OPTIONAL (nullable).
  // If they are null -> We use Group Chat mode.
  // If they have data -> We use Private Chat mode.
  final String? receiverEmail;
  final String? receiverID;

  const ChatPage({super.key, this.receiverEmail, this.receiverID});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ScrollController _scrollController = ScrollController();
  FocusNode myFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    myFocusNode.addListener(() {
      if (myFocusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 500), () => scrollDown());
      }
    });
  }

  @override
  void dispose() {
    myFocusNode.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void scrollDown() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(seconds: 1),
        curve: Curves.fastOutSlowIn,
      );
    }
  }

  // --- HELPER: GET THE CORRECT COLLECTION ---
  // This is the magic part. It decides where to save/read messages.
  CollectionReference getMessageCollection() {
    // 1. GROUP CHAT MODE (No receiver)
    if (widget.receiverID == null) {
      return _firestore.collection('messages');
    }

    // 2. PRIVATE CHAT MODE (With receiver)
    // Create a unique Chat Room ID that is always the same for these two users
    String currentUserID = _auth.currentUser!.uid;
    List<String> ids = [currentUserID, widget.receiverID!];
    ids.sort(); // Sort alphabetically (e.g., "A_B" is same as "B_A")
    String chatRoomID = ids.join('_');

    return _firestore
        .collection('chat_rooms')
        .doc(chatRoomID)
        .collection('messages');
  }

  // --- SEND MESSAGE ---
  void sendMessage() async {
    if (_messageController.text.isNotEmpty) {
      String message = _messageController.text;
      _messageController.clear();

      // --- BUG FIX ---
      // use getMessageCollection() to ensure it goes to the right room
      await getMessageCollection().add({
        'text': message,
        'sender': _auth.currentUser!.email,
        'senderID': _auth.currentUser!.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'readBy': [],
      });

      scrollDown();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine the title based on mode
    String pageTitle = widget.receiverEmail ?? "Team Chat";

    return Scaffold(
      appBar: AppBar(
        title: Text(pageTitle),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.grey,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildUserInput(),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return StreamBuilder<QuerySnapshot>(
      // Listen to the correct collection dynamically
      stream: getMessageCollection()
          .orderBy('timestamp', descending: false)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('Error');
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        return ListView(
          controller: _scrollController,
          children: snapshot.data!.docs.map((document) {
            return _buildMessageItem(document);
          }).toList(),
        );
      },
    );
  }

  Widget _buildMessageItem(DocumentSnapshot document) {
    Map<String, dynamic> data = document.data() as Map<String, dynamic>;

    String messageText = data['text'] ?? '';
    String senderEmail = data['sender'] ?? 'Unknown';
    List<dynamic> readBy = data['readBy'] ?? [];
    bool isRead = readBy.isNotEmpty; // Simplified read check

    // Timestamp
    Timestamp? t = data['timestamp'];
    DateTime d = t != null ? t.toDate() : DateTime.now();
    String formattedTime = "${d.hour}:${d.minute.toString().padLeft(2, '0')}";

    bool isCurrentUser = senderEmail == _auth.currentUser?.email;

    return Container(
      alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Column(
        crossAxisAlignment: isCurrentUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (!isCurrentUser) // Only show name for others
            Text(
              senderEmail,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),

          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isCurrentUser ? Colors.green : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  messageText,
                  style: TextStyle(
                    color: isCurrentUser ? Colors.white : Colors.black,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formattedTime,
                      style: TextStyle(
                        fontSize: 10,
                        color: isCurrentUser ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(width: 5),
                    if (isCurrentUser)
                      Icon(
                        Icons.done_all,
                        size: 15,
                        color: isRead ? Colors.blue.shade900 : Colors.white60,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserInput() {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 50.0,
        top: 10,
        left: 20,
        right: 20,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              focusNode: myFocusNode,
              decoration: InputDecoration(
                hintText: "Type a message",
                filled: true,
                fillColor: Colors.white,
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.grey),
                  borderRadius: BorderRadius.circular(20),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.green),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: sendMessage,
              icon: const Icon(Icons.arrow_upward, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
