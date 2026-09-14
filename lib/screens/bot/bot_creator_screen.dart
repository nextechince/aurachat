import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart' show AuraAuthProvider;

// ═══════════════════════════════════════════════════════════════
// BotCreatorScreen — Dart port of bot_creator.html
// ═══════════════════════════════════════════════════════════════
class BotCreatorScreen extends StatefulWidget {
  final String? editBotId;
  final String? editUsername;

  const BotCreatorScreen({
    super.key,
    this.editBotId,
    this.editUsername,
  });

  @override
  State<BotCreatorScreen> createState() => _BotCreatorScreenState();
}

class _BotCreatorScreenState extends State<BotCreatorScreen> {
  // ═══════════════════════════════════════════════════════════════
  // STATE
  // ═══════════════════════════════════════════════════════════════
  static const _cloudName = 'dn2mwp1lc';
  static const _uploadPreset = 'aura_chat';

  String? _currentUserId;
  String? _bcChatId;

  /// Chat state machine — mirrors web's `chatState`
  String _chatState = 'idle';
  Map<String, dynamic> _tempBot = {};

  XFile? _pendingMedia;
  bool _initialised = false;
  bool _botTyping = false;

  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final ImagePicker _picker = ImagePicker();

  /// In-memory message list — mirrors what we render
  List<_BCMessage> _messages = [];

  final _cameraInput = ImagePicker();

