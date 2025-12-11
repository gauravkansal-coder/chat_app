import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/chat_service.dart';

class ChatPage extends StatefulWidget {
  final String? receiverEmail;
  final String? receiverID;

  const ChatPage({super.key, this.receiverEmail, this.receiverID});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();

  final ChatService _chatService = ChatService();
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

  // SEND MESSAGE
  void sendMessage() async {
    if (_messageController.text.isNotEmpty) {
      // CHECK: Is this a Group Chat (null ID) or Private Chat?
      if (widget.receiverID == null) {
        // --- GROUP CHAT SEND ---
        await FirebaseFirestore.instance.collection('messages').add({
          'senderID': _auth.currentUser!.uid,
          'senderEmail': _auth.currentUser!.email,
          'message': _messageController.text,
          'timestamp': Timestamp.now(),
        });
      } else {
        // --- PRIVATE CHAT SEND ---
        await _chatService.sendMessage(
          widget.receiverID!,
          _messageController.text,
        );
      }

      _messageController.clear();
      scrollDown();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.receiverEmail ?? "Team Chat"), // Fallback title
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
    String currentUserID = _auth.currentUser!.uid;

    // DETERMINE THE STREAM SOURCE
    Stream<QuerySnapshot> stream;
    if (widget.receiverID == null) {
      // Group Chat Stream
      stream = FirebaseFirestore.instance
          .collection('messages')
          .orderBy('timestamp', descending: false)
          .snapshots();
    } else {
      // Private Chat Stream
      stream = _chatService.getMessages(widget.receiverID!, currentUserID);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('Error');
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // TRIGGER READ RECEIPT (Only for Private Chat)
        if (snapshot.hasData && widget.receiverID != null) {
          Future.microtask(
            () => _chatService.markMessagesAsRead(widget.receiverID!),
          );
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

    // Align content
    bool isCurrentUser = data['senderID'] == _auth.currentUser!.uid;
    var alignment = isCurrentUser
        ? Alignment.centerRight
        : Alignment.centerLeft;

    // Timestamp formatting
    Timestamp? t = data['timestamp'];
    DateTime d = t != null ? t.toDate() : DateTime.now();
    String formattedTime = "${d.hour}:${d.minute.toString().padLeft(2, '0')}";

    // Check Read Status
    bool isRead = data['isRead'] ?? false;

    // Handle old keys ('text') vs new keys ('message')
    String messageContent = data['message'] ?? data['text'] ?? "";
    String senderEmail = data['senderEmail'] ?? data['sender'] ?? "Unknown";

    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Column(
        crossAxisAlignment: isCurrentUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Show Name in Group Chat (if not me)
          if (!isCurrentUser && widget.receiverID == null)
            Padding(
              padding: const EdgeInsets.only(left: 5.0, bottom: 2.0),
              child: Text(
                senderEmail,
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),

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
                  messageContent,
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
                    // Show Blue Ticks ONLY for Private Chat & Current User
                    if (isCurrentUser && widget.receiverID != null) ...[
                      const SizedBox(width: 5),
                      Icon(
                        Icons.done_all,
                        size: 15,
                        color: isRead
                            ? const Color.fromARGB(255, 12, 59, 141)
                            : Colors.white60,
                      ),
                    ],
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
