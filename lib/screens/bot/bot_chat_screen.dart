import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../providers/auth_provider.dart' show AuraAuthProvider;

class BotChatScreen extends StatefulWidget {
  final String chatId; // = bot doc id (per web structure)
  final String botName;

  const BotChatScreen({
    super.key,
    required this.chatId,
    required this.botName,
  });

  @override
  State<BotChatScreen> createState() => _BotChatScreenState();
}

class _BotChatScreenState extends State<BotChatScreen> {
  // ═══════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════
  String? _botId;
  Map<String, dynamic>? _botData;
  List<Map<String, dynamic>> _messages = [];
  StreamSubscription<QuerySnapshot>? _msgSub;

  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final ImagePicker _picker = ImagePicker();

  XFile? _pendingMedia;

  bool _loading = true;
  bool _sending = false;
  bool _initialised = false;

  static const _cloudName = 'dn2mwp1lc';
  static const _uploadPreset = 'aura_chat';

  // ═══════════════════════════════════════════════════════════════
  // BOOT
  // ═══════════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    _inputCtrl.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialised) {
      _initialised = true;
      _botId = widget.chatId;
      _loadBot();
    }
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String get _myUid {
    final auth = Provider.of<AuraAuthProvider>(context, listen: false);
    return auth.currentUserId ??
        FirebaseAuth.instance.currentUser?.uid ??
        '';
  }

  // ═══════════════════════════════════════════════════════════════
  // LOAD BOT
  // ═══════════════════════════════════════════════════════════════
  Future<void> _loadBot() async {
    if (_botId == null || _botId!.isEmpty) {
      _toast('Bot not found');
      Navigator.pop(context);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('bots')
          .doc(_botId)
          .get();

      if (!doc.exists) {
        _toast('Bot not found');
        if (mounted) Navigator.pop(context);
        return;
      }

      _botData = doc.data();

      // Ensure chat doc exists (mirrors web logic)
      final uid = _myUid;
      if (uid.isNotEmpty) {
        final chatDoc = await FirebaseFirestore.instance
            .collection('chats')
            .doc(_botId)
            .get();

        if (!chatDoc.exists) {
          await FirebaseFirestore.instance
              .collection('chats')
              .doc(_botId)
              .set({
            'id': _botId,
            'type': 'bot',
            'name': _botData?['name'] ?? widget.botName,
            'username': _botData?['username'] ?? '',
            'about': _botData?['about'] ?? '',
            'avatar_url': _botData?['avatar_url'],
            'owner_id': _botData?['owner_id'],
            'participants': [uid],
            'participants_data': {
              uid: {'role': 'subscriber'},
            },
            'created_at': FieldValue.serverTimestamp(),
            'last_message': '',
            'last_message_at': FieldValue.serverTimestamp(),
          });
        } else {
          await FirebaseFirestore.instance
              .collection('chats')
              .doc(_botId)
              .update({
            'participants': FieldValue.arrayUnion([uid]),
            'participants_data.$uid': {'role': 'subscriber'},
          }).catchError((_) {});
        }
      }

      _listenToMessages();

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint('loadBot error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // MESSAGES LISTENER
  // ═══════════════════════════════════════════════════════════════
  void _listenToMessages() {
    if (_botId == null) return;
    _msgSub?.cancel();

    _msgSub = FirebaseFirestore.instance
        .collection('chats')
        .doc(_botId)
        .collection('messages')
        .orderBy('created_at', descending: false)
        .limit(200)
        .snapshots()
        .listen((snap) {
      final uid = _myUid;
      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        if (data['deleted_for_everyone'] == true) continue;
        final df = List<String>.from(data['deleted_for'] ?? []);
        if (df.contains(uid)) continue;
        list.add(data);
      }
      if (!mounted) return;
      setState(() => _messages = list);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollBottom());
    }, onError: (e) {
      debugPrint('messages error: $e');
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // SEND
  // ═══════════════════════════════════════════════════════════════
  Future<void> _sendStart() async {
    await _sendMessage('/start');
  }

  Future<void> _sendUserMsg() async {
    final text = _inputCtrl.text.trim();
    final hasImage = _pendingMedia != null;
    if (text.isEmpty && !hasImage) return;

    _inputCtrl.clear();

    if (hasImage) {
      final media = _pendingMedia!;
      setState(() => _pendingMedia = null);
      _toast('Uploading...');
      try {
        final url = await _uploadToCloudinary(File(media.path));
        await _sendMessage(text.isEmpty ? null : text, url, 'image');
      } catch (e) {
        _toast('Upload failed');
      }
      return;
    }

    await _sendMessage(text);
  }

  Future<void> _sendMessage(
    String? text, [
    String? mediaUrl,
    String? mediaType,
  ]) async {
    final uid = _myUid;
    if (uid.isEmpty || _botId == null) return;

    setState(() => _sending = true);
    try {
      final ref = FirebaseFirestore.instance
          .collection('chats')
          .doc(_botId)
          .collection('messages')
          .doc();

      await ref.set({
        'id': ref.id,
        'text': text,
        'content': text,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'sender_id': uid,
        'created_at': FieldValue.serverTimestamp(),
        'reactions': {},
        'views': 0,
        'deleted_for_everyone': false,
        'is_edited': false,
      });

      String preview = '';
      if (text != null && text.isNotEmpty) {
        preview = text.length > 80 ? text.substring(0, 80) : text;
      } else if (mediaType == 'image') {
        preview = '📷 Photo';
      }

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_botId)
          .update({
        'last_message': preview,
        'last_message_at': FieldValue.serverTimestamp(),
      }).catchError((_) {});
    } catch (e) {
      debugPrint('send error: $e');
      _toast('Failed to send');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // UPLOAD
  // ═══════════════════════════════════════════════════════════════
  Future<String> _uploadToCloudinary(File file) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
    );
    final req = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..fields['folder'] = 'aura_chat/bots'
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await req.send();
    if (streamed.statusCode != 200) {
      throw Exception('Upload failed: ${streamed.statusCode}');
    }
    final body = await streamed.stream.bytesToString();
    final data = jsonDecode(body);
    return data['secure_url'] as String;
  }

  // ═══════════════════════════════════════════════════════════════
  // PICK IMAGE
  // ═══════════════════════════════════════════════════════════════
  Future<void> _pickImage() async {
    // Show sheet: camera or gallery
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1a103c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFF8B5CF6)),
              title: const Text('Camera',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: Color(0xFF8B5CF6)),
              title: const Text('Gallery',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 90);
      if (picked == null) return;
      setState(() => _pendingMedia = picked);
    } catch (e) {
      _toast('Picker error');
    }
  }

  void _clearPendingMedia() {
    setState(() => _pendingMedia = null);
  }

  // ═══════════════════════════════════════════════════════════════
  // NAVIGATION
  // ═══════════════════════════════════════════════════════════════
  void _openBotProfile() {
    if (_botId == null) return;
    Navigator.pushNamed(
      context,
      '/bot_profile',
      arguments: {
        'botId': _botId!,
        'botName': _botData?['name'] ?? widget.botName,
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════
  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1A1822),
      ),
    );
  }

  void _scrollBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgD = DateTime(d.year, d.month, d.day);
    final diff = today.difference(msgD).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${months[d.month - 1]} ${d.day}';
  }

  String _formatSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1048576).toStringAsFixed(1)} MB';
  }

  // Very small markdown-ish renderer matching web's linkify()
  List<TextSpan> _buildSpans(String text, {required bool isMe}) {
    final base = TextStyle(
      color: isMe ? Colors.white : Colors.white,
      fontSize: 14.5,
      height: 1.5,
    );

    final linkColor = isMe ? Colors.white : const Color(0xFFC4B5FD);
    final boldColor = isMe ? Colors.white : const Color(0xFFC4B5FD);

    final spans = <TextSpan>[];
    // Split into tokens: urls, *bold*, _italic_, `code`, plain
    final pattern = RegExp(
      r'(https?://[^\s]+)|\*([^*]+)\*|_([^_]+)_|`([^`]+)`',
    );

    int last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start), style: base));
      }
      if (m.group(1) != null) {
        spans.add(TextSpan(
          text: m.group(1),
          style: base.copyWith(
            color: linkColor,
            decoration:
                isMe ? TextDecoration.underline : TextDecoration.none,
          ),
        ));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(
          text: m.group(2),
          style: base.copyWith(fontWeight: FontWeight.w700, color: boldColor),
        ));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(
          text: m.group(3),
          style: base.copyWith(color: Colors.white70),
        ));
      } else if (m.group(4) != null) {
        spans.add(TextSpan(
          text: m.group(4),
          style: base.copyWith(
            fontFamily: 'monospace',
            backgroundColor: isMe
                ? Colors.black.withOpacity(0.25)
                : const Color(0xFFA855F7).withOpacity(0.15),
          ),
        ));
      }
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: base));
    }
    return spans;
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final hasMessages = _messages.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1.2),
            radius: 1.5,
            colors: [
              Color(0x148B5CF6),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFA855F7),
                        ),
                      )
                    : hasMessages
                        ? _buildMessagesList()
                        : _buildEmptyState(),
              ),
              if (_pendingMedia != null) _buildMediaPreview(),
              if (hasMessages) _buildInputArea(),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final avatar = _botData?['avatar_url'] as String?;
    final name = _botData?['name'] as String? ?? widget.botName;
    final username = _botData?['username'] as String? ?? 'bot';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F).withOpacity(0.95),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: GestureDetector(
              onTap: _openBotProfile,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFA855F7), Color(0xFF3B82F6)],
                      ),
                    ),
                    child: ClipOval(
                      child: (avatar != null && avatar.isNotEmpty)
                          ? Image.network(
                              avatar,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.smart_toy,
                                color: Colors.white,
                                size: 20,
                              ),
                            )
                          : const Icon(Icons.smart_toy,
                              color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.01,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFA855F7),
                                    Color(0xFF3B82F6),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'BOT',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@$username',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.35),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: _openBotProfile,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final avatar = _botData?['avatar_url'] as String?;
    final name = _botData?['name'] as String? ?? widget.botName;
    final about = _botData?['about'] as String? ??
        'Start a conversation with this bot.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFA855F7), Color(0xFF3B82F6)],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: (avatar != null && avatar.isNotEmpty)
                    ? Image.network(avatar, fit: BoxFit.cover)
                    : const Icon(Icons.smart_toy,
                        color: Colors.white, size: 38),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.02,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              about,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 13.5,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _sendStart,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFA855F7), Color(0xFF3B82F6)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_arrow, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Start',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isMe = msg['sender_id'] == _myUid;
        final text = (msg['text'] ?? msg['content'] ?? '') as String;
        final mediaUrl = msg['media_url'] as String?;
        final mediaType = msg['media_type'] as String?;
        final ts = msg['created_at'] as Timestamp?;

        // Date divider
        final prev = index > 0 ? _messages[index - 1] : null;
        final prevTs = prev?['created_at'] as Timestamp?;
        final showDate = _formatDate(ts) != _formatDate(prevTs);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDate)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _formatDate(ts),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            Align(
              alignment:
                  isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: 4),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.82,
                ),
                decoration: BoxDecoration(
                  gradient: isMe
                      ? const LinearGradient(
                          colors: [
                            Color(0xFFA855F7),
                            Color(0xFF3B82F6),
                          ],
                        )
                      : null,
                  color: isMe ? null : const Color(0xFF1C1A24),
                  border: isMe
                      ? null
                      : Border.all(color: Colors.white.withOpacity(0.06)),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 6),
                    bottomRight: Radius.circular(isMe ? 6 : 16),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (mediaType == 'image' &&
                          mediaUrl != null &&
                          mediaUrl.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: ConstrainedBox(
                              constraints:
                                  const BoxConstraints(maxHeight: 280),
                              child: Image.network(
                                mediaUrl,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, prog) {
                                  if (prog == null) return child;
                                  return Container(
                                    height: 180,
                                    color: Colors.black26,
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFFA855F7),
                                      ),
                                    ),
                                  );
                                },
                                errorBuilder: (_, __, ___) => Container(
                                  height: 180,
                                  color: Colors.black26,
                                  child: const Icon(Icons.broken_image,
                                      color: Colors.white54),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (text.isNotEmpty)
                        RichText(
                          text: TextSpan(
                            children: _buildSpans(text, isMe: isMe),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          _formatTime(ts),
                          style: TextStyle(
                            color: isMe
                                ? Colors.white.withOpacity(0.7)
                                : Colors.white.withOpacity(0.4),
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMediaPreview() {
    final f = _pendingMedia!;
    final size = File(f.path).lengthSync();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFA855F7).withOpacity(0.08),
          border: Border.all(
            color: const Color(0xFFA855F7).withOpacity(0.2),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(f.path),
                width: 44,
                height: 44,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    f.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatSize(size),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.35),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54),
              onPressed: _clearPendingMedia,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F).withOpacity(0.95),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.06)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.image,
                color: Colors.white.withOpacity(0.55),
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _inputCtrl,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendUserMsg(),
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Message...',
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.35),
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 11,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : _sendUserMsg,
            child: Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFFA855F7), Color(0xFF3B82F6)],
                ),
              ),
              child: _sending
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send,
                      color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