  // ═══════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialised) {
      _initialised = true;
      _init();
    }
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String? get _uid {
    final auth = Provider.of<AuraAuthProvider>(context, listen: false);
    return auth.currentUserId ??
        FirebaseAuth.instance.currentUser?.uid;
  }

  // ═══════════════════════════════════════════════════════════════
  // INIT
  // ═══════════════════════════════════════════════════════════════
  Future<void> _init() async {
    _currentUserId = _uid;
    if (_currentUserId == null) {
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
            context, '/', (route) => false);
      }
      return;
    }

    await _bcEnsureChat();
    final hadHistory = await _bcLoadHistory();

    // If opened with editBotId passed via args (from BotProfile)
    if (widget.editBotId != null &&
        widget.editUsername != null &&
        widget.editUsername!.isNotEmpty) {
      await _botSay(
        '👋 Welcome back! Manage <strong>@${widget.editUsername}</strong>:',
        buttons: [
          _BCButton(label: 'Name', onTap: () => _quickCmd('/setname')),
          _BCButton(
              label: 'About', onTap: () => _quickCmd('/setdescription')),
          _BCButton(
              label: 'Picture', onTap: () => _quickCmd('/setuserpic')),
          _BCButton(label: 'Revoke', onTap: () => _quickCmd('/revoke')),
          _BCButton(
            label: 'Token',
            primary: true,
            onTap: () =>
                _quickCmd('/token @${widget.editUsername}'),
          ),
          _BCButton(
            label: 'Delete',
            danger: true,
            onTap: () => _quickCmd('/deletebot'),
          ),
        ],
      );
      return;
    }

    if (!hadHistory) {
      await _botSay(
        '👋 Welcome to <strong>BotCreator</strong>!\n\n'
        'I create and manage bots for AURA.\n\n'
        'Type <code>/newbot</code> to get started — '
        'or <code>/help</code> for commands.',
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // CHAT DOC — one per user
  // ═══════════════════════════════════════════════════════════════
  Future<void> _bcEnsureChat() async {
    _bcChatId = 'botcreator_$_currentUserId';
    final ref = FirebaseFirestore.instance
        .collection('chats')
        .doc(_bcChatId);
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        'id': _bcChatId,
        'type': 'bot',
        'subtype': 'botcreator',
        'name': 'BotCreator',
        'username': 'BotCreator',
        'about': 'Your personal bot factory',
        'avatar_url': null,
        'owner_id': _currentUserId,
        'participants': [_currentUserId],
        'participants_data': {},
        'created_at': FieldValue.serverTimestamp(),
        'last_message': 'Bot factory',
        'last_message_at': FieldValue.serverTimestamp(),
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // SAVE MESSAGE TO FIRESTORE
  // ═══════════════════════════════════════════════════════════════
  Future<void> _bcSaveMsg(
    String sender,
    String? text,
    String? html, {
    String? mediaUrl,
    String? mediaType,
  }) async {
    if (_bcChatId == null) return;
    try {
      final ref = FirebaseFirestore.instance
          .collection('chats')
          .doc(_bcChatId)
          .collection('messages')
          .doc();
      await ref.set({
        'id': ref.id,
        'sender_id':
            sender == 'user' ? _currentUserId : 'botcreator',
        'sender_name': sender == 'user' ? 'You' : 'BotCreator',
        'text': text,
        'content': text,
        'html': html,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'created_at': FieldValue.serverTimestamp(),
      });

      String preview;
      if (sender == 'user') {
        if (mediaType == 'image') {
          preview = '📷 Photo';
        } else {
          preview = (text ?? '').length > 60
              ? text!.substring(0, 60)
              : (text ?? '');
        }
      } else {
        final plain = (text ?? '')
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        preview = plain.isEmpty
            ? 'Reply'
            : (plain.length > 60 ? plain.substring(0, 60) : plain);
      }

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_bcChatId)
          .update({
        'last_message': preview,
        'last_message_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('bcSaveMsg error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // LOAD HISTORY
  // ═══════════════════════════════════════════════════════════════
  Future<bool> _bcLoadHistory() async {
    if (_bcChatId == null) return false;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('chats')
          .doc(_bcChatId)
          .collection('messages')
          .orderBy('created_at')
          .limit(300)
          .get();

      if (snap.docs.isEmpty) return false;

      final list = <_BCMessage>[];
      for (final doc in snap.docs) {
        final m = doc.data();
        list.add(_BCMessage(
          isOut: m['sender_id'] == _currentUserId,
          html: m['html'] as String?,
          text: (m['text'] ?? m['content']) as String?,
          imageUrl: m['media_url'] as String?,
        ));
      }
      if (mounted) setState(() => _messages = list);
      _scrollBottom();
      return true;
    } catch (e) {
      debugPrint('bcLoadHistory error: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ADD MESSAGE (client side)
  // ═══════════════════════════════════════════════════════════════
  void _addMsg(
    String text, {
    bool out = false,
    String? html,
    String? imageUrl,
    List<_BCButton>? buttons,
  }) {
    setState(() {
      _messages = [
        ..._messages,
        _BCMessage(
          isOut: out,
          html: html,
          text: text,
          imageUrl: imageUrl,
          buttons: buttons,
        ),
      ];
    });
    _scrollBottom();
  }

  // ═══════════════════════════════════════════════════════════════
  // BOT SAY (typing + delay)
  // ═══════════════════════════════════════════════════════════════
  Future<void> _botSay(
    String text, {
    String? html,
    List<_BCButton>? buttons,
    int delay = 420,
  }) async {
    setState(() => _botTyping = true);
    _scrollBottom();
    await Future.delayed(Duration(milliseconds: delay));
    if (!mounted) return;
    setState(() => _botTyping = false);
    _addMsg(text, html: html, buttons: buttons);
    await _bcSaveMsg('bot', text, html);
  }

  // ═══════════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════════
  void _quickCmd(String c) {
    _inputCtrl.text = c;
    _sendUserMsg();
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toast(String m, {bool success = false, bool error = false}) {
    if (!mounted) return;
    final bg = success
        ? const Color(0xFF4ADE80).withOpacity(0.15)
        : error
            ? const Color(0xFFEF4444).withOpacity(0.15)
            : const Color(0xFF1A103C);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      behavior: SnackBarBehavior.floating,
      backgroundColor: bg,
      duration: const Duration(seconds: 2),
    ));
  }

  String _genToken() {
    final botId =
        (100000000 + Random().nextInt(900000000)).toString();
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
    final rand = Random();
    final secret = List.generate(
        35, (_) => chars[rand.nextInt(chars.length)]).join();
    return '$botId:$secret';
  }

  String _escapeHtml(String t) {
    return t
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  // ═══════════════════════════════════════════════════════════════
  // SEND — command parser
  // ═══════════════════════════════════════════════════════════════
  Future<void> _sendUserMsg() async {
    final text = _inputCtrl.text.trim();
    final hasImage = _pendingMedia != null;
    if (text.isEmpty && !hasImage) return;
    _inputCtrl.clear();

    // Image path
    if (hasImage) {
      final media = _pendingMedia!;
      setState(() => _pendingMedia = null);

      _addMsg('', out: true, imageUrl: media.path);
      // Save with a placeholder URL for the local preview (web does the same)
      await _bcSaveMsg('user', null, null,
          mediaUrl: media.path, mediaType: 'image');

      if (_chatState == 'awaiting_bot_avatar' ||
          _chatState == 'awaiting_edit_avatar') {
        final botId = _tempBot['id'] as String?;
        if (botId == null) {
          await _botSay('❌ No bot selected.');
          return;
        }
        setState(() => _botTyping = true);
        _toast('Uploading picture...');
        try {
          final url = await _uploadToCloudinary(File(media.path));
          await FirebaseFirestore.instance
              .collection('bots')
              .doc(botId)
              .update({'avatar_url': url});
          await FirebaseFirestore.instance
              .collection('chats')
              .doc(botId)
              .update({'avatar_url': url});
          await FirebaseFirestore.instance
              .collection('users')
              .doc(botId)
              .update({'avatar_url': url});
          if (!mounted) return;
          setState(() => _botTyping = false);
          _toast('✅ Picture set!', success: true);
          if (_chatState == 'awaiting_bot_avatar') {
            await _skipAvatar();
          } else {
            await _botSay('✅ Profile picture updated.');
            _resetState();
          }
        } catch (e) {
          if (!mounted) return;
          setState(() => _botTyping = false);
          await _botSay('❌ Upload failed: $e');
        }
        return;
      }

      await _botSay(
          '📷 I only use images as profile pics when creating or editing a bot.');
      return;
    }

    // Text path
    _addMsg(text, out: true);
    await _bcSaveMsg('user', text, null);

    if (text.startsWith('/')) {
      if (_chatState != 'idle' &&
          text.trim().toLowerCase() != '/cancel') {
        _resetState();
      }
      await _handleCommand(text);
      return;
    }

    // State machine (non-command text)
    switch (_chatState) {
      case 'awaiting_bot_name':
        await _handleBotName(text);
        break;
      case 'awaiting_bot_username':
        await _handleBotUsername(text);
        break;
      case 'awaiting_edit_name':
        await _handleEditName(text);
        break;
      case 'awaiting_edit_about':
        await _handleEditAbout(text);
        break;
      case 'awaiting_edit_username':
        await _handleEditUsername(text);
        break;
      case 'awaiting_bot_avatar':
      case 'awaiting_edit_avatar':
        await _botSay(
            'Please send an image file, or tap Skip.');
        break;
      default:
        await _botSay(
            'I only understand commands. Try /help');
    }
  }

  void _resetState() {
    _chatState = 'idle';
    _tempBot = {};
  }

  // ═══════════════════════════════════════════════════════════════
  // COMMAND DISPATCHER
  // ═══════════════════════════════════════════════════════════════
  Future<void> _handleCommand(String rawText) async {
    final parts = rawText.trim().split(RegExp(r'\s+'));
    final cmd = parts.first.toLowerCase();
    final args = parts.length > 1 ? parts.sublist(1) : <String>[];

    switch (cmd) {
      case '/start':
        await _botSay(
          '',
          html:
              '👋 Hello! I\'m <strong>BotCreator</strong>.\n\n'
              'I can help you create and manage bots for AURA.\n\n'
              'Type <code>/newbot</code> to get started, '
              'or <code>/help</code> for all commands.',
        );
        return;

      case '/help':
        await _botSay(
          '',
          html:
              '<strong>📖 BotCreator Commands</strong>\n\n'
              '<strong>Create & Manage</strong>\n'
              '<code>/newbot</code> — Create a new bot\n'
              '<code>/mybots</code> — List your bots\n'
              '<code>/deletebot</code> — Delete a bot\n\n'
              '<strong>Bot Settings</strong>\n'
              '<code>/token</code> — Get API token\n'
              '<code>/setname</code> — Change display name\n'
              '<code>/setdescription</code> — Change about text\n'
              '<code>/setuserpic</code> — Change profile picture\n'
              '<code>/setusername</code> — Change @username\n'
              '<code>/revoke</code> — Regenerate token\n\n'
              '<strong>Developer</strong>\n'
              '<code>/docs</code> — API documentation\n'
              '<code>/package</code> — npm / pip install\n\n'
              '<strong>Other</strong>\n'
              '<code>/cancel</code> — Cancel current action',
          delay: 300,
        );
        return;

      case '/cancel':
        _resetState();
        await _botSay('✅ Cancelled.');
        return;

      case '/newbot':
        _chatState = 'awaiting_bot_name';
        _tempBot = {};
        await _botSay(
            'Alright, a new bot! 🎉\n\n'
            'What should we call it?\n\n'
            '<em>Display name (2–40 chars). Emojis allowed.</em>');
        return;

      case '/mybots':
        await _listMyBots();
        return;

      case '/token':
        if (args.isEmpty) {
          await _botSay(
              'Usage: <code>/token @yourbotusername</code>\n'
              'Or use /mybots to pick one.');
          return;
        }
        await _sendTokenForUsername(args.first);
        return;

      case '/setname':
        _chatState = 'awaiting_bot_to_edit';
        _tempBot['editAction'] = 'setname';
        await _pickBotForEdit('Choose a bot to rename:');
        return;

      case '/setdescription':
        _chatState = 'awaiting_bot_to_edit';
        _tempBot['editAction'] = 'setdescription';
        await _pickBotForEdit(
            'Choose a bot to change about text:');
        return;

      case '/setuserpic':
        _chatState = 'awaiting_bot_to_edit';
        _tempBot['editAction'] = 'setuserpic';
        await _pickBotForEdit(
            'Choose a bot to change profile picture:');
        return;

      case '/setusername':
        _chatState = 'awaiting_bot_to_edit';
        _tempBot['editAction'] = 'setusername';
        await _pickBotForEdit(
            'Choose a bot to rename @username:');
        return;

      case '/revoke':
        _chatState = 'awaiting_bot_to_edit';
        _tempBot['editAction'] = 'revoke';
        await _pickBotForEdit(
            'Choose a bot to regenerate its token:');
        return;

      case '/deletebot':
        _chatState = 'awaiting_bot_to_edit';
        _tempBot['editAction'] = 'deletebot';
        await _pickBotForEdit('Choose a bot to delete:');
        return;

      case '/docs':
        await _botSay(
          '',
          html:
              '<strong>📚 AURA Bot API</strong>\n\n'
              'Base URL: <code>/api/bot/&lt;TOKEN&gt;</code>\n\n'
              '<strong>Endpoints</strong>\n'
              '<code>GET  /getMe</code>\n'
              '<code>GET  /getUpdates</code>\n'
              '<code>POST /sendMessage</code>\n'
              '<code>POST /sendPhoto</code>\n'
              '<code>POST /setWebhook</code>\n\n'
              '<strong>Packages</strong>\n'
              '• Node: <code>npm i aura-bot-api</code>\n'
              '• Python: <code>pip install aura-bot</code>',
        );
        return;

      case '/package':
        await _botSay(
          '',
          html:
              '<strong>📦 Install the SDK</strong>\n\n'
              '<strong>Node.js</strong>\n'
              '<pre>npm install aura-bot-api\n\n'
              'const AuraBot = require(\'aura-bot-api\');\n'
              'const bot = new AuraBot(\'YOUR_TOKEN\');\n\n'
              'bot.on(\'message\', msg => {\n'
              '  bot.sendMessage(msg.chat.id, \'Hi!\');\n'
              '});\n\n'
              'bot.start();</pre>\n\n'
              '<strong>Python</strong>\n'
              '<pre>pip install aura-bot\n\n'
              'from aura_bot import Bot\n'
              'bot = Bot(\'YOUR_TOKEN\')\n\n'
              '@bot.message()\n'
              'def handle(msg):\n'
              '    bot.send_message(msg[\'chat\'][\'id\'], \'Hi!\')\n\n'
              'bot.run()</pre>',
        );
        return;

      default:
        await _botSay('Unknown command: <code>$cmd</code>\n\n'
            'Try /help');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // CREATE FLOW — name → username → avatar
  // ═══════════════════════════════════════════════════════════════
  Future<void> _handleBotName(String name) async {
    if (name.length < 2 || name.length > 40) {
      await _botSay('Name must be 2–40 characters. Try again:');
      return;
    }
    _tempBot['name'] = name;
    _chatState = 'awaiting_bot_username';
    await _botSay(
        'Nice! Now choose an <strong>@username</strong>.\n\n'
        '<em>Rules: 4–31 chars, starts with letter, '
        'letters/numbers/underscore, must end in "bot".</em>\n\n'
        '<em>Example: @MyCoolBot</em>');
  }

  Future<void> _handleBotUsername(String raw) async {
    final uname = raw.trim().replaceFirst(RegExp(r'^@'), '');
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{3,30}$').hasMatch(uname)) {
      await _botSay(
          'Invalid format. Must be 4–31 chars, start with letter. Try again:');
      return;
    }
    if (!uname.toLowerCase().endsWith('bot')) {
      await _botSay('❌ Username must end in "bot". Try again:');
      return;
    }

    final exists = await FirebaseFirestore.instance
        .collection('bots')
        .where('username', isEqualTo: uname)
        .limit(1)
        .get();
    if (exists.docs.isNotEmpty) {
      await _botSay('❌ @$uname is taken. Try another:');
      return;
    }

    _tempBot['username'] = uname;
    final token = _genToken();

    try {
      final botRef = FirebaseFirestore.instance.collection('bots').doc();
      final botId = botRef.id;
      final now = FieldValue.serverTimestamp();

      await botRef.set({
        'id': botId,
        'owner_id': _currentUserId,
        'name': _tempBot['name'],
        'username': uname,
        'about': '',
        'avatar_url': null,
        'token': token,
        'created_at': now,
        'is_public': true,
        'type': 'bot',
        'subscribers': 0,
        'commands': ['/start', '/help'],
      });

      await FirebaseFirestore.instance
          .collection('users')
          .doc(botId)
          .set({
        'uid': botId,
        'username': uname,
        'display_name': _tempBot['name'],
        'avatar_url': null,
        'about': '',
        'email': '${uname}@bot.aurachat.app',
        'is_bot': true,
        'bot_owner': _currentUserId,
        'is_verified': false,
        'created_at': now,
      });

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(botId)
          .set({
        'id': botId,
        'type': 'bot',
        'name': _tempBot['name'],
        'username': uname,
        'about': '',
        'avatar_url': null,
        'owner_id': _currentUserId,
        'participants': [_currentUserId],
        'participants_data': {},
        'created_at': now,
        'last_message': 'Bot created',
        'last_message_at': now,
      });

      _chatState = 'awaiting_bot_avatar';
      _tempBot['id'] = botId;
      _tempBot['token'] = token;

      await _botSay(
        '',
        html:
            '<strong>🎉 Bot created!</strong>\n\n'
            'You can find it at <code>@$uname</code>.\n\n'
            '<strong>🔑 API Token:</strong>\n'
            '<pre>$token</pre>\n\n'
            '<em>⚠ Keep this secret. Anyone with this token '
            'controls your bot.</em>\n\n'
            '📷 Now send me a <strong>profile picture</strong> '
            'for your bot — attach an image below.\n\n'
            '<em>Or tap Skip.</em>',
        buttons: [
          _BCButton(label: 'Skip', onTap: _skipAvatar),
        ],
        delay: 500,
      );
    } catch (e) {
      debugPrint('createBot error: $e');
      await _botSay('❌ Failed to create bot: $e');
      _resetState();
    }
  }

  Future<void> _skipAvatar() async {
    _chatState = 'idle';
    await _botSay(
      '',
      html:
          '<strong>✅ Your bot is ready!</strong>\n\n'
          '<strong>@${_tempBot['username']}</strong>\n\n'
          '<strong>Next steps</strong>\n'
          '1. Copy the token above\n'
          '2. Install: <code>npm i aura-bot-api</code>\n'
          '3. Deploy to your server\n\n'
          'Try these:\n'
          '<code>/token @${_tempBot['username']}</code>\n'
          '<code>/setdescription</code>\n'
          '<code>/setuserpic</code>\n'
          '<code>/mybots</code>',
      buttons: [
        _BCButton(
          label: '🤖 Open Bot',
          primary: true,
          onTap: () {
            if (!mounted) return;
            Navigator.pushNamed(context, '/bot_profile', arguments: {
              'botId': _tempBot['id'],
              'botName': _tempBot['name'],
            });
          },
        ),
      ],
    );
    _tempBot = {};
  }

  // ═══════════════════════════════════════════════════════════════
  // MY BOTS
  // ═══════════════════════════════════════════════════════════════
  Future<void> _listMyBots() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('bots')
          .where('owner_id', isEqualTo: _currentUserId)
          .get();

      if (snap.docs.isEmpty) {
        await _botSay(
            'You don\'t have any bots yet. Use /newbot to create one!');
        return;
      }

      final docs = snap.docs.toList()
        ..sort((a, b) {
          final aT = (a.data()['created_at'] as Timestamp?)
                  ?.millisecondsSinceEpoch ??
              0;
          final bT = (b.data()['created_at'] as Timestamp?)
                  ?.millisecondsSinceEpoch ??
              0;
          return bT.compareTo(aT);
        });

      var html = '<strong>Your bots (${docs.length}):</strong>\n\n';
      final buttons = <_BCButton>[];
      for (var i = 0; i < docs.length; i++) {
        final b = docs[i].data();
        html +=
            '${i + 1}. <strong>${_escapeHtml(b['name'] ?? '')}</strong> — @${b['username']}\n';
        final docId = docs[i].id;
        final botName = b['name'] ?? '';
        buttons.add(_BCButton(
          label: '@${b['username']}',
          primary: true,
          onTap: () {
            if (!mounted) return;
            Navigator.pushNamed(context, '/bot_profile', arguments: {
              'botId': docId,
              'botName': botName,
            });
          },
        ));
      }
      await _botSay('', html: html, buttons: buttons);
    } catch (e) {
      debugPrint('listMyBots error: $e');
      await _botSay('❌ Error loading bots: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // PICK BOT FOR EDIT
  // ═══════════════════════════════════════════════════════════════
  Future<void> _pickBotForEdit(String prompt) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('bots')
          .where('owner_id', isEqualTo: _currentUserId)
          .get();

      if (snap.docs.isEmpty) {
        await _botSay('No bots found. Create one with /newbot first.');
        _resetState();
        return;
      }

      final docs = snap.docs.toList()
        ..sort((a, b) {
          final aT = (a.data()['created_at'] as Timestamp?)
                  ?.millisecondsSinceEpoch ??
              0;
          final bT = (b.data()['created_at'] as Timestamp?)
                  ?.millisecondsSinceEpoch ??
              0;
          return bT.compareTo(aT);
        });

      final buttons = docs.map((doc) {
        final b = doc.data();
        return _BCButton(
          label: '@${b['username']}',
          primary: true,
          onTap: () => _selectBot(doc.id, b['username'] as String),
        );
      }).toList();

      await _botSay(prompt, buttons: buttons);
    } catch (e) {
      debugPrint('pickBotForEdit error: $e');
      await _botSay('❌ Error loading bots: $e');
      _resetState();
    }
  }

  Future<void> _selectBot(String botId, String username) async {
    final doc = await FirebaseFirestore.instance
        .collection('bots')
        .doc(botId)
        .get();
    if (!doc.exists) {
      await _botSay('Bot not found.');
      return;
    }
    _tempBot['id'] = botId;
    _tempBot['username'] = username;

    final action = _tempBot['editAction'];

    switch (action) {
      case 'setname':
        _chatState = 'awaiting_edit_name';
        await _botSay(
            'OK. Send the new <strong>name</strong> for @$username');
        return;
      case 'setdescription':
        _chatState = 'awaiting_edit_about';
        await _botSay(
            'OK. Send the new <strong>About</strong> text (max 200 chars) for @$username');
        return;
      case 'setuserpic':
        _chatState = 'awaiting_edit_avatar';
        await _botSay(
            'OK. Send a new <strong>profile picture</strong> for @$username — attach an image below.');
        return;
      case 'setusername':
        _chatState = 'awaiting_edit_username';
        await _botSay(
            'OK. Send the new <strong>@username</strong> (must end in "bot").');
        return;
      case 'revoke':
        final newToken = _genToken();
        await FirebaseFirestore.instance
            .collection('bots')
            .doc(botId)
            .update({'token': newToken});
        await _botSay(
          '',
          html:
              '🔐 <strong>Token revoked</strong> for @$username\n\n'
              '<strong>New token:</strong>\n'
              '<pre>$newToken</pre>\n'
              'Your old token is now invalid.',
        );
        _resetState();
        return;
      case 'deletebot':
        _chatState = 'awaiting_delete_confirm';
        await _botSay(
          '',
          html:
              '⚠️ Delete <strong>@$username</strong>?\n\n'
              '<em>This cannot be undone.</em>',
          buttons: [
            _BCButton(
              label: 'Yes, delete',
              danger: true,
              onTap: () => _confirmDeleteBot(botId),
            ),
            _BCButton(label: 'Cancel', onTap: _cancelDelete),
          ],
        );
        return;
    }
  }

  Future<void> _confirmDeleteBot(String botId) async {
    try {
      await FirebaseFirestore.instance
          .collection('bots')
          .doc(botId)
          .delete();
      try {
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(botId)
            .delete();
      } catch (_) {}
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(botId)
            .delete();
      } catch (_) {}
      await _botSay('🗑 Bot deleted.');
    } catch (_) {
      await _botSay('Failed to delete.');
    }
    _resetState();
  }

  Future<void> _cancelDelete() async {
    await _botSay('Cancelled.');
    _resetState();
  }

  // ═══════════════════════════════════════════════════════════════
  // EDIT FIELDS
  // ═══════════════════════════════════════════════════════════════
  Future<void> _handleEditName(String name) async {
    if (name.length < 2 || name.length > 40) {
      await _botSay('2–40 chars. Try again:');
      return;
    }
    final id = _tempBot['id'];
    await FirebaseFirestore.instance
        .collection('bots')
        .doc(id)
        .update({'name': name});
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(id)
        .update({'name': name});
    await FirebaseFirestore.instance
        .collection('users')
        .doc(id)
        .update({'display_name': name});
    await _botSay('✅ Name changed to "$name".');
    _resetState();
  }

  Future<void> _handleEditAbout(String text) async {
    if (text.length > 200) {
      await _botSay('Max 200 chars. Try again:');
      return;
    }
    final id = _tempBot['id'];
    await FirebaseFirestore.instance
        .collection('bots')
        .doc(id)
        .update({'about': text});
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(id)
        .update({'about': text});
    await FirebaseFirestore.instance
        .collection('users')
        .doc(id)
        .update({'about': text});
    await _botSay('✅ About text updated.');
    _resetState();
  }

  Future<void> _handleEditUsername(String raw) async {
    final uname = raw.trim().replaceFirst(RegExp(r'^@'), '');
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{3,30}$').hasMatch(uname) ||
        !uname.toLowerCase().endsWith('bot')) {
      await _botSay('Invalid. Must end in "bot". Try again:');
      return;
    }
    final exists = await FirebaseFirestore.instance
        .collection('bots')
        .where('username', isEqualTo: uname)
        .limit(1)
        .get();
    if (exists.docs.isNotEmpty && exists.docs.first.id != _tempBot['id']) {
      await _botSay('❌ @$uname is taken. Try another:');
      return;
    }
    final id = _tempBot['id'];
    await FirebaseFirestore.instance
        .collection('bots')
        .doc(id)
        .update({'username': uname});
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(id)
        .update({'username': uname});
    await FirebaseFirestore.instance.collection('users').doc(id).update({
      'username': uname,
      'email': '${uname}@bot.aurachat.app',
    });
    await _botSay('✅ Username changed to @$uname.');
    _resetState();
  }

  // ═══════════════════════════════════════════════════════════════
  // TOKEN BY USERNAME
  // ═══════════════════════════════════════════════════════════════
  Future<void> _sendTokenForUsername(String raw) async {
    final uname = raw.replaceFirst(RegExp(r'^@'), '');
    final snap = await FirebaseFirestore.instance
        .collection('bots')
        .where('username', isEqualTo: uname)
        .where('owner_id', isEqualTo: _currentUserId)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) {
      await _botSay('❌ You don\'t own a bot with username @$uname');
      return;
    }

    final b = snap.docs.first.data();
    final botDocId = snap.docs.first.id;
    await _botSay(
      '',
      html:
          '<strong>🔑 Token for @${b['username']}</strong>\n\n'
          '<pre>${b['token']}</pre>\n\n'
          '<em>⚠ Keep this secret.</em>\n\n'
          'Host your bot with <code>npm i aura-bot-api</code> '
          'or <code>pip install aura-bot</code>.',
      buttons: [
        _BCButton(
          label: 'Open Bot',
          primary: true,
          onTap: () {
            if (!mounted) return;
            Navigator.pushNamed(context, '/bot_profile', arguments: {
              'botId': botDocId,
              'botName': b['name'] ?? '',
            });
          },
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // IMAGE PICKER
  // ═══════════════════════════════════════════════════════════════
  Future<void> _pickImage() async {
    // If we're awaiting avatar, show camera/gallery choice; otherwise just gallery
    final isAvatarFlow = _chatState == 'awaiting_bot_avatar' ||
        _chatState == 'awaiting_edit_avatar';

    ImageSource source = ImageSource.gallery;
    if (isAvatarFlow) {
      final chosen = await showModalBottomSheet<ImageSource>(
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
              ListTile(
                leading:
                    const Icon(Icons.camera_alt, color: Color(0xFF8B5CF6)),
                title: const Text('Camera',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library,
                    color: Color(0xFF8B5CF6)),
                title: const Text('Gallery',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (chosen == null) return;
      source = chosen;
    }

    try {
      final picked =
          await _picker.pickImage(source: source, imageQuality: 90);
      if (picked == null) return;
      setState(() => _pendingMedia = picked);
    } catch (e) {
      _toast('Picker error');
    }
  }

  void _clearMedia() {
    setState(() => _pendingMedia = null);
  }

  // ═══════════════════════════════════════════════════════════════
  // CLOUDINARY
  // ═══════════════════════════════════════════════════════════════
  Future<String> _uploadToCloudinary(File file) async {
    final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudName/image/upload');
    final req = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = _uploadPreset
      ..fields['folder'] = 'aura_chat/bots'
      ..files.add(await http.MultipartFile.fromPath('file', file.path));
    final streamed = await req.send();
    if (streamed.statusCode != 200) {
      throw Exception('Cloudinary ${streamed.statusCode}');
    }
    final body = await streamed.stream.bytesToString();
    final data = jsonDecode(body);
    final url = data['secure_url'] as String?;
    if (url == null) throw Exception('No URL returned');
    return url;
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.6, -0.5),
            radius: 1.4,
            colors: [Color(0x148B5CF6), Colors.transparent],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildMessages()),
              if (_pendingMedia != null) _buildMediaPreview(),
              _buildCommandsBar(),
              _buildInputArea(),
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F).withOpacity(0.9),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
              ),
            ),
            child: const Icon(Icons.smart_toy,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'BotCreator',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF8B5CF6),
                            Color(0xFF06B6D4),
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
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  _statusText,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white54),
            onPressed: () => _quickCmd('/help'),
          ),
        ],
      ),
    );
  }

  String get _statusText {
    if (_chatState == 'idle') return 'Your bot factory';
    if (_chatState.startsWith('awaiting_edit_')) {
      final u = _tempBot['username'] as String?;
      return u != null ? 'Editing @$u' : 'Your bot factory';
    }
    if (_chatState.startsWith('awaiting_bot_')) return 'Creating a bot...';
    return 'Your bot factory';
  }

  Widget _buildMessages() {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      itemCount: _messages.length + (_botTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (_botTyping && index == _messages.length) {
          return _buildTypingBubble();
        }
        final m = _messages[index];
        return _buildBubble(m);
      },
    );
  }

  Widget _buildTypingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return Padding(
              padding: EdgeInsets.only(right: i < 2 ? 4 : 0),
              child: _TypingDot(delay: i * 150),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildBubble(_BCMessage m) {
    return Align(
      alignment: m.isOut ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          gradient: m.isOut
              ? const LinearGradient(
                  colors: [
                    Color(0x4D8B5CF6),
                    Color(0x3306B6D4),
                  ],
                )
              : null,
          color: m.isOut ? null : Colors.white.withOpacity(0.04),
          border: Border.all(
            color: m.isOut
                ? const Color(0xFF8B5CF6).withOpacity(0.2)
                : Colors.white.withOpacity(0.05),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.fromLTRB(13, 10, 13, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.imageUrl != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: m.imageUrl!.startsWith('http')
                      ? Image.network(
                          m.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(
                            height: 120,
                            child: Center(
                              child: Icon(Icons.broken_image,
                                  color: Colors.white30),
                            ),
                          ),
                        )
                      : Image.file(
                          File(m.imageUrl!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(
                            height: 120,
                            child: Center(
                              child: Icon(Icons.broken_image,
                                  color: Colors.white30),
                            ),
                          ),
                        ),
                ),
              ),
            if ((m.html ?? m.text ?? '').isNotEmpty)
              _RichBubble(
                content: m.html ?? m.text ?? '',
                isOut: m.isOut,
              ),
            if (m.buttons != null && m.buttons!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: m.buttons!.map((b) {
                    return GestureDetector(
                      onTap: b.onTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          gradient: b.primary
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFF8B5CF6),
                                    Color(0xFF06B6D4),
                                  ],
                                )
                              : null,
                          color: b.primary
                              ? null
                              : b.danger
                                  ? const Color(0xFFEF4444)
                                      .withOpacity(0.15)
                                  : const Color(0xFF8B5CF6)
                                      .withOpacity(0.15),
                          border: Border.all(
                            color: b.primary
                                ? Colors.transparent
                                : b.danger
                                    ? const Color(0xFFEF4444)
                                        .withOpacity(0.3)
                                    : const Color(0xFF8B5CF6)
                                        .withOpacity(0.3),
                          ),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          b.label,
                          style: TextStyle(
                            color: b.danger
                                ? const Color(0xFFFCA5A5)
                                : Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaPreview() {
    final f = _pendingMedia!;
    final size = File(f.path).lengthSync();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF8B5CF6).withOpacity(0.08),
          border: Border.all(
            color: const Color(0xFF8B5CF6).withOpacity(0.2),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(f.path),
                width: 42,
                height: 42,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
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
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _formatSize(size),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white54, size: 18),
              onPressed: _clearMedia,
            ),
          ],
        ),
      ),
    );
  }

  String _formatSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1048576).toStringAsFixed(1)} MB';
  }

  Widget _buildCommandsBar() {
    const commands = [
      '/newbot',
      '/mybots',
      '/token',
      '/setname',
      '/setdescription',
      '/setuserpic',
      '/setusername',
      '/revoke',
      '/deletebot',
      '/docs',
      '/package',
      '/cancel',
    ];
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F).withOpacity(0.9),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: commands.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final c = commands[i];
          return GestureDetector(
            onTap: () => _quickCmd(c),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withOpacity(0.08),
                border: Border.all(
                  color: const Color(0xFF8B5CF6).withOpacity(0.2),
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  c,
                  style: const TextStyle(
                    color: Color(0xFFC4B5FD),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F).withOpacity(0.95),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.image,
                  color: Color(0xFF8B5CF6), size: 16),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(18),
              ),
              child: TextField(
                controller: _inputCtrl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendUserMsg(),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Type a command...',
                  hintStyle: TextStyle(
                    color: Colors.white.withOpacity(0.25),
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _sendUserMsg,
            child: Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
                ),
              ),
              child: const Icon(Icons.send, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// SUPPORTING TYPES
// ═══════════════════════════════════════════════════════════════
class _BCMessage {
  final bool isOut;
  final String? html;
  final String? text;
  final String? imageUrl;
  final List<_BCButton>? buttons;

  _BCMessage({
    required this.isOut,
    this.html,
    this.text,
    this.imageUrl,
    this.buttons,
  });
}

class _BCButton {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool danger;

  _BCButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.danger = false,
  });
}

class _TypingDot extends StatefulWidget {
  final int delay;
  const _TypingDot({required this.delay});

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = (_controller.value * 1000 + widget.delay) % 1000 / 1000;
        final scale = 0.5 + 0.5 * (1 - (t - 0.4).abs() * 2).clamp(0, 1);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF8B5CF6),
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

/// Tiny HTML-ish renderer matching the web's `linkify()` output.
/// Supports: <strong>, <em>, <code>, <pre>, <a href>, plain text,
/// and escapes bare text.
class _RichBubble extends StatelessWidget {
  final String content;
  final bool isOut;

  const _RichBubble({required this.content, required this.isOut});

  @override
  Widget build(BuildContext context) {
    final spans = _parse(content);
    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: Colors.white,
          fontSize: 13.5,
          height: 1.5,
        ),
        children: spans,
      ),
    );
  }

  List<TextSpan> _parse(String html) {
    final spans = <TextSpan>[];
    final pattern = RegExp(
      r'<strong>(.*?)</strong>|<em>(.*?)</em>|<code>(.*?)</code>|<pre>(.*?)</pre>|<a href="([^"]*)">(.*?)</a>|([^<]+)',
      dotAll: true,
    );

    for (final m in pattern.allMatches(html)) {
      if (m.group(1) != null) {
        spans.add(TextSpan(
          text: m.group(1),
          style: const TextStyle(
              fontWeight: FontWeight.w700, color: Colors.white),
        ));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(
          text: m.group(2),
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 12.5,
          ),
        ));
      } else if (m.group(3) != null) {
        spans.add(TextSpan(
          text: m.group(3),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: isOut ? Colors.white : const Color(0xFFC4B5FD),
            backgroundColor: isOut
                ? Colors.black.withOpacity(0.25)
                : const Color(0xFF8B5CF6).withOpacity(0.15),
          ),
        ));
      } else if (m.group(4) != null) {
        spans.add(TextSpan(
          text: m.group(4),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 11.5,
            color: Color(0xFFD8B4FE),
            backgroundColor: Color(0x59000000),
          ),
        ));
      } else if (m.group(5) != null) {
        spans.add(TextSpan(
          text: m.group(6),
          style: TextStyle(
            color: isOut ? Colors.white : const Color(0xFF8B5CF6),
            decoration: TextDecoration.underline,
          ),
        ));
      } else if (m.group(7) != null) {
        spans.add(TextSpan(text: m.group(7)));
      }
    }
    return spans;
  }
}
