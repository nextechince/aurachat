import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:just_audio/just_audio.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../calls/call_screen.dart';
import '../../providers/auth_provider.dart' show AuraAuthProvider;
import '../../services/cloudinary_service.dart';
import '../../services/call_service.dart';
import '../../services/invitation_service.dart';
import '../../utils/verified_badge.dart';

class ChatScreen extends StatefulWidget {
  final String? chatId;
  final String? chatName;
  final String? chatAvatar;
  final bool isGroup;
  final bool isChannel;

  const ChatScreen({
    super.key,
    this.chatId,
    this.chatName,
    this.chatAvatar,
    this.isGroup = false,
    this.isChannel = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final _messageController = TextEditingController();
  final _editController = TextEditingController();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _gifSearchController = TextEditingController();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final Record _audioRecorder = Record();
  final ImagePicker _picker = ImagePicker();

  String? _chatId;
  String? _chatName;
  String? _chatAvatar;
  bool _isGroup = false;
  bool _isChannel = false;
  String? _currentUserId;
  String? _otherUserId;
  String? _otherUserNickname;
  bool _otherUserOnline = false;
  DateTime? _otherUserLastSeen;
  bool _otherUserTyping = false;
  Timer? _otherTypingHideTimer;

  List<Map<String, dynamic>> _messages = [];
  StreamSubscription? _messageSubscription;
  StreamSubscription? _chatSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _statusSubscription;
  StreamSubscription<Position>? _liveSub;
  Timer? _liveTimer;
  final _blockUnsub = <StreamSubscription>[];
  bool _isLoading = true;
  bool _initialized = false;
  DateTime? _clearedAt;

  final Map<String, Map<String, dynamic>> _userCache = {};
  final Set<String> _pendingUserFetches = {};

  bool _isBlocked = false;
  bool _iBlockedThem = false;
  bool _theyBlockedMe = false;

  String? _replyingTo;
  String? _replyingToContent;
  String? _replyingToSender;
  String? _editingMessageId;
  String? _selectedMessageId;
  bool _multiSelectMode = false;
  final Set<String> _selectedMessageIds = {};

  bool _showEmojiPicker = false;
  String _pickerTab = 'emoji';
  String _lastPanelMode = 'emoji';

  bool _showScrollDown = false;

  static const Map<String, Map<String, dynamic>> _emojiCategories = {
    'smileys': {
      'icon': '😀',
      'emojis': ['😀','😃','😄','😁','😆','😅','🤣','😂','🙂','🙃','😉','😊','😇','🥰','😍','🤩','😘','😗','😚','😙','😋','😛','😜','🤪','😝','🤑','🤗','🤭','🤫','🤔','🤐','🤨','😐','😑','😶','😏','😒','🙄','😬','🤥','😌','😔','😪','🤤','😴','😷','🤒','🤕','🤢','🤮','🤧','🥵','🥶','😵','🤯','🤠','🥳','😎','🤓','🧐']
    },
    'love': {
      'icon': '❤️',
      'emojis': ['❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','❣️','💕','💞','💓','💗','💖','💘','💝','💟','♥️','💋','🌹','🌷','🌺','🌸','💐','💌']
    },
    'gestures': {
      'icon': '👍',
      'emojis': ['👍','👎','👌','🤌','🤏','✌️','🤞','🤟','🤘','🤙','👈','👉','👆','👇','☝️','👋','🤚','🖐️','✋','🖖','👏','🙌','🤲','🤝','🙏','✍️','💪','👂','👃','👀','👁️','👅','👄']
    },
    'animals': {
      'icon': '🐶',
      'emojis': ['🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷','🐸','🐵','🐔','🐧','🐦','🐤','🦆','🦅','🦉','🦇','🐺','🐴','🦄','🐝','🐛','🦋','🐌','🐞','🐜','🐢','🐍','🐙','🐬','🐳','🦈','🐊','🐘']
    },
    'food': {
      'icon': '🍔',
      'emojis': ['🍏','🍎','🍐','🍊','🍋','🍌','🍉','🍇','🍓','🫐','🍈','🍒','🍑','🥭','🍍','🥥','🥝','🍅','🍆','🥑','🥦','🥬','🥒','🌶️','🌽','🥕','🥔','🍞','🥖','🧀','🥚','🍳','🥓','🥩','🍗','🍔','🍟','🍕','🌮','🍝','🍜','🍣','🍱','🍚','🍙','🍢','🍡','🍦','🍰','🎂']
    },
    'activities': {
      'icon': '⚽',
      'emojis': ['⚽','🏀','🏈','⚾','🥎','🎾','🏐','🏉','🎱','🏓','🏸','🏒','🥅','⛳','🏹','🎣','🥊','🥋','🛹','🛼','🛷','⛸️','🎿','⛷️','🏂','🏋️','🤼','🤸','⛹️','🤺','🤾','🏌️','🏇','🧘','🏄','🏊','🚣','🧗','🚵','🚴','🏆','🥇','🥈','🥉','🏅']
    },
    'travel': {
      'icon': '✈️',
      'emojis': ['🚗','🚕','🚙','🚌','🏎️','🚓','🚑','🚒','🚐','🚚','🚛','🚜','🛴','🚲','🛵','🏍️','🚨','🚔','🚃','🚋','🚞','🚝','🚄','🚅','🚈','🚂','🚆','🚇','🚊','🚉','✈️','🛫','🛬','🚀','🛸','🚁','⛵','🚤','🛳️','⛴️','🚢','⚓']
    },
    'objects': {
      'icon': '💡',
      'emojis': ['⌚','📱','💻','⌨️','🖥️','🖨️','🖱️','🕹️','💽','💾','💿','📀','📼','📷','📸','📹','🎥','📽️','📞','☎️','📟','📠','📺','📻','🎙️','🧭','⏱️','⏰','🕰️','⌛','⏳','📡','🔋','🔌','💡','🔦','🕯️','💸','💵','💰','💳','💎','🔧','🔨','⚙️']
    },
    'symbols': {
      'icon': '💯',
      'emojis': ['✅','❌','❎','✔️','☑️','🔘','🔴','🟠','🟡','🟢','🔵','🟣','⚫','⚪','🟤','🔺','🔻','🔸','🔹','🔶','🔷','🔳','🔲','▪️','▫️','◾','◽','◼️','◻️','🔈','🔇','🔉','🔊','🔔','🔕','📣','📢','💬','💭','💯','🔢','🔤']
    }
  };
  String _currentEmojiCategory = 'smileys';

  List<Map<String, dynamic>> _myStickers = [];
  List<Map<String, dynamic>> _favoriteStickers = [];
  List<Map<String, dynamic>> _stickerPacks = [];
  String _currentStickerPackId = 'fav';
  bool _loadingStickers = false;

  static const String _giphyApiKey = '7tXB3cisPGymcszQX85JFOY6kp3Gz47T';
  List<Map<String, dynamic>> _gifs = [];
  bool _loadingGifs = false;
  bool _gifsLoaded = false;

  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  String? _recordingPath;
  final List<double> _recordingWave = [];

  String? _currentlyPlayingAudioId;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;

  final Map<String, VideoPlayerController> _videoControllers = {};

  int _selfDestructSeconds = 0;
  Map<String, dynamic>? _chatSettings;
  String? _myRole = 'member';
  bool _canSend = true;
  bool _canSendFiles = true;
  bool _isAnnouncementsOnly = false;
  String? _creatorEmail;

  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  int _currentSearchIndex = -1;

  List<Map<String, dynamic>> _pinnedMessages = [];
  String? _pinnedMessageId;

  Timer? _onlineHeartbeat;
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAudioPlayer();
    _messageController.addListener(_onTextChanged);
    _gifSearchController.addListener(() => setState(() {}));
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    final cur = _scrollController.position.pixels;
    final show = (max - cur) > 200;
    if (show != _showScrollDown) setState(() => _showScrollDown = show);
  }

  void _onTextChanged() {
    setState(() {});
    _startTyping();
  }

  void _initAudioPlayer() {
    _audioPlayer.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _audioDuration = d);
    });
    _audioPlayer.positionStream.listen((p) {
      if (mounted) setState(() => _audioPosition = p);
    });
    _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _currentlyPlayingAudioId = null;
          _audioPosition = Duration.zero;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      _chatId = args['chatId'] as String?;
      _chatName = args['chatName'] as String?;
      _chatAvatar = args['chatAvatar'] as String?;
      _isGroup = args['isGroup'] as bool? ?? false;
      _isChannel = args['isChannel'] as bool? ?? false;
    }

    final auth = Provider.of<AuraAuthProvider>(context, listen: false);
    _currentUserId = auth.user?.uid ?? auth.mockUserId;

    if (_chatId == null) {
      setState(() => _isLoading = false);
      return;
    }

    _loadChatInfoAndStart();
    _loadStickers();
    _setOnlineStatus();
  }

  Future<void> _loadChatInfoAndStart() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .get();
      if (doc.exists) {
        _applyChatInfo(doc.data() as Map<String, dynamic>);
      }
    } catch (_) {}

    _subscribeToChat();
    _loadMessages();
    _subscribeToMessages();
    _loadPinnedMessages();

    if (!_isGroup && !_isChannel) {
      _initDirectFeatures();
    }
  }

  void _applyChatInfo(Map<String, dynamic> data) {
    final clearedMap = data['cleared_at'] as Map<String, dynamic>?;
    final clearedTs = _currentUserId != null
        ? (clearedMap?[_currentUserId] as Timestamp?)
        : null;
    _clearedAt = clearedTs?.toDate();

    _creatorEmail = data['created_by_email'] as String?;
    _chatSettings = data['settings'] as Map<String, dynamic>?;
    _myRole =
        (data['participants_data']?[_currentUserId]?['role'] ?? 'member')
            as String;

    final isAdmin = _myRole == 'owner' || _myRole == 'admin';
    _canSend = !(_chatSettings?['chat_disabled'] == true && !isAdmin);
    _canSendFiles =
        !(_chatSettings?['file_sharing_disabled'] == true && !isAdmin);
    _isAnnouncementsOnly =
        _chatSettings?['announcements_only'] == true && !isAdmin;
    _selfDestructSeconds = (data['self_destruct_seconds'] ?? 0) as int;
    _pinnedMessageId = data['pinned_message_id'] as String?;

    if (!_isGroup && !_isChannel) {
      final parts = List<String>.from(data['participants'] ?? []);
      _otherUserId = parts.firstWhere(
        (id) => id != _currentUserId,
        orElse: () => '',
      );
      if (_otherUserId!.isEmpty) _otherUserId = null;
    }
  }

  void _subscribeToChat() {
    _chatSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists || !mounted) return;
      final data = doc.data() as Map<String, dynamic>;
      setState(() => _applyChatInfo(data));
      _loadPinnedMessages();
    });
  }

  Future<void> _initDirectFeatures() async {
    if (_otherUserId == null) return;
    await _checkBlockStatus();
    _subscribeBlockStatus();
    _subscribeOtherUserStatus();
    _subscribeTyping();
    _loadNickname();
  }

  Future<void> _loadNickname() async {
    if (_otherUserId == null || _currentUserId == null) return;
    try {
      final d = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('nicknames')
          .doc(_otherUserId)
          .get();
      if (d.exists && mounted) {
        setState(() => _otherUserNickname = d.data()?['nickname']);
      }
    } catch (_) {}
  }

  Future<void> _checkBlockStatus() async {
    if (_otherUserId == null) return;
    try {
      final myDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .get();
      final myBlocked = List<String>.from(myDoc.data()?['blocked_users'] ?? []);
      final theirDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_otherUserId)
          .get();
      final theirBlocked =
          List<String>.from(theirDoc.data()?['blocked_users'] ?? []);
      if (!mounted) return;
      setState(() {
        _iBlockedThem = myBlocked.contains(_otherUserId);
        _theyBlockedMe = theirBlocked.contains(_currentUserId);
        _isBlocked = _iBlockedThem || _theyBlockedMe;
      });
    } catch (_) {}
  }

  void _subscribeBlockStatus() {
    if (_otherUserId == null) return;
    _blockUnsub.add(
      FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .snapshots()
          .listen((snap) async {
        if (!mounted) return;
        final blocked =
            List<String>.from(snap.data()?['blocked_users'] ?? []);
        final theirDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_otherUserId)
            .get();
        final theirBlocked =
            List<String>.from(theirDoc.data()?['blocked_users'] ?? []);
        if (!mounted) return;
        setState(() {
          _iBlockedThem = blocked.contains(_otherUserId);
          _theyBlockedMe = theirBlocked.contains(_currentUserId);
          _isBlocked = _iBlockedThem || _theyBlockedMe;
        });
      }),
    );
  }

  void _subscribeOtherUserStatus() {
    if (_otherUserId == null) return;
    _statusSubscription?.cancel();
    _statusSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(_otherUserId)
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists) return;
      final d = doc.data() as Map<String, dynamic>;
      final online = d['is_online'] == true;
      final lastSeen = d['last_seen'] as Timestamp?;
      if (!mounted) return;
      setState(() {
        _otherUserOnline = online;
        _otherUserLastSeen = lastSeen?.toDate();
      });
    });
  }

  void _subscribeTyping() {
    if (_otherUserId == null) return;
    _typingSubscription?.cancel();
    _typingSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('typing')
        .doc(_otherUserId)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      final isTyping =
          doc.exists && (doc.data()?['is_typing'] as bool? ?? false);
      setState(() => _otherUserTyping = isTyping);
      _otherTypingHideTimer?.cancel();
      if (isTyping) {
        _otherTypingHideTimer = Timer(const Duration(seconds: 13), () {
          if (mounted) setState(() => _otherUserTyping = false);
        });
      }
    });
  }

  void _startTyping() {
    if (_chatId == null || _currentUserId == null || _isBlocked) return;
    if (_messageController.text.trim().isEmpty) return;
    FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('typing')
        .doc(_currentUserId)
        .set({
      'timestamp': FieldValue.serverTimestamp(),
      'is_typing': true,
    }, SetOptions(merge: true));
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), _stopTyping);
  }

  void _stopTyping() {
    if (_chatId == null || _currentUserId == null) return;
    _typingTimer?.cancel();
    FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('typing')
        .doc(_currentUserId)
        .delete()
        .catchError((_) {});
  }

  Future<void> _setOnlineStatus() async {
    if (_currentUserId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .update({
        'is_online': true,
        'last_seen': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    _onlineHeartbeat?.cancel();
    _onlineHeartbeat = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .update({'last_seen': FieldValue.serverTimestamp()});
      } catch (_) {}
    });
  }

  Future<void> _setOfflineStatus() async {
    _onlineHeartbeat?.cancel();
    if (_currentUserId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .update({
        'is_online': false,
        'last_seen': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setOnlineStatus();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _setOfflineStatus();
    }
  }

  Future<void> _loadMessages() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .orderBy('created_at', descending: true)
          .limit(100)
          .get();

      final loaded = <Map<String, dynamic>>[];
      final ids = <String>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        if (d['deleted_for_everyone'] == true) continue;
        final df = List<String>.from(d['deleted_for'] ?? []);
        if (_currentUserId != null && df.contains(_currentUserId)) continue;
        final destruct = d['self_destruct_seconds'] as int?;
        if (destruct != null && destruct > 0 && d['created_at'] != null) {
          final ct = (d['created_at'] as Timestamp).toDate();
          if (DateTime.now().difference(ct).inSeconds > destruct) continue;
        }
        if (_clearedAt != null && d['created_at'] != null) {
          final ct = (d['created_at'] as Timestamp).toDate();
          if (!ct.isAfter(_clearedAt!)) continue;
        }
        if (d['sender_id'] != null) ids.add(d['sender_id'] as String);
        loaded.add({'id': doc.id, ...d});
      }
      await _fetchMissingUsers(ids);
      if (!mounted) return;
      setState(() {
        _messages = loaded;
        _isLoading = false;
      });
      _scrollToBottom(force: true);
      _markAsRead();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToMessages() {
    _messageSubscription?.cancel();
    _messageSubscription = FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .orderBy('created_at', descending: true)
        .limit(100)
        .snapshots()
        .listen((snap) async {
      final loaded = <Map<String, dynamic>>[];
      final ids = <String>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        if (d['deleted_for_everyone'] == true) continue;
        final df = List<String>.from(d['deleted_for'] ?? []);
        if (_currentUserId != null && df.contains(_currentUserId)) continue;
        final destruct = d['self_destruct_seconds'] as int?;
        if (destruct != null && destruct > 0 && d['created_at'] != null) {
          final ct = (d['created_at'] as Timestamp).toDate();
          if (DateTime.now().difference(ct).inSeconds > destruct) continue;
        }
        if (_clearedAt != null && d['created_at'] != null) {
          final ct = (d['created_at'] as Timestamp).toDate();
          if (!ct.isAfter(_clearedAt!)) continue;
        }
        if (d['sender_id'] != null) ids.add(d['sender_id'] as String);
        loaded.add({'id': doc.id, ...d});
      }
      await _fetchMissingUsers(ids);
      if (!mounted) return;
      setState(() {
        _messages = loaded;
        _isLoading = false;
      });
      _scrollToBottom();
      _markAsRead();
    });
  }

  Future<void> _fetchMissingUsers(Set<String> ids) async {
    final missing = ids
        .where((id) =>
            !_userCache.containsKey(id) && !_pendingUserFetches.contains(id))
        .toList();
    if (missing.isEmpty) return;
    _pendingUserFetches.addAll(missing);
    final docs = await Future.wait(missing
        .map((id) =>
            FirebaseFirestore.instance.collection('users').doc(id).get()));
    _pendingUserFetches.removeAll(missing);
    for (final d in docs) {
      if (d.exists) {
        final u = d.data()!;
        _userCache[d.id] = {
          'username': u['username'] ?? u['display_name'] ?? 'Unknown',
          'display_name': u['display_name'] ?? u['username'] ?? 'Unknown',
          'avatar_url': u['avatar_url'],
          'email': u['email'],
          'is_verified': _isVerifiedEmail(u['email']),
        };
      }
    }
  }

  bool _isVerifiedEmail(dynamic email) {
    if (email == null) return false;
    final e = email.toString().toLowerCase().trim();
    if (e.endsWith('@bot.aurachat.app')) return false;
    return e.endsWith('@gmail.com') || e.endsWith('@aurachat.app');
  }

  Future<void> _markAsRead() async {
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .update({
        'unread_counts.$_currentUserId': 0,
        'last_read_at.$_currentUserId': FieldValue.serverTimestamp(),
      });
      final unread = await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .where('is_read', isEqualTo: false)
          .limit(500)
          .get();
      if (unread.docs.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      var n = 0;
      for (final doc in unread.docs) {
        if (doc.data()['sender_id'] != _currentUserId) {
          batch.update(doc.reference, {'is_read': true});
          n++;
        }
      }
      if (n > 0) await batch.commit();
    } catch (_) {}
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      final cur = _scrollController.position.pixels;
      if (force || (max - cur) < 300) {
        _scrollController.jumpTo(max);
      }
    });
  }

  Future<void> _loadPinnedMessages() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('pinned_messages')
          .orderBy('pinned_at', descending: true)
          .limit(3)
          .get();
      final pinned = snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .where((p) {
        final hidden = List<String>.from(p['hidden_for'] ?? []);
        return !hidden.contains(_currentUserId);
      }).toList();
      if (!mounted) return;
      setState(() => _pinnedMessages = pinned);
    } catch (_) {}
  }

  Future<void> _sendTextMessage() async {
    if (_isBlocked || !_canSend || _isAnnouncementsOnly) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    setState(() {});
    _stopTyping();
    await _sendMessage(type: 'text', content: text);
    if (_EffectBurst.isTrigger(text)) {
      if (mounted) _EffectBurst.fire(context, text);
    }
  }

  Future<void> _sendMessage({
    required String type,
    required String content,
    String? mediaUrl,
    String? fileName,
    String? fileSize,
    int? duration,
    Map<String, dynamic>? sticker,
    Map<String, dynamic>? location,
    Map<String, dynamic>? contact,
    Map<String, dynamic>? linkPreview,
    List<Map<String, dynamic>>? images,
    String? gifUrl,
    bool viewOnce = false,
  }) async {
    if (_currentUserId == null || _chatId == null) return;

    final messageId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();

    if (type == 'text' && linkPreview == null) {
      final url = _detectFirstUrl(content);
      if (url != null &&
          !_InviteLinkDetector.isInvite(url) &&
          !_AuraShortLink.isShortLink(url)) {
        linkPreview = await _fetchLinkPreview(url);
      }
    }

    final serverMessage = <String, dynamic>{
      'id': messageId,
      'chat_id': _chatId,
      'sender_id': _currentUserId,
      'text': content,
      'content': content,
      'type': type,
      'media_type': type,
      'media_url': mediaUrl,
      'file_name': fileName,
      'file_size': fileSize,
      'duration': duration,
      'sticker': sticker,
      'images': images,
      'gif_url': gifUrl,
      'location_lat': location?['lat'],
      'location_lng': location?['lng'],
      'location_label': location?['label'],
      'location_live': location?['live'] ?? false,
      'contact': contact,
      'link_preview': linkPreview,
      'view_once': viewOnce,
      'reply_to': _replyingTo,
      'reply_to_content': _replyingToContent,
      'reply_to_sender': _replyingToSender,
      'self_destruct_seconds':
          _selfDestructSeconds > 0 ? _selfDestructSeconds : null,
      'created_at': FieldValue.serverTimestamp(),
      'is_read': false,
      'is_edited': false,
      'deleted_for_everyone': false,
      'deleted_for': [],
      'reactions': {},
    };

    setState(() {
      _messages.insert(
        0,
        {...serverMessage, 'created_at': now, 'created_at_local': now},
      );
      _replyingTo = null;
      _replyingToContent = null;
      _replyingToSender = null;
    });
    _scrollToBottom(force: true);

    try {
      final ref = FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .doc(messageId);
      await ref.set(serverMessage);

      final upd = <String, dynamic>{
        'last_message': _lastMessageLabel(type, content),
        'last_message_at': FieldValue.serverTimestamp(),
      };
      if (_otherUserId != null) {
        upd['unread_counts.$_otherUserId'] = FieldValue.increment(1);
      }
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .update(upd);

      if (_selfDestructSeconds > 0) {
        Timer(Duration(seconds: _selfDestructSeconds), () {
          FirebaseFirestore.instance
              .collection('chats')
              .doc(_chatId)
              .collection('messages')
              .doc(messageId)
              .update({
            'deleted_for_everyone': true,
            'text': 'This message was deleted',
            'content': 'This message was deleted',
            'media_url': null,
          }).catchError((_) {});
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _messages.removeWhere((m) => m['id'] == messageId));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  String _lastMessageLabel(String type, String content) {
    switch (type) {
      case 'image':
        return '📷 Photo';
      case 'video':
        return '🎥 Video';
      case 'audio':
        return '🎤 Voice message';
      case 'file':
        return '📎 File';
      case 'sticker':
        return '🎨 Sticker';
      case 'gif':
        return '🎞️ GIF';
      case 'location':
        return '📍 Location';
      case 'contact':
        return '👤 Contact';
      default:
        return content;
    }
  }

  String? _detectFirstUrl(String text) {
    final m = RegExp(r'(https?://[^\s]+)').firstMatch(text);
    return m?.group(1);
  }

  Future<Map<String, dynamic>?> _fetchLinkPreview(String url) async {
    try {
      final r = await http.get(Uri.parse(
          'https://api.microlink.io/?url=${Uri.encodeComponent(url)}'));
      if (r.statusCode != 200) return null;
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      if (body['status'] != 'success') return null;
      final d = body['data'] as Map<String, dynamic>;
      return {
        'title': d['title'] ?? '',
        'description': d['description'] ?? '',
        'image': (d['image']?['url']) ?? '',
        'domain': d['publisher'] ??
            (d['url'] != null ? Uri.parse(d['url'] as String).host : ''),
        'url': d['url'] ?? url,
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadStickers() async {
    if (_currentUserId == null || _loadingStickers) return;
    setState(() => _loadingStickers = true);
    try {
      final f = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('stickers')
          .orderBy('created_at', descending: true)
          .limit(200)
          .get();
      final packs = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('sticker_packs')
          .orderBy('created_at', descending: true)
          .get();
      if (!mounted) return;
      setState(() {
        _myStickers = f.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        _stickerPacks =
            packs.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        _favoriteStickers =
            _myStickers.where((s) => s['favorite'] == true).toList();
        _loadingStickers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingStickers = false);
    }
  }

  Future<void> _createStickerFromGallery({bool video = false}) async {
    final XFile? picked = video
        ? await _picker.pickVideo(source: ImageSource.gallery)
        : await _picker.pickImage(
            source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Creating sticker...')));
    try {
      final file = File(picked.path);
      final url = video
          ? await CloudinaryService.uploadVideo(
              file, 'aurachat/stickers/$_currentUserId')
          : await CloudinaryService.uploadImage(
              file, 'aurachat/stickers/$_currentUserId');
      if (url == null) throw Exception('Upload failed');
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('stickers')
          .doc();
      await ref.set({
        'id': ref.id,
        'url': url,
        'sticker_type': video ? 'video' : 'static',
        'favorite': false,
        'created_at': FieldValue.serverTimestamp(),
      });
      await _loadStickers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sticker created')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _deleteSticker(String id) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .collection('stickers')
        .doc(id)
        .delete();
    await _loadStickers();
  }

  Future<void> _toggleFavoriteSticker(Map<String, dynamic> s) async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .collection('stickers')
        .doc(s['id']);
    await ref.update({'favorite': !(s['favorite'] == true)});
    await _loadStickers();
  }

  Future<void> _sendSticker(Map<String, dynamic> s) async {
    if (_isBlocked || !_canSend || _isAnnouncementsOnly) return;
    setState(() => _showEmojiPicker = false);
    await _sendMessage(
      type: 'sticker',
      content: '🎨 Sticker',
      sticker: {
        'url': s['url'],
        'sticker_type': s['sticker_type'] ?? 'static',
      },
      mediaUrl: s['url'],
    );
  }

  Future<void> _sendGif(String url) async {
    setState(() => _showEmojiPicker = false);
    await _sendMessage(
        type: 'gif', content: '🎞️ GIF', gifUrl: url, mediaUrl: url);
  }

  Future<void> _loadGifs({String? q}) async {
    if (_loadingGifs) return;
    setState(() => _loadingGifs = true);
    try {
      final query = (q ?? '').trim();
      final endpoint = query.isEmpty
          ? 'https://api.giphy.com/v1/gifs/trending?api_key=$_giphyApiKey&limit=24&rating=g'
          : 'https://api.giphy.com/v1/gifs/search?api_key=$_giphyApiKey&q=${Uri.encodeComponent(query)}&limit=24&rating=g';
      final res = await http.get(Uri.parse(endpoint));
      if (res.statusCode != 200) throw Exception('Giphy ${res.statusCode}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final data = (body['data'] as List).cast<Map<String, dynamic>>();
      final gifs = data.map((g) {
        final images = g['images'] as Map<String, dynamic>?;
        final full = images?['downsized_medium']?['url'] ??
            images?['fixed_height']?['url'] ??
            images?['original']?['url'];
        final preview = images?['fixed_width']?['url'] ??
            images?['fixed_width_small']?['url'] ??
            full;
        return {'full': full, 'preview': preview};
      }).where((g) => g['full'] != null).toList();
      if (!mounted) return;
      setState(() {
        _gifs = gifs;
        _loadingGifs = false;
        _gifsLoaded = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _gifs = [];
          _loadingGifs = false;
          _gifsLoaded = true;
        });
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      final has = await _audioRecorder.hasPermission();
      if (!has) return;
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(path: path, encoder: AudioEncoder.aacLc);
      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _recordingPath = path;
        _recordingSeconds = 0;
        _recordingWave.clear();
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) return;
        setState(() {
          _recordingWave.add(0.3 + math.Random().nextDouble() * 0.7);
          if (_recordingWave.length > 40) _recordingWave.removeAt(0);
        });
      });
      Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || !_isRecording) {
          t.cancel();
          return;
        }
        setState(() => _recordingSeconds++);
      });
    } catch (_) {}
  }

  Future<void> _stopRecordingAndSend() async {
    try {
      _recordingTimer?.cancel();
      final path = await _audioRecorder.stop();
      if (!mounted) return;
      setState(() => _isRecording = false);
      if (path == null) return;
      final file = File(path);
      final size = await file.length();
      await _uploadAndSendMedia(
        file: file,
        type: 'audio',
        fileName: 'Voice message',
        fileSize: _formatFileSize(size),
        duration: _recordingSeconds,
      );
    } catch (_) {}
  }

  Future<void> _cancelRecording() async {
    try {
      _recordingTimer?.cancel();
      await _audioRecorder.stop();
      if (_recordingPath != null) {
        final f = File(_recordingPath!);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
    if (mounted) setState(() => _isRecording = false);
  }

  Future<void> _pickImage() async {
    if (!_canSendFiles) return;
    final x = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 90);
    if (x == null) return;
    await _openMediaEditor(File(x.path), isVideo: false);
  }

  Future<void> _takePhoto() async {
    if (!_canSendFiles) return;
    final x = await _picker.pickImage(source: ImageSource.camera);
    if (x == null) return;
    await _openMediaEditor(File(x.path), isVideo: false);
  }

  Future<void> _pickVideo() async {
    if (!_canSendFiles) return;
    final x = await _picker.pickVideo(source: ImageSource.gallery);
    if (x == null) return;
    await _openMediaEditor(File(x.path), isVideo: true);
  }

  Future<void> _recordVideo() async {
    if (!_canSendFiles) return;
    final x = await _picker.pickVideo(source: ImageSource.camera);
    if (x == null) return;
    await _openMediaEditor(File(x.path), isVideo: true);
  }

  Future<void> _pickFile() async {
    if (!_canSendFiles) return;
    final res = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    if (f.path == null) return;
    await _uploadAndSendMedia(
      file: File(f.path!),
      type: 'file',
      fileName: f.name,
      fileSize: _formatFileSize(f.size),
    );
  }

  Future<void> _openMediaEditor(File file, {required bool isVideo}) async {
    final result = await Navigator.push<_EditorResult>(
      context,
      MaterialPageRoute(
        builder: (_) => _MediaEditorScreen(
          initialFile: file,
          isVideo: isVideo,
        ),
      ),
    );
    if (result == null) return;
    final asSticker = await _askSendAsStickerOrPhoto();
    if (asSticker == null) return;
    if (asSticker) {
      try {
        final url = isVideo
            ? await CloudinaryService.uploadVideo(
                result.file, 'aurachat/stickers/$_currentUserId')
            : await CloudinaryService.uploadImage(
                result.file, 'aurachat/stickers/$_currentUserId');
        if (url == null) throw Exception('Upload failed');
        final ref = FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUserId)
            .collection('stickers')
            .doc();
        await ref.set({
          'id': ref.id,
          'url': url,
          'sticker_type': isVideo ? 'video' : 'static',
          'favorite': false,
          'created_at': FieldValue.serverTimestamp(),
        });
        await _loadStickers();
        await _sendSticker(
            {'url': url, 'sticker_type': isVideo ? 'video' : 'static'});
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } else {
      await _uploadAndSendMedia(
        file: result.file,
        type: isVideo ? 'video' : 'image',
        fileName: isVideo ? 'Video' : 'Photo',
      );
    }
  }

  Future<bool?> _askSendAsStickerOrPhoto() {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _glassSheet(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Send as',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _bigChoice(
                        icon: Icons.auto_awesome,
                        title: 'Sticker',
                        sub: 'Transparent, no bubble',
                        onTap: () => Navigator.pop(context, true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _bigChoice(
                        icon: Icons.image,
                        title: 'Photo',
                        sub: 'Normal image message',
                        onTap: () => Navigator.pop(context, false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.white54)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bigChoice({
    required IconData icon,
    required String title,
    required String sub,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 28, color: const Color(0xFF8B5CF6)),
            const SizedBox(height: 8),
            Text(title,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(sub,
                style:
                    const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadAndSendMedia({
    required File file,
    required String type,
    String? fileName,
    String? fileSize,
    int? duration,
    bool viewOnce = false,
  }) async {
    if (_currentUserId == null || _chatId == null) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Row(children: [
        SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 12),
        Text('Uploading...'),
      ]),
      duration: Duration(seconds: 60),
    ));
    try {
      String? url;
      if (type == 'image') {
        url = await CloudinaryService.uploadImage(
            file, 'aurachat/chats/$_chatId');
      } else if (type == 'video') {
        url = await CloudinaryService.uploadVideo(
            file, 'aurachat/chats/$_chatId');
      } else if (type == 'audio') {
        url = await CloudinaryService.uploadAudio(
            file, 'aurachat/chats/$_chatId');
      } else {
        url =
            await CloudinaryService.uploadFile(file, 'aurachat/chats/$_chatId');
      }
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (url == null) throw Exception('Upload failed');
      await _sendMessage(
        type: type,
        content: fileName ?? type,
        mediaUrl: url,
        fileName: fileName,
        fileSize: fileSize,
        duration: duration,
        viewOnce: viewOnce,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }

  Future<void> _playVoice(String id, String url) async {
    try {
      if (_currentlyPlayingAudioId == id) {
        if (_audioPlayer.playing) {
          await _audioPlayer.pause();
        } else {
          await _audioPlayer.play();
        }
        return;
      }
      await _audioPlayer.stop();
      await _audioPlayer.setUrl(url);
      setState(() => _currentlyPlayingAudioId = id);
      await _audioPlayer.play();
    } catch (_) {}
  }

  Future<void> _openFile(String url, String? fileName) async {
    try {
      final dir = await getTemporaryDirectory();
      final ext = fileName?.split('.').last ?? 'bin';
      final path = '${dir.path}/${const Uuid().v4()}.$ext';
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      final f = File(path);
      await resp.pipe(f.openWrite());
      await OpenFilex.open(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Cannot open: $e')));
      }
    }
  }

  void _openImageViewer(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PhotoView(
              imageProvider: CachedNetworkImageProvider(url),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 2,
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openViewOnce(String id, String url, {required bool isVideo}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ViewOnceViewer(
        url: url,
        isVideo: isVideo,
        onExpired: () async {
          if (mounted) Navigator.pop(context);
          try {
            await FirebaseFirestore.instance
                .collection('chats')
                .doc(_chatId)
                .collection('messages')
                .doc(id)
                .update({
              'deleted_for_everyone': true,
              'text': 'This message was deleted',
              'content': 'This message was deleted',
              'media_url': null,
            });
          } catch (_) {}
        },
      ),
    );
  }

  Future<void> _openLocationMap(double lat, double lng) async {
    final uri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _shareLocation() async {
    Navigator.pop(context);
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition();
      String label = 'Shared location';
      try {
        final r = await http.get(Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?format=json&lat=${pos.latitude}&lon=${pos.longitude}&zoom=14'));
        if (r.statusCode == 200) {
          final d = jsonDecode(r.body);
          if (d['display_name'] != null) {
            label = (d['display_name'] as String).split(',').take(3).join(', ');
          }
        }
      } catch (_) {}
      await _sendMessage(
        type: 'location',
        content: '📍 Location',
        location: {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'label': label,
          'live': false,
        },
      );
    } catch (_) {}
  }

  Future<void> _startLiveLocation() async {
    Navigator.pop(context);
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final first = await Geolocator.getCurrentPosition();
      final msgId = const Uuid().v4();
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .doc(msgId)
          .set({
        'id': msgId,
        'sender_id': _currentUserId,
        'type': 'location',
        'media_type': 'location',
        'location_live': true,
        'location_lat': first.latitude,
        'location_lng': first.longitude,
        'location_label': 'Live location',
        'created_at': FieldValue.serverTimestamp(),
        'is_read': false,
        'is_edited': false,
        'deleted_for_everyone': false,
        'deleted_for': [],
        'reactions': {},
      });
      _liveSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((p) async {
        try {
          await FirebaseFirestore.instance
              .collection('chats')
              .doc(_chatId)
              .collection('messages')
              .doc(msgId)
              .update(
                  {'location_lat': p.latitude, 'location_lng': p.longitude});
        } catch (_) {}
      });
      _liveTimer = Timer(const Duration(minutes: 15), () async {
        await _liveSub?.cancel();
        _liveSub = null;
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(_chatId)
            .collection('messages')
            .doc(msgId)
            .update({
          'location_live': false,
          'location_label': 'Live location ended',
        });
      });
    } catch (_) {}
  }

  Future<void> _openShareContactSheet() async {
    Navigator.pop(context);
    if (_currentUserId == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: _currentUserId)
        .get();
    final contacts = <Map<String, dynamic>>[];
    for (final doc in snap.docs) {
      final c = doc.data();
      if ((c['type'] ?? 'direct') != 'direct') continue;
      final parts = List<String>.from(c['participants'] ?? []);
      final otherId =
          parts.firstWhere((id) => id != _currentUserId, orElse: () => '');
      if (otherId.isEmpty) continue;
      if (!_userCache.containsKey(otherId)) {
        await _fetchMissingUsers({otherId});
      }
      final u = _userCache[otherId];
      if (u != null) contacts.add({'uid': otherId, ...u});
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _glassSheet(
        child: SafeArea(
          child: contacts.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No contacts found',
                      style: TextStyle(color: Colors.white54)),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: contacts.length,
                  itemBuilder: (_, i) {
                    final c = contacts[i];
                    final name = c['display_name'] ?? c['username'] ?? 'User';
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            const Color(0xFF8B5CF6).withOpacity(0.3),
                        backgroundImage: c['avatar_url'] != null
                            ? CachedNetworkImageProvider(c['avatar_url'])
                            : null,
                        child: c['avatar_url'] == null
                            ? Text(name.toString()[0].toUpperCase())
                            : null,
                      ),
                      title: Text(name.toString(),
                          style: const TextStyle(color: Colors.white)),
                      onTap: () {
                        Navigator.pop(context);
                        _sendMessage(
                          type: 'contact',
                          content: '👤 Contact',
                          contact: {
                            'uid': c['uid'],
                            'username': c['username'],
                            'display_name': name,
                            'avatar_url': c['avatar_url'],
                          },
                        );
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _pickViewOnce() async {
    final picker = ImagePicker();
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _glassSheet(
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text('View once',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.image, color: Color(0xFF8B5CF6)),
                title: const Text('Pick photo',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 'photo'),
              ),
              ListTile(
                leading:
                    const Icon(Icons.videocam, color: Color(0xFF8B5CF6)),
                title: const Text('Pick video',
                    style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, 'video'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    final x = choice == 'photo'
        ? await picker.pickImage(source: ImageSource.gallery)
        : await picker.pickVideo(source: ImageSource.gallery);
    if (x == null) return;
    await _uploadAndSendMedia(
      file: File(x.path),
      type: choice == 'photo' ? 'image' : 'video',
      fileName: choice == 'photo' ? 'Photo' : 'Video',
      viewOnce: true,
    );
  }

  void _showMessageOptions(Map<String, dynamic> m) {
    final isMe = m['sender_id'] == _currentUserId;
    final isDeleted = m['deleted_for_everyone'] == true;
    final isText = (m['media_type'] ?? 'text') == 'text';
    final isEdited = m['is_edited'] == true;
    _selectedMessageId = m['id'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _glassSheet(
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isDeleted) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final e in const ['❤️', '👍', '😂', '😮', '😢', '🔥'])
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              _quickReact(m['id'], e);
                            },
                            child:
                                Text(e, style: const TextStyle(fontSize: 28)),
                          ),
                        ),
                    ],
                  ),
                  const Divider(color: Colors.white10),
                ],
                if (isMe && isText && !isDeleted)
                  _sheetTile(Icons.edit, 'Edit', () {
                    Navigator.pop(context);
                    _openEditDialog(m);
                  }),
                if (isEdited && !isDeleted)
                  _sheetTile(Icons.history, 'Edit history', () {
                    Navigator.pop(context);
                    _openEditHistory(m['id']);
                  }),
                if (isText && !isDeleted)
                  _sheetTile(Icons.copy, 'Copy', () {
                    Navigator.pop(context);
                    Clipboard.setData(
                        ClipboardData(text: (m['text'] ?? '').toString()));
                  }),
                if (!isDeleted) ...[
                  _sheetTile(Icons.reply, 'Reply', () {
                    Navigator.pop(context);
                    _setReply(m);
                  }),
                  _sheetTile(Icons.share, 'Forward', () {
                    Navigator.pop(context);
                    _forwardMessage(m);
                  }),
                  _sheetTile(Icons.push_pin, 'Pin', () {
                    Navigator.pop(context);
                    _pinMessage(m['id']);
                  }),
                  _sheetTile(Icons.bookmark, 'Save', () {
                    Navigator.pop(context);
                    _saveMessage(m);
                  }),
                  if (m['media_url'] != null)
                    _sheetTile(Icons.download, 'Download', () {
                      Navigator.pop(context);
                      _downloadMedia(m['media_url'], m['file_name'] ?? 'file');
                    }),
                  _sheetTile(Icons.check_circle, 'Select', () {
                    Navigator.pop(context);
                    _enterMultiSelect(m['id']);
                  }),
                ],
                if (!isMe && !isDeleted)
                  _sheetTile(Icons.report, 'Report', () {
                    Navigator.pop(context);
                    _openReportDialog(m);
                  }, color: Colors.orange),
                if (isMe && !isDeleted)
                  _sheetTile(Icons.delete_forever, 'Delete for everyone', () {
                    Navigator.pop(context);
                    _confirmDelete(m['id']);
                  }, color: Colors.red),
                if (!isDeleted)
                  _sheetTile(Icons.delete, 'Delete for me', () {
                    Navigator.pop(context);
                    _deleteForMe(m['id']);
                  }, color: Colors.red),
                _sheetTile(Icons.close, 'Cancel', () => Navigator.pop(context),
                    color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetTile(IconData i, String label, VoidCallback onTap,
      {Color? color}) {
    return ListTile(
      leading: Icon(i, color: color ?? const Color(0xFF8B5CF6)),
      title: Text(label,
          style: TextStyle(color: color ?? Colors.white, fontSize: 14)),
      onTap: onTap,
    );
  }

  Future<void> _quickReact(String id, String emoji) async {
    if (_currentUserId == null) return;
    final ref = FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .doc(id);
    final doc = await ref.get();
    if (!doc.exists) return;
    final r = Map<String, dynamic>.from(doc.data()?['reactions'] ?? {});
    final users = List<String>.from(r[emoji] ?? []);
    if (users.contains(_currentUserId)) {
      users.remove(_currentUserId);
    } else {
      users.add(_currentUserId!);
    }
    if (users.isEmpty) {
      r.remove(emoji);
    } else {
      r[emoji] = users;
    }
    await ref.update({'reactions': r});
  }

  void _setReply(Map<String, dynamic> m) {
    setState(() {
      _replyingTo = m['id'];
      _replyingToContent =
          (m['text'] ?? m['content'] ?? m['media_type'] ?? 'Media').toString();
      final u = _userCache[m['sender_id']];
      _replyingToSender =
          (u?['display_name'] ?? u?['username'] ?? 'Unknown').toString();
    });
  }

  void _openEditDialog(Map<String, dynamic> m) {
    _editController.text = (m['text'] ?? m['content'] ?? '').toString();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1a103c),
        title: const Text('Edit message',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _editController,
          maxLines: null,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDeco('New text...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              final id = m['id'];
              final t = _editController.text.trim();
              Navigator.pop(context);
              if (t.isEmpty) return;
              await FirebaseFirestore.instance
                  .collection('chats')
                  .doc(_chatId)
                  .collection('messages')
                  .doc(id)
                  .update({
                'text': t,
                'content': t,
                'is_edited': true,
                'updated_at': FieldValue.serverTimestamp(),
              });
            },
            child: const Text('Save',
                style: TextStyle(color: Color(0xFF8B5CF6))),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditHistory(String msgId) async {
    final doc = await FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .doc(msgId)
        .get();
    if (!doc.exists) return;
    final d = doc.data()!;
    final history = (d['edit_history'] as List?) ?? [];
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1a103c),
        title: const Text('Version history',
            style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 320,
          child: ListView(
            shrinkWrap: true,
            children: [
              _histTile('Current',
                  (d['text'] ?? d['content'] ?? '').toString(),
                  highlight: true),
              for (final h in history.reversed)
                _histTile(
                  _fmtTs(h['edited_at']),
                  (h['text'] ?? '').toString(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _histTile(String time, String text, {bool highlight = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0xFF8B5CF6).withOpacity(0.08)
            : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: highlight
                ? const Color(0xFF8B5CF6)
                : const Color(0xFF8B5CF6).withOpacity(0.4),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(time,
              style: TextStyle(
                  color: highlight
                      ? const Color(0xFF8B5CF6)
                      : Colors.white38,
                  fontSize: 10,
                  fontWeight: highlight
                      ? FontWeight.w600
                      : FontWeight.normal)),
          const SizedBox(height: 4),
          Text(text,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }

  String _fmtTs(dynamic ts) {
    if (ts == null) return '';
    final d = ts is Timestamp ? ts.toDate() : DateTime.tryParse(ts.toString());
    if (d == null) return '';
    return DateFormat('MMM d, HH:mm').format(d);
  }

  void _confirmDelete(String id) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1a103c),
        title: const Text('Delete for everyone?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
            'This will delete the message for all participants.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseFirestore.instance
                  .collection('chats')
                  .doc(_chatId)
                  .collection('messages')
                  .doc(id)
                  .update({
                'deleted_for_everyone': true,
                'text': 'This message was deleted',
                'content': 'This message was deleted',
                'media_url': null,
              });
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteForMe(String id) async {
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .doc(id)
        .update({
      'deleted_for': FieldValue.arrayUnion([_currentUserId]),
    });
  }

  Future<void> _pinMessage(String id) async {
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('pinned_messages')
        .doc(id)
        .set({
      'message_id': id,
      'pinned_at': FieldValue.serverTimestamp(),
      'pinned_by': _currentUserId,
      'scope': 'both',
      'hidden_for': [],
    });
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .update({'pinned_message_id': id});
    await _loadPinnedMessages();
  }

  Future<void> _unpinMessage(String id) async {
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('pinned_messages')
        .doc(id)
        .delete();
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .update({'pinned_message_id': FieldValue.delete()});
    await _loadPinnedMessages();
  }

  Future<void> _saveMessage(Map<String, dynamic> m) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .collection('saved')
        .add({
      'text': m['text'],
      'media_url': m['media_url'],
      'media_type': m['media_type'],
      'sticker': m['sticker'],
      'contact': m['contact'],
      'location_lat': m['location_lat'],
      'location_lng': m['location_lng'],
      'location_label': m['location_label'],
      'from_sender': _userCache[m['sender_id']]?['display_name'],
      'from_chat': _chatName,
      'from_chat_id': _chatId,
      'original_msg_id': m['id'],
      'saved_at': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saved')));
    }
  }

  Future<void> _downloadMedia(String url, String name) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) throw Exception('Download failed');
      Directory dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download/AURA');
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      if (!await dir.exists()) await dir.create(recursive: true);
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(res.bodyBytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved to ${f.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _forwardMessage(Map<String, dynamic> m) async {
    final snap = await FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: _currentUserId)
        .get();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _glassSheet(
        child: SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: snap.docs.length,
            itemBuilder: (_, i) {
              final c = snap.docs[i];
              if (c.id == _chatId) return const SizedBox.shrink();
              final d = c.data();
              final name = d['name'] ?? d['title'] ?? 'Chat';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF8B5CF6).withOpacity(0.3),
                  backgroundImage: d['avatar_url'] != null
                      ? CachedNetworkImageProvider(d['avatar_url'])
                      : null,
                  child: d['avatar_url'] == null
                      ? Text(name.toString()[0].toUpperCase())
                      : null,
                ),
                title: Text(name.toString(),
                    style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _performForward(m, c.id);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _performForward(
      Map<String, dynamic> m, String targetChatId) async {
    final ref = FirebaseFirestore.instance
        .collection('chats')
        .doc(targetChatId)
        .collection('messages')
        .doc();
    await ref.set({
      'id': ref.id,
      'text': m['text'],
      'content': m['text'],
      'media_url': m['media_url'],
      'media_type': m['media_type'] ?? 'text',
      'file_name': m['file_name'],
      'file_size': m['file_size'],
      'duration': m['duration'],
      'sticker': m['sticker'],
      'contact': m['contact'],
      'location_lat': m['location_lat'],
      'location_lng': m['location_lng'],
      'location_label': m['location_label'],
      'sender_id': _currentUserId,
      'is_forwarded': true,
      'created_at': FieldValue.serverTimestamp(),
      'is_read': false,
      'is_edited': false,
      'deleted_for_everyone': false,
      'deleted_for': [],
      'reactions': {},
    });
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(targetChatId)
        .update({
      'last_message': '📤 Forwarded',
      'last_message_at': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Forwarded')));
    }
  }

  void _enterMultiSelect(String id) {
    setState(() {
      _multiSelectMode = true;
      _selectedMessageIds.clear();
      _selectedMessageIds.add(id);
    });
  }

  void _exitMultiSelect() {
    setState(() {
      _multiSelectMode = false;
      _selectedMessageIds.clear();
    });
  }

  void _toggleMultiSelect(String id) {
    setState(() {
      if (_selectedMessageIds.contains(id)) {
        _selectedMessageIds.remove(id);
      } else {
        _selectedMessageIds.add(id);
      }
      if (_selectedMessageIds.isEmpty) _multiSelectMode = false;
    });
  }

  Future<void> _blockUser() async {
    if (_otherUserId == null || _currentUserId == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .update({
      'blocked_users': FieldValue.arrayUnion([_otherUserId]),
    });
    if (mounted) setState(() => _iBlockedThem = true);
  }

  Future<void> _unblockUser() async {
    if (_otherUserId == null || _currentUserId == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_currentUserId)
        .update({
      'blocked_users': FieldValue.arrayRemove([_otherUserId]),
    });
    if (mounted) setState(() => _iBlockedThem = false);
  }

  void _openNicknameDialog() {
    final ctrl = TextEditingController(text: _otherUserNickname ?? '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1a103c),
        title: const Text('Nickname', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: _inputDeco('Enter nickname...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              final v = ctrl.text.trim();
              Navigator.pop(context);
              if (_otherUserId == null) return;
              if (v.isEmpty) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(_currentUserId)
                    .collection('nicknames')
                    .doc(_otherUserId)
                    .delete()
                    .catchError((_) {});
                if (mounted) setState(() => _otherUserNickname = null);
              } else {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(_currentUserId)
                    .collection('nicknames')
                    .doc(_otherUserId)
                    .set({
                  'nickname': v,
                  'updated_at': FieldValue.serverTimestamp(),
                });
                if (mounted) setState(() => _otherUserNickname = v);
              }
            },
            child: const Text('Save',
                style: TextStyle(color: Color(0xFF8B5CF6))),
          ),
        ],
      ),
    );
  }

  Future<void> _openReportDialog(Map<String, dynamic> m) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1a103c),
        title: const Text('Report message',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Why are you reporting this?',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDeco('Add details (optional)...'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Report',
                style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await FirebaseFirestore.instance.collection('reports').add({
          'reporter_id': _currentUserId,
          'reported_user_id': m['sender_id'],
          'chat_id': _chatId,
          'message_id': m['id'],
          'message_content': m['text'] ?? m['content'] ?? '',
          'media_type': m['media_type'] ?? 'text',
          'media_url': m['media_url'],
          'details': ctrl.text.trim(),
          'created_at': FieldValue.serverTimestamp(),
          'status': 'pending',
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Report submitted')));
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to submit')));
        }
      }
    }
  }

  Widget _glassSheet({required Widget child}) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1a103c).withOpacity(0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border:
                Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
          ),
          child: child,
        ),
      ),
    );
  }

  Future<void> _startCall(bool video) async {
    if (!_isGroup && _isBlocked) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Unblock to call')));
      return;
    }
    if (_otherUserId == null && !_isGroup) return;
    final channel = CallService.generateChannelName();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen.active(
          channelName: channel,
          isVideoCall: video,
          targetUserId: _otherUserId ?? _chatId ?? 'unknown',
          targetUserName: _chatName ?? 'Unknown',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTextChanged);
    _scrollController.removeListener(_onScroll);
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _editController.dispose();
    _searchController.dispose();
    _gifSearchController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    _audioRecorder.dispose();
    _messageSubscription?.cancel();
    _chatSubscription?.cancel();
    _typingSubscription?.cancel();
    _statusSubscription?.cancel();
    _liveSub?.cancel();
    _liveTimer?.cancel();
    for (final s in _blockUnsub) {
      s.cancel();
    }
    _otherTypingHideTimer?.cancel();
    _typingTimer?.cancel();
    _recordingTimer?.cancel();
    _onlineHeartbeat?.cancel();
    for (final v in _videoControllers.values) {
      v.dispose();
    }
    final uid = _currentUserId;
    if (uid != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({
        'is_online': false,
        'last_seen': FieldValue.serverTimestamp(),
      }).catchError((_) {});
      if (_chatId != null) {
        FirebaseFirestore.instance
            .collection('chats')
            .doc(_chatId)
            .collection('typing')
            .doc(uid)
            .delete()
            .catchError((_) {});
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: _isSearching ? _buildSearchAppBar() : _buildHeader(),
      body: Stack(
        children: [
          Column(
            children: [
              if (_pinnedMessages.isNotEmpty) _buildPinnedBanner(),
              if (_isBlocked) _buildBlockedBanner(),
              if (!_canSend || _isAnnouncementsOnly) _buildAdminBanner(),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF8B5CF6)))
                    : _messages.isEmpty
                        ? const _EmptyState()
                        : _buildMessageList(),
              ),
              if (_otherUserTyping && !_isGroup && !_isBlocked)
                _buildTypingIndicator(),
              if (_replyingTo != null) _buildReplyBar(),
              if (_multiSelectMode) _buildMultiSelectBar(),
              if (_isRecording) _buildRecordingBar(),
              if (_showEmojiPicker) _buildPickerPanel(),
              _buildInputBar(),
            ],
          ),
          if (_showScrollDown)
            Positioned(
              bottom: 90,
              right: 16,
              child: GestureDetector(
                onTap: () {
                  _scrollController.animateTo(
                    _scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1a103c).withOpacity(0.95),
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: Colors.white.withOpacity(0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.keyboard_arrow_down,
                      color: Colors.white, size: 22),
                ),
              ),
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildHeader() {
    final displayName = _otherUserNickname ?? _chatName ?? 'Chat';
    final verified = _userCache[_otherUserId]?['is_verified'] == true;
    String status;
    Color statusColor;
    if (_isGroup || _isChannel) {
      status = 'Tap for info';
      statusColor = const Color(0xFF06B6D4);
    } else if (_isBlocked) {
      status = _iBlockedThem ? 'You blocked this user' : 'Blocked';
      statusColor = Colors.red.shade300;
    } else if (_otherUserTyping) {
      status = 'typing...';
      statusColor = const Color(0xFF06B6D4);
    } else if (_otherUserOnline) {
      status = 'Online';
      statusColor = const Color(0xFF22C55E);
    } else if (_otherUserLastSeen != null) {
      status = 'Last seen ${_timeAgo(_otherUserLastSeen!)}';
      statusColor = Colors.white54;
    } else {
      status = 'Offline';
      statusColor = Colors.white54;
    }

    return PreferredSize(
      preferredSize: const Size.fromHeight(66),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding:
                const EdgeInsets.only(top: 8, bottom: 8, left: 10, right: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              border: Border(
                  bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  _headerCircle(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_isGroup || _isChannel) {
                          Navigator.pushNamed(context, '/group_info', arguments: {
                            'chatId': _chatId,
                            'chatName': _chatName,
                            'chatAvatar': _chatAvatar,
                            'isChannel': _isChannel,
                          });
                          return;
                        }
                        if (_otherUserId != null) {
                          Navigator.pushNamed(
                            context,
                            '/public_profile',
                            arguments: {
                              'userId': _otherUserId,
                              'username': displayName,
                              'avatar_url': _chatAvatar,
                            },
                          );
                        }
                      },
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.only(
                            left: 4, right: 14, top: 4, bottom: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.06)),
                        ),
                        child: Row(
                          children: [
                            Stack(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xFF8B5CF6),
                                        Color(0xFF06B6D4)
                                      ],
                                    ),
                                  ),
                                  child: _chatAvatar != null &&
                                          _chatAvatar!.isNotEmpty
                                      ? ClipOval(
                                          child: CachedNetworkImage(
                                            imageUrl: _chatAvatar!,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : Center(
                                          child: Text(
                                            displayName.isNotEmpty
                                                ? displayName[0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                ),
                                if (_otherUserOnline && !_isGroup)
                                  Positioned(
                                    right: -1,
                                    bottom: -1,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF22C55E),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: const Color(0xFF0A0A0F),
                                            width: 2),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (verified) ...[
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.verified,
                                          color: Color(0xFF1DA1F2),
                                          size: 13,
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    status,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 11,
                                      fontWeight: _otherUserOnline ||
                                              _otherUserTyping
                                          ? FontWeight.w500
                                          : FontWeight.w400,
                                      fontStyle: _otherUserTyping
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _headerCircle(
                    icon: Icons.search,
                    onTap: () => setState(() => _isSearching = true),
                  ),
                  const SizedBox(width: 6),
                  _headerCircle(
                    icon: Icons.videocam,
                    onTap: () => _startCall(true),
                  ),
                  const SizedBox(width: 6),
                  _headerCircle(
                    icon: Icons.call,
                    onTap: () => _startCall(false),
                  ),
                  const SizedBox(width: 6),
                  _headerCircle(
                    icon: Icons.more_vert,
                    onTap: _showMoreMenu,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerCircle({
    required IconData icon,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor ?? Colors.white70, size: 18),
      ),
    );
  }

  PreferredSizeWidget _buildSearchAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0A0A0F),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white70),
        onPressed: () => setState(() {
          _isSearching = false;
          _searchResults.clear();
          _searchController.clear();
        }),
      ),
      title: TextField(
        controller: _searchController,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Search messages',
          hintStyle: TextStyle(color: Colors.white30),
          border: InputBorder.none,
        ),
        onChanged: (q) {
          final lower = q.toLowerCase();
          setState(() {
            _searchResults = _messages
                .where((m) =>
                    (m['text'] ?? '').toString().toLowerCase().contains(lower))
                .toList();
            _currentSearchIndex = _searchResults.isEmpty ? -1 : 0;
          });
        },
      ),
    );
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _glassSheet(
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              if (!_isGroup && _otherUserId != null)
                _sheetTile(Icons.person, 'View Profile', () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/public_profile', arguments: {
                    'userId': _otherUserId,
                    'username': _chatName,
                    'avatar_url': _chatAvatar,
                  });
                }),
              if (!_isGroup && _otherUserId != null)
                _sheetTile(Icons.tag, 'Set Nickname', () {
                  Navigator.pop(context);
                  _openNicknameDialog();
                }),
              if (_isGroup || _isChannel)
                _sheetTile(Icons.info_outline, 'Group Info', () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/group_info', arguments: {
                    'chatId': _chatId,
                    'chatName': _chatName,
                    'chatAvatar': _chatAvatar,
                    'isChannel': _isChannel,
                  });
                }),
              _sheetTile(Icons.bookmark, 'Saved Messages', () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const _SavedMessagesScreen()),
                );
              }),
              _sheetTile(Icons.image, 'Create Sticker', () {
                Navigator.pop(context);
                _createStickerFromGallery();
              }),
              _sheetTile(
                _iBlockedThem ? Icons.lock_open : Icons.block,
                _iBlockedThem ? 'Unblock Contact' : 'Block Contact',
                () {
                  Navigator.pop(context);
                  if (_iBlockedThem) {
                    _unblockUser();
                  } else {
                    _blockUser();
                  }
                },
                color: Colors.red,
              ),
              _sheetTile(Icons.close, 'Cancel', () => Navigator.pop(context),
                  color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinnedBanner() {
    return GestureDetector(
      onTap: () {
        final first = _pinnedMessages.first;
        final idx =
            _messages.indexWhere((m) => m['id'] == first['message_id']);
        if (idx >= 0 && _scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent - (idx * 80.0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            const Color(0xFF8B5CF6).withOpacity(0.15),
            const Color(0xFF06B6D4).withOpacity(0.10),
          ]),
          border: Border(
              bottom: BorderSide(
                  color: const Color(0xFF8B5CF6).withOpacity(0.25))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < _pinnedMessages.length; i++) ...[
              if (i > 0) const Divider(color: Colors.white12, height: 10),
              Builder(builder: (context) {
                final p = _pinnedMessages[i];
                final msg = _messages.firstWhere(
                  (m) => m['id'] == p['message_id'],
                  orElse: () => {},
                );
                return Row(
                  children: [
                    const Icon(Icons.push_pin,
                        size: 12, color: Color(0xFF8B5CF6)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (_userCache[msg['sender_id']]?['display_name'] ??
                                    'Pinned')
                                .toString(),
                            style: const TextStyle(
                                color: Color(0xFF8B5CF6),
                                fontSize: 10,
                                fontWeight: FontWeight.w700),
                          ),
                          Text(
                            (msg['text'] ??
                                    msg['media_type'] ??
                                    'Message')
                                .toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.75),
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 14, color: Colors.white38),
                      onPressed: () => _unpinMessage(p['message_id']),
                    ),
                  ],
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedBanner() {
    return GestureDetector(
      onTap: () {
        if (_iBlockedThem) _unblockUser();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        color: Colors.red.withOpacity(0.1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.block, size: 14, color: Colors.red.shade300),
            const SizedBox(width: 8),
            Text(
              _iBlockedThem
                  ? 'You blocked this person. Tap to unblock.'
                  : 'This user blocked you.',
              style: TextStyle(color: Colors.red.shade300, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.orange.withOpacity(0.15),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 14, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isAnnouncementsOnly
                  ? 'Announcements only — only admins can send'
                  : 'Chat disabled by admin',
              style: const TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    final list = _messages.reversed.toList();
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final m = list[index];
        final prev = index > 0 ? list[index - 1] : null;
        final showDate = _shouldShowDate(m, prev);
        final isMine = m['sender_id'] == _currentUserId;
        final selected = _selectedMessageIds.contains(m['id']);
        return Column(
          children: [
            if (showDate) _dateDivider(m['created_at']),
            _MessageBubble(
              message: m,
              isMine: isMine,
              showAvatar: _isGroup && !isMine,
              selected: selected,
              multiSelect: _multiSelectMode,
              userCache: _userCache,
              onTap: () {
                if (_multiSelectMode) {
                  _toggleMultiSelect(m['id']);
                } else if (m['view_once'] == true && m['media_url'] != null) {
                  _openViewOnce(
                    m['id'],
                    m['media_url'],
                    isVideo: m['media_type'] == 'video',
                  );
                } else if (m['media_type'] == 'image' &&
                    m['media_url'] != null) {
                  _openImageViewer(m['media_url']);
                }
              },
              onLongPress: () {
                if (!_multiSelectMode) _showMessageOptions(m);
              },
              onDoubleTap: () => _quickReact(m['id'], '❤️'),
              onReply: () => _setReply(m),
              playingAudioId: _currentlyPlayingAudioId,
              audioPosition: _audioPosition,
              audioDuration: _audioDuration,
              onPlayAudio: (id, url) => _playVoice(id, url),
              onOpenImage: _openImageViewer,
              onOpenFile: _openFile,
              onOpenLocation: _openLocationMap,
              videoControllers: _videoControllers,
              onVideoInit: () => setState(() {}),
              onOpenProfile: (uid, name, avatar) {
                Navigator.pushNamed(context, '/public_profile', arguments: {
                  'userId': uid,
                  'username': name,
                  'avatar_url': avatar,
                });
              },
            ),
          ],
        );
      },
    );
  }

  bool _shouldShowDate(Map<String, dynamic> m, Map<String, dynamic>? prev) {
    if (prev == null) return true;
    final a = _parseTs(m['created_at']);
    final b = _parseTs(prev['created_at']);
    if (a == null || b == null) return false;
    return a.year != b.year || a.month != b.month || a.day != b.day;
  }

  DateTime? _parseTs(dynamic t) {
    if (t == null) return null;
    if (t is Timestamp) return t.toDate();
    if (t is String) return DateTime.tryParse(t);
    return null;
  }

  Widget _dateDivider(dynamic ts) {
    final d = _parseTs(ts);
    if (d == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            _formatDate(d),
            style:
                TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yest = today.subtract(const Duration(days: 1));
    final md = DateTime(d.year, d.month, d.day);
    if (md == today) return 'Today';
    if (md == yest) return 'Yesterday';
    return DateFormat('MMM d').format(d);
  }

  String _timeAgo(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, HH:mm').format(d);
  }

  Widget _buildTypingIndicator() {
    final u = _otherUserId != null ? _userCache[_otherUserId] : null;
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: const Color(0xFF8B5CF6).withOpacity(0.3),
            backgroundImage: u?['avatar_url'] != null
                ? CachedNetworkImageProvider(u!['avatar_url'])
                : null,
            child: u?['avatar_url'] == null
                ? Text(
                    (u?['display_name'] ?? 'U').toString()[0].toUpperCase(),
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  )
                : null,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF8B5CF6),
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1a103c).withOpacity(0.9),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Replying to ${_replyingToSender ?? ''}',
                    style: const TextStyle(
                        color: Color(0xFF8B5CF6),
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                Text(
                  _replyingToContent ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.white54),
            onPressed: () => setState(() {
              _replyingTo = null;
              _replyingToContent = null;
              _replyingToSender = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiSelectBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1a103c).withOpacity(0.95),
        border: Border(
            top: BorderSide(color: const Color(0xFF8B5CF6).withOpacity(0.3))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            onPressed: _exitMultiSelect,
          ),
          Text('${_selectedMessageIds.length}',
              style: const TextStyle(
                  color: Color(0xFF8B5CF6),
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.copy, color: Color(0xFF8B5CF6)),
            onPressed: () {
              final text = _messages
                  .where((m) => _selectedMessageIds.contains(m['id']))
                  .map((m) => (m['text'] ?? '').toString())
                  .join('\n\n');
              Clipboard.setData(ClipboardData(text: text));
              _exitMultiSelect();
            },
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Color(0xFF8B5CF6)),
            onPressed: () async {
              final selected = _messages
                  .where((m) => _selectedMessageIds.contains(m['id']))
                  .toList();
              if (selected.isEmpty) return;
              final snap = await FirebaseFirestore.instance
                  .collection('chats')
                  .where('participants', arrayContains: _currentUserId)
                  .get();
              if (!mounted) return;
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (_) => _glassSheet(
                  child: SafeArea(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: snap.docs.length,
                      itemBuilder: (_, i) {
                        final c = snap.docs[i];
                        if (c.id == _chatId) return const SizedBox.shrink();
                        final d = c.data();
                        final name = d['name'] ?? d['title'] ?? 'Chat';
                        return ListTile(
                          title: Text(name.toString(),
                              style:
                                  const TextStyle(color: Colors.white)),
                          onTap: () async {
                            Navigator.pop(context);
                            for (final m in selected) {
                              await _performForward(m, c.id);
                            }
                            _exitMultiSelect();
                          },
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () async {
              for (final id in _selectedMessageIds) {
                await FirebaseFirestore.instance
                    .collection('chats')
                    .doc(_chatId)
                    .collection('messages')
                    .doc(id)
                    .update({
                  'deleted_for_everyone': true,
                  'text': 'This message was deleted',
                  'content': 'This message was deleted',
                  'media_url': null,
                });
              }
              _exitMultiSelect();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        border: Border(top: BorderSide(color: Colors.red.withOpacity(0.2))),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration:
                const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Text(
            _fmtDuration(_recordingSeconds),
            style: const TextStyle(
                color: Colors.red, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 24,
              child: Row(
                children: _recordingWave
                    .map((h) => Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          width: 3,
                          height: 4 + h * 18,
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: _cancelRecording,
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Color(0xFF8B5CF6)),
            onPressed: _stopRecordingAndSend,
          ),
        ],
      ),
    );
  }

  Widget _buildPickerPanel() {
    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: const Color(0xFF1a103c).withOpacity(0.98),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.04))),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                _mainTab('emoji', Icons.emoji_emotions, 'Emoji'),
                const SizedBox(width: 6),
                _mainTab('sticker', Icons.auto_awesome, 'Stickers'),
                const SizedBox(width: 6),
                _mainTab('gif', Icons.gif_box, 'GIFs'),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          Expanded(
            child: IndexedStack(
              index: _pickerTab == 'emoji'
                  ? 0
                  : _pickerTab == 'sticker'
                      ? 1
                      : 2,
              children: [
                _buildEmojiPanel(),
                _buildStickerPanel(),
                _buildGifPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mainTab(String tab, IconData icon, String label) {
    final active = _pickerTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _pickerTab = tab;
            _lastPanelMode = tab;
          });
          if (tab == 'gif' && !_gifsLoaded) _loadGifs();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFF8B5CF6).withOpacity(0.12)
                : Colors.transparent,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            border: Border(
              bottom: BorderSide(
                color: active ? const Color(0xFF8B5CF6) : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 14, color: active ? Colors.white : Colors.white38),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmojiPanel() {
    return Column(
      children: [
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            children: _emojiCategories.entries.map((e) {
              final active = e.key == _currentEmojiCategory;
              return GestureDetector(
                onTap: () => setState(() => _currentEmojiCategory = e.key),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF8B5CF6).withOpacity(0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(e.value['icon'] as String,
                      style: const TextStyle(fontSize: 18)),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount:
                (_emojiCategories[_currentEmojiCategory]!['emojis'] as List)
                    .length,
            itemBuilder: (_, i) {
              final e = (_emojiCategories[_currentEmojiCategory]!['emojis']
                  as List)[i];
              return GestureDetector(
                onTap: () {
                  _messageController.text += e as String;
                  _messageController.selection = TextSelection.collapsed(
                      offset: _messageController.text.length);
                },
                child: Center(
                  child: Text(e as String,
                      style: const TextStyle(fontSize: 22)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStickerPanel() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Text(
                'My Stickers',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showStickerCreatorSheet(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 12, color: Color(0xFF8B5CF6)),
                      SizedBox(width: 4),
                      Text(
                        'New',
                        style: TextStyle(
                          color: Color(0xFF8B5CF6),
                          fontSize: 11,
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
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              _stickerPackTab('fav', '⭐ Fav'),
              for (final p in _stickerPacks)
                _stickerPackTab(p['id'], (p['name'] ?? 'Pack').toString()),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _loadingStickers
              ? const Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFF8B5CF6), strokeWidth: 2))
              : _currentStickerPackId == 'fav' && _favoriteStickers.isEmpty
                  ? _stickerEmpty(
                      'No favorites yet — long-press any of your stickers to add one')
                  : _currentStickerPackId != 'fav' &&
                          _stickersInCurrentPack().isEmpty
                      ? _stickerEmpty('This pack is empty')
                      : GridView.builder(
                          padding: const EdgeInsets.all(10),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemCount: _stickersInCurrentPack().length,
                          itemBuilder: (_, i) {
                            final s = _stickersInCurrentPack()[i];
                            return GestureDetector(
                              onTap: () => _sendSticker(s),
                              onLongPress: () => _showStickerOptions(s, true),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: s['sticker_type'] == 'video'
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          child: _StickerVideoPreview(
                                              url: s['url'] as String),
                                        )
                                      : CachedNetworkImage(
                                          imageUrl: s['url'] as String,
                                          fit: BoxFit.contain,
                                          memCacheWidth: 200,
                                        ),
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  Widget _stickerPackTab(String id, String label) {
    final active = _currentStickerPackId == id;
    return GestureDetector(
      onTap: () => setState(() => _currentStickerPackId = id),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF8B5CF6).withOpacity(0.25)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.white60,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _stickersInCurrentPack() {
    if (_currentStickerPackId == 'fav') return _favoriteStickers;
    return _myStickers
        .where((s) => s['pack_id'] == _currentStickerPackId)
        .toList();
  }

  Widget _stickerEmpty(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          msg,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
        ),
      ),
    );
  }

  void _showStickerCreatorSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _glassSheet(
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              const Text('Create Sticker',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _bigChoice(
                      icon: Icons.image,
                      title: 'From Photo',
                      sub: 'Pick an image',
                      onTap: () {
                        Navigator.pop(context);
                        _createStickerFromGallery();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _bigChoice(
                      icon: Icons.videocam,
                      title: 'From Video',
                      sub: 'Max 5 seconds',
                      onTap: () {
                        Navigator.pop(context);
                        _createStickerFromGallery(video: true);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _showStickerOptions(Map<String, dynamic> s, bool isMine) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _glassSheet(
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetTile(
                s['favorite'] == true ? Icons.star : Icons.star_border,
                s['favorite'] == true
                    ? 'Remove from Favorites'
                    : 'Add to Favorites',
                () {
                  Navigator.pop(context);
                  _toggleFavoriteSticker(s);
                },
                color: Colors.amber,
              ),
              if (isMine)
                _sheetTile(Icons.delete, 'Delete sticker', () {
                  Navigator.pop(context);
                  _deleteSticker(s['id']);
                }, color: Colors.red),
              _sheetTile(Icons.close, 'Cancel', () => Navigator.pop(context),
                  color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGifPanel() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(
            controller: _gifSearchController,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Search GIFs...',
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (q) => _loadGifs(q: q),
          ),
        ),
        Expanded(
          child: _loadingGifs
              ? const Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFF8B5CF6), strokeWidth: 2))
              : _gifs.isEmpty
                  ? _stickerEmpty('No GIFs found')
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                        childAspectRatio: 1,
                      ),
                      itemCount: _gifs.length,
                      itemBuilder: (_, i) {
                        final g = _gifs[i];
                        return GestureDetector(
                          onTap: () => _sendGif(g['full'] as String),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: CachedNetworkImage(
                              imageUrl: g['preview'] as String,
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildInputBar() {
    final hasText = _messageController.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F).withOpacity(0.95),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _inputCircle(
              icon: Icons.add,
              onTap: (_canSend &&
                      !_isAnnouncementsOnly &&
                      !(_isBlocked && !_isGroup))
                  ? _showAttachmentSheet
                  : null,
            ),
            const SizedBox(width: 4),
            _inputCircle(
              icon: _showEmojiPicker
                  ? Icons.keyboard
                  : _lastPanelMode == 'sticker'
                      ? Icons.auto_awesome
                      : _lastPanelMode == 'gif'
                          ? Icons.gif_box
                          : Icons.emoji_emotions_outlined,
              onTap: (_canSend &&
                      !_isAnnouncementsOnly &&
                      !(_isBlocked && !_isGroup))
                  ? () {
                      setState(() => _showEmojiPicker = !_showEmojiPicker);
                      if (_showEmojiPicker) {
                        FocusScope.of(context).unfocus();
                        if (_lastPanelMode == 'gif' && !_gifsLoaded) _loadGifs();
                      }
                    }
                  : null,
              iconColor: _lastPanelMode == 'sticker'
                  ? const Color(0xFF8B5CF6)
                  : _lastPanelMode == 'gif'
                      ? const Color(0xFFEC4899)
                      : const Color(0xFFFBBF24),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 140),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: TextField(
                  controller: _messageController,
                  enabled: _canSend &&
                      !_isAnnouncementsOnly &&
                      !(_isBlocked && !_isGroup),
                  minLines: 1,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: _isBlocked && !_isGroup
                        ? 'Unblock to send'
                        : !_canSend || _isAnnouncementsOnly
                            ? 'Only admins can send'
                            : 'Message',
                    hintStyle: const TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  onTap: () {
                    if (_showEmojiPicker) {
                      setState(() => _showEmojiPicker = false);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: hasText ? _sendTextMessage : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: hasText
                      ? const LinearGradient(
                          colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)])
                      : null,
                  color: hasText ? null : Colors.white.withOpacity(0.06),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.send,
                  size: 18,
                  color: hasText ? Colors.white : Colors.white38,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputCircle({
    required IconData icon,
    VoidCallback? onTap,
    Color? iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Icon(
          icon,
          size: 18,
          color:
              onTap == null ? Colors.white24 : (iconColor ?? Colors.white70),
        ),
      ),
    );
  }

  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _glassSheet(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: [
                    _attachBtn(Icons.image, 'Gallery', const Color(0xFF8B5CF6),
                        () {
                      Navigator.pop(context);
                      _pickImage();
                    }),
                    _attachBtn(
                        Icons.camera_alt, 'Camera', const Color(0xFF06B6D4),
                        () {
                      Navigator.pop(context);
                      _takePhoto();
                    }),
                    _attachBtn(Icons.videocam, 'Video', Colors.purple, () {
                      Navigator.pop(context);
                      _pickVideo();
                    }),
                    _attachBtn(Icons.videocam_off, 'Record', Colors.pink, () {
                      Navigator.pop(context);
                      _recordVideo();
                    }),
                    _attachBtn(Icons.insert_drive_file, 'Document', Colors.blue,
                        () {
                      Navigator.pop(context);
                      _pickFile();
                    }),
                    _attachBtn(Icons.mic, 'Voice', Colors.red, () {
                      Navigator.pop(context);
                      _startRecording();
                    }),
                    _attachBtn(Icons.local_fire_department, 'View once',
                        Colors.orange, () async {
                      Navigator.pop(context);
                      await _pickViewOnce();
                    }),
                    _attachBtn(Icons.location_on, 'Location',
                        const Color(0xFF10B981), () {
                      _shareLocation();
                    }),
                    _attachBtn(Icons.satellite_alt, 'Live Loc',
                        Colors.redAccent, () {
                      _startLiveLocation();
                    }),
                    if (_isGroup)
                      _attachBtn(Icons.contact_page, 'Contact', Colors.amber,
                          () {
                        _openShareContactSheet();
                      }),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _attachBtn(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 76,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  String _fmtDuration(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30),
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
      );
}

// ═══════════════════════════════════════════════════════════════════════
// SAVED MESSAGES SCREEN
// ═══════════════════════════════════════════════════════════════════════
class _SavedMessagesScreen extends StatelessWidget {
  const _SavedMessagesScreen();

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuraAuthProvider>(context, listen: false);
    final uid = auth.user?.uid ?? auth.mockUserId;
    if (uid == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0F),
        body: Center(
            child: Text('Not signed in', style: TextStyle(color: Colors.white))),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        title: const Text('Saved Messages',
            style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('saved')
            .orderBy('saved_at', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFF8B5CF6)));
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Text('Nothing saved yet',
                  style: TextStyle(color: Colors.white38)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              return _savedTile(d, docs[i].reference);
            },
          );
        },
      ),
    );
  }

  Widget _savedTile(Map<String, dynamic> d, DocumentReference ref) {
    final text = (d['text'] ?? '').toString();
    final url = d['media_url'] as String?;
    final type = (d['media_type'] ?? 'text').toString();
    final sender = (d['from_sender'] ?? 'Unknown').toString();
    final fromChat = (d['from_chat'] ?? '').toString();
    final ts = d['saved_at'] as Timestamp?;
    final timeStr =
        ts != null ? DateFormat('MMM d, HH:mm').format(ts.toDate()) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bookmark, size: 12, color: Color(0xFFFBBF24)),
              const SizedBox(width: 6),
              Expanded(
                child: Text('$sender · $fromChat',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11),
                    overflow: TextOverflow.ellipsis),
              ),
              Text(timeStr,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 10)),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 16, color: Colors.white38),
                onPressed: () => ref.delete(),
              ),
            ],
          ),
          if (type == 'image' && url != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: url,
                  height: 160,
                  fit: BoxFit.cover,
                ),
              ),
            )
          else if (type == 'sticker' && url != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                width: 120,
                height: 120,
                child:
                    CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
              ),
            )
          else if (type == 'video' && url != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('🎥 Video: $url',
                  style: const TextStyle(
                      color: Color(0xFF06B6D4), fontSize: 12)),
            ),
          if (text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(text,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// EMPTY STATE
// ═══════════════════════════════════════════════════════════════════════
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 80, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          Text('No messages yet',
              style: TextStyle(color: Colors.white.withOpacity(0.3))),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// STICKER VIDEO PREVIEW
// ═══════════════════════════════════════════════════════════════════════
class _StickerVideoPreview extends StatefulWidget {
  final String url;
  const _StickerVideoPreview({required this.url});

  @override
  State<_StickerVideoPreview> createState() => _StickerVideoPreviewState();
}

class _StickerVideoPreviewState extends State<_StickerVideoPreview> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..setLooping(true)
      ..setVolume(0)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _controller.play();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _controller.value.isInitialized
        ? AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          )
        : const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF8B5CF6)),
            ),
          );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// INVITE / SLUG DETECTORS
// ═══════════════════════════════════════════════════════════════════════
class _InviteLinkDetector {
  static final _re = RegExp(
    r'https?://([a-z0-9-]+\.web\.app)/join/([A-Za-z0-9_-]{2,60})',
    caseSensitive: false,
  );
  static String? detect(String text) {
    if (text.isEmpty) return null;
    final m = _re.firstMatch(text);
    return m?.group(2);
  }

  static bool isInvite(String url) => _re.hasMatch(url);
}

class _AuraShortLink {
  static final _re = RegExp(
    r'https?://[a-z0-9-]+\.web\.app/(?!join/)([A-Za-z0-9_-]{2,60})/?$',
    caseSensitive: false,
  );
  static String? detect(String text) {
    if (text.isEmpty) return null;
    final m = _re.firstMatch(text.trim());
    return m?.group(1);
  }

  static bool isShortLink(String url) => _re.hasMatch(url.trim());
}

class _InviteCard extends StatefulWidget {
  final String code;
  final VoidCallback onJoined;
  const _InviteCard({required this.code, required this.onJoined});

  @override
  State<_InviteCard> createState() => _InviteCardState();
}

class _InviteCardState extends State<_InviteCard> {
  Map<String, dynamic>? _info;
  String? _inviteDocId;
  bool _loading = true;
  bool _joining = false;
  bool _already = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final q = await FirebaseFirestore.instance
          .collection('invitations')
          .where('code', isEqualTo: widget.code)
          .where('is_active', isEqualTo: true)
          .limit(1)
          .get();
      if (q.docs.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      _inviteDocId = q.docs.first.id;
      final inv = q.docs.first.data();
      final chatId = inv['chat_id'] as String?;
      if (chatId == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final chat = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .get();
      if (!chat.exists) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final d = chat.data()!;
      final auth = Provider.of<AuraAuthProvider>(context, listen: false);
      final uid = auth.user?.uid ?? auth.mockUserId;
      final parts = List<String>.from(d['participants'] ?? []);
      if (!mounted) return;
      setState(() {
        _info = {
          'chat_id': chatId,
          'name': d['name'] ?? 'Chat',
          'avatar_url': d['avatar_url'],
          'type': d['type'] ?? 'group',
          'member_count': parts.length,
        };
        _already = uid != null && parts.contains(uid);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _join() async {
    if (_info == null) return;
    final auth = Provider.of<AuraAuthProvider>(context, listen: false);
    final uid = auth.user?.uid ?? auth.mockUserId;
    final name = auth.displayName ?? auth.userName ?? 'User';
    if (uid == null) return;
    setState(() => _joining = true);
    final res = await InvitationService.joinWithInvitation(
      invitationId: _inviteDocId ?? widget.code,
      userId: uid,
      userName: name,
    );
    if (!mounted) return;
    setState(() => _joining = false);
    if (res['success'] == true) {
      widget.onJoined();
      Navigator.pushNamed(context, '/chat', arguments: {
        'chatId': res['chat_id'] ?? _info!['chat_id'],
        'chatName': res['chat_name'] ?? _info!['name'],
        'isGroup': (res['chat_type'] ?? 'group') == 'group',
        'isChannel': (res['chat_type'] ?? 'group') == 'channel',
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        width: 260,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF8B5CF6))),
          SizedBox(width: 10),
          Text('Loading invite...',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
      );
    }
    if (_info == null) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        width: 240,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withOpacity(0.2)),
        ),
        child: const Row(children: [
          Icon(Icons.link_off, color: Colors.red, size: 16),
          SizedBox(width: 8),
          Text('Invalid or expired link',
              style: TextStyle(color: Colors.red, fontSize: 12)),
        ]),
      );
    }
    final name = (_info!['name'] ?? 'Chat').toString();
    final avatar = _info!['avatar_url'] as String?;
    final type = (_info!['type'] ?? 'group').toString();
    final members = _info!['member_count'] ?? 0;

    return GestureDetector(
      onTap: _already ? null : _join,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        width: 260,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF8B5CF6).withOpacity(0.14),
              const Color(0xFF06B6D4).withOpacity(0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)]),
                border: Border.all(
                    color: const Color(0xFF8B5CF6).withOpacity(0.35),
                    width: 2),
              ),
              child: avatar != null && avatar.isNotEmpty
                  ? ClipOval(
                      child: CachedNetworkImage(
                          imageUrl: avatar, fit: BoxFit.cover))
                  : Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Icon(
                        type == 'channel' ? Icons.campaign : Icons.group,
                        size: 11,
                        color: const Color(0xFF8B5CF6)),
                    const SizedBox(width: 4),
                    Text(
                      type == 'channel' ? 'CHANNEL' : 'GROUP',
                      style: const TextStyle(
                          color: Color(0xFF8B5CF6),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '$members member${members == 1 ? '' : 's'}',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5), fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _joining
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF8B5CF6)))
                : Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: _already
                          ? null
                          : const LinearGradient(
                              colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)]),
                      color:
                          _already ? Colors.white.withOpacity(0.1) : null,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _already ? 'Open' : 'Join',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _SlugCard extends StatefulWidget {
  final String slug;
  final VoidCallback onMessage;
  const _SlugCard({required this.slug, required this.onMessage});

  @override
  State<_SlugCard> createState() => _SlugCardState();
}

class _SlugCardState extends State<_SlugCard> {
  Map<String, dynamic>? _info;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final sd = await FirebaseFirestore.instance
          .collection('slugs')
          .doc(widget.slug)
          .get();
      if (!sd.exists) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final d = sd.data()!;
      final type = d['type'] as String?;
      if (type == 'group' || type == 'channel') {
        final cd = await FirebaseFirestore.instance
            .collection('chats')
            .doc(d['chat_id'])
            .get();
        if (!cd.exists) {
          if (mounted) setState(() => _loading = false);
          return;
        }
        final c = cd.data()!;
        final parts = List<String>.from(c['participants'] ?? []);
        final auth = Provider.of<AuraAuthProvider>(context, listen: false);
        final uid = auth.user?.uid ?? auth.mockUserId;
        if (!mounted) return;
        setState(() {
          _info = {
            'kind': type,
            'id': d['chat_id'],
            'name': c['name'] ?? 'Chat',
            'avatar': c['avatar_url'],
            'members': parts.length,
            'already': uid != null && parts.contains(uid),
          };
          _loading = false;
        });
      } else if (type == 'user') {
        final ud = await FirebaseFirestore.instance
            .collection('users')
            .doc(d['user_id'])
            .get();
        if (!ud.exists) {
          if (mounted) setState(() => _loading = false);
          return;
        }
        final u = ud.data()!;
        if (!mounted) return;
        setState(() {
          _info = {
            'kind': 'user',
            'id': d['user_id'],
            'name': u['display_name'] ?? u['username'] ?? 'User',
            'username': u['username'],
            'avatar': u['avatar_url'],
            'verified': (u['email'] ?? '').toString().endsWith('@gmail.com'),
          };
          _loading = false;
        });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinGroup() async {
    if (_info == null || _info!['kind'] == 'user') return;
    final auth = Provider.of<AuraAuthProvider>(context, listen: false);
    final uid = auth.user?.uid ?? auth.mockUserId;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_info!['id'])
          .update({
        'participants': FieldValue.arrayUnion([uid]),
        'unread_counts.$uid': 0,
        'last_message_at': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      Navigator.pushNamed(context, '/chat', arguments: {
        'chatId': _info!['id'],
        'chatName': _info!['name'],
        'isGroup': _info!['kind'] == 'group',
        'isChannel': _info!['kind'] == 'channel',
      });
    } catch (_) {}
  }

  Future<void> _openDirect() async {
    if (_info == null || _info!['kind'] != 'user') return;
    final auth = Provider.of<AuraAuthProvider>(context, listen: false);
    final uid = auth.user?.uid ?? auth.mockUserId;
    if (uid == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: uid)
        .where('type', isEqualTo: 'direct')
        .get();
    for (final d in snap.docs) {
      if ((d.data()['participants'] as List).contains(_info!['id'])) {
        if (!mounted) return;
        Navigator.pushNamed(context, '/chat', arguments: {
          'chatId': d.id,
          'chatName': _info!['name'],
        });
        return;
      }
    }
    final ref = FirebaseFirestore.instance.collection('chats').doc();
    await ref.set({
      'id': ref.id,
      'type': 'direct',
      'participants': [uid, _info!['id']],
      'unread_counts': {uid: 0, _info!['id']: 0},
      'last_message': '',
      'last_message_at': FieldValue.serverTimestamp(),
      'created_at': FieldValue.serverTimestamp(),
    });
    if (!mounted) return;
    Navigator.pushNamed(context, '/chat', arguments: {
      'chatId': ref.id,
      'chatName': _info!['name'],
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        width: 260,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Row(children: [
          SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFF8B5CF6))),
          SizedBox(width: 10),
          Text('Loading...',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
      );
    }
    if (_info == null) return const SizedBox.shrink();

    final isUser = _info!['kind'] == 'user';
    final already = _info!['already'] == true;
    final name = (_info!['name'] ?? '').toString();
    final avatar = _info!['avatar'] as String?;
    final verified = _info!['verified'] == true;

    return GestureDetector(
      onTap: isUser
          ? _openDirect
          : (already
              ? () => Navigator.pushNamed(context, '/chat', arguments: {
                    'chatId': _info!['id'],
                    'chatName': name,
                  })
              : _joinGroup),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        width: 280,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF8B5CF6).withOpacity(0.12),
              const Color(0xFF06B6D4).withOpacity(0.07),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)]),
                border: Border.all(
                    color: const Color(0xFF8B5CF6).withOpacity(0.35),
                    width: 2),
              ),
              child: avatar != null && avatar.isNotEmpty
                  ? ClipOval(
                      child: CachedNetworkImage(
                          imageUrl: avatar, fit: BoxFit.cover))
                  : Center(
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Icon(
                        isUser
                            ? Icons.person
                            : _info!['kind'] == 'channel'
                                ? Icons.campaign
                                : Icons.group,
                        size: 11,
                        color: const Color(0xFF8B5CF6)),
                    const SizedBox(width: 4),
                    Text(
                      isUser
                          ? 'USER'
                          : _info!['kind'] == 'channel'
                              ? 'CHANNEL'
                              : 'GROUP',
                      style: const TextStyle(
                          color: Color(0xFF8B5CF6),
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.6),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Row(children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                    ),
                    if (verified) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.verified,
                          color: Color(0xFF1DA1F2), size: 12),
                    ],
                  ]),
                  Text(
                    isUser
                        ? '@${_info!['username']}'
                        : '${_info!['members']} member${_info!['members'] == 1 ? '' : 's'}',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.5), fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                gradient: already || isUser
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)]),
                color:
                    already || isUser ? Colors.white.withOpacity(0.1) : null,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                isUser
                    ? 'Message'
                    : already
                        ? 'Open'
                        : 'Join',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// LINK PREVIEW BUBBLE
// ═══════════════════════════════════════════════════════════════════════
class _LinkPreviewBubble extends StatelessWidget {
  final Map<String, dynamic> preview;
  final VoidCallback onTap;
  const _LinkPreviewBubble({required this.preview, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final image = preview['image'] as String?;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF8B5CF6).withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: const Border(
              left: BorderSide(color: Color(0xFF8B5CF6), width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (image != null && image.isNotEmpty)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8)),
                child: CachedNetworkImage(
                  imageUrl: image,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((preview['domain'] ?? '').toString().isNotEmpty)
                    Text(
                      (preview['domain']).toString().toUpperCase(),
                      style: const TextStyle(
                          color: Color(0xFF8B5CF6),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5),
                    ),
                  if ((preview['title'] ?? '').toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        (preview['title']).toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  if ((preview['description'] ?? '').toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        (preview['description']).toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 11.5),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// VIEW-ONCE VIEWER
// ═══════════════════════════════════════════════════════════════════════
class _ViewOnceViewer extends StatefulWidget {
  final String url;
  final bool isVideo;
  final VoidCallback onExpired;
  const _ViewOnceViewer({
    required this.url,
    required this.isVideo,
    required this.onExpired,
  });
  @override
  State<_ViewOnceViewer> createState() => _ViewOnceViewerState();
}

class _ViewOnceViewerState extends State<_ViewOnceViewer> {
  int _remaining = 5;
  Timer? _t;
  VideoPlayerController? _vc;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _vc = VideoPlayerController.networkUrl(Uri.parse(widget.url))
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            _vc!.play();
          }
        });
    }
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) {
        _t?.cancel();
        widget.onExpired();
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: widget.isVideo
                ? (_vc?.value.isInitialized == true
                    ? AspectRatio(
                        aspectRatio: _vc!.value.aspectRatio,
                        child: VideoPlayer(_vc!))
                    : const CircularProgressIndicator(
                        color: Color(0xFF8B5CF6)))
                : PhotoView(
                    imageProvider: CachedNetworkImageProvider(widget.url),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 2,
                  ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$_remaining',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 12,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                _t?.cancel();
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// EFFECT BURSTS
// ═══════════════════════════════════════════════════════════════════════
class _EffectBurst {
  static const _styleMap = <String, String>{
    '🎉': 'confetti',
    '🎊': 'confetti',
    '❤️': 'hearts',
    '💖': 'hearts',
    '💗': 'hearts',
    '🎆': 'fireworks',
    '🎇': 'fireworks',
    '💥': 'explosion',
    '💣': 'explosion',
    '✨': 'sparkles',
    '🌟': 'sparkles',
    '⭐': 'sparkles',
  };
  static bool isTrigger(String s) => _styleMap.containsKey(s.trim());

  static void fire(BuildContext context, String emoji) {
    final style = _styleMap[emoji.trim()] ?? 'confetti';
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _EffectLayer(style: style, onDone: () => entry.remove()),
    );
    overlay.insert(entry);
  }
}

class _EffectLayer extends StatefulWidget {
  final String style;
  final VoidCallback onDone;
  const _EffectLayer({required this.style, required this.onDone});
  @override
  State<_EffectLayer> createState() => _EffectLayerState();
}

class _EffectLayerState extends State<_EffectLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 3));
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random();
    final palette = {
          'confetti': ['🎉', '🎊', '🎈', '✨', '🎁'],
          'hearts': ['❤️', '💖', '💗', '💓', '💕', '💘', '🧡'],
          'fireworks': ['🎆', '🎇', '✨', '💫', '🌟'],
          'explosion': ['💥', '💣'],
          'sparkles': ['✨', '🌟', '⭐', '💫'],
        }[widget.style] ??
        ['✨'];
    final count = {
          'confetti': 40,
          'hearts': 30,
          'fireworks': 24,
          'explosion': 6,
          'sparkles': 30,
        }[widget.style] ??
        24;
    _particles = List.generate(count, (_) {
      return _Particle(
        emoji: palette[rnd.nextInt(palette.length)],
        dx: rnd.nextDouble(),
        angle: rnd.nextDouble() * math.pi * 2,
        dist: 100 + rnd.nextDouble() * 160,
        size: 28 + rnd.nextDouble() * 24,
        delay: rnd.nextDouble() * 0.3,
      );
    });
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          return Stack(
            children: _particles.map((p) {
              final t = ((_c.value - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
              double x;
              double y;
              if (widget.style == 'hearts') {
                x = p.dx * size.width;
                y = size.height - (size.height + 60) * t;
              } else if (widget.style == 'fireworks' ||
                  widget.style == 'explosion') {
                x = size.width / 2 + math.cos(p.angle) * p.dist * t;
                y = size.height / 2 + math.sin(p.angle) * p.dist * t;
              } else if (widget.style == 'sparkles') {
                x = p.dx * size.width;
                y = (0.2 + p.dx * 0.6) * size.height;
              } else {
                x = p.dx * size.width;
                y = (size.height + 60) * t - 60;
              }
              return Positioned(
                left: x,
                top: y,
                child: Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: t * 4 * math.pi,
                    child: Transform.scale(
                      scale: 0.6 + 0.6 * t,
                      child: Text(p.emoji, style: TextStyle(fontSize: p.size)),
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _Particle {
  final String emoji;
  final double dx;
  final double angle;
  final double dist;
  final double size;
  final double delay;
  _Particle({
    required this.emoji,
    required this.dx,
    required this.angle,
    required this.dist,
    required this.size,
    required this.delay,
  });
}

// ═══════════════════════════════════════════════════════════════════════
// EMOJI-ONLY ANIMATION
// ═══════════════════════════════════════════════════════════════════════
class _EmojiOnly extends StatefulWidget {
  final String emoji;
  const _EmojiOnly({required this.emoji});
  @override
  State<_EmojiOnly> createState() => _EmojiOnlyState();
}

class _EmojiOnlyState extends State<_EmojiOnly>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        final scale = 1 + 0.2 * math.sin(t * math.pi * 2);
        final rot = 0.05 * math.sin(t * math.pi * 4);
        return Transform.rotate(
          angle: rot,
          child: Transform.scale(
            scale: scale,
            child: Text(widget.emoji, style: const TextStyle(fontSize: 72)),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MESSAGE BUBBLE
// ═══════════════════════════════════════════════════════════════════════
class _MessageBubble extends StatefulWidget {
  final Map<String, dynamic> message;
  final bool isMine;
  final bool showAvatar;
  final bool selected;
  final bool multiSelect;
  final Map<String, Map<String, dynamic>> userCache;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDoubleTap;
  final VoidCallback onReply;
  final String? playingAudioId;
  final Duration audioPosition;
  final Duration audioDuration;
  final void Function(String id, String url) onPlayAudio;
  final void Function(String url) onOpenImage;
  final void Function(String url, String? fileName) onOpenFile;
  final void Function(double lat, double lng) onOpenLocation;
  final Map<String, VideoPlayerController> videoControllers;
  final VoidCallback onVideoInit;
  final void Function(String uid, String name, String? avatar) onOpenProfile;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.showAvatar,
    required this.selected,
    required this.multiSelect,
    required this.userCache,
    required this.onTap,
    required this.onLongPress,
    required this.onDoubleTap,
    required this.onReply,
    required this.playingAudioId,
    required this.audioPosition,
    required this.audioDuration,
    required this.onPlayAudio,
    required this.onOpenImage,
    required this.onOpenFile,
    required this.onOpenLocation,
    required this.videoControllers,
    required this.onVideoInit,
    required this.onOpenProfile,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  double _dragOffset = 0;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isMine = widget.isMine;
    final type = message['media_type'] ?? 'text';
    final isDeleted = message['deleted_for_everyone'] == true;
    final isSticker = type == 'sticker';
    final text = (message['text'] ?? message['content'] ?? '').toString();
    final mediaUrl = message['media_url'] as String?;
    final sticker = message['sticker'] as Map<String, dynamic>?;
    final reactions = Map<String, dynamic>.from(message['reactions'] ?? {});
    final images = message['images'] as List?;
    final hasAlbum = images != null && images.length > 1;
    final singleEmoji = !hasAlbum && _isSingleEmoji(text);
    final linkPreview = message['link_preview'] as Map<String, dynamic>?;
    final inviteCode = _InviteLinkDetector.detect(text);
    final slug = inviteCode == null ? _AuraShortLink.detect(text) : null;
    final isViewOnce = message['view_once'] == true;

    return Padding(
      padding: EdgeInsets.only(
        bottom: reactions.isNotEmpty ? 18 : 10,
        top: 2,
      ),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine && widget.showAvatar) _messageAvatar(),
          if (!isMine && !widget.showAvatar) const SizedBox(width: 32),
          Flexible(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: widget.onTap,
                  onLongPress: widget.onLongPress,
                  onDoubleTap: widget.onDoubleTap,
                  onHorizontalDragUpdate: (d) {
                    setState(() {
                      _dragOffset += d.delta.dx * (isMine ? -1 : 1);
                      _dragOffset = _dragOffset.clamp(0, 80);
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    if (_dragOffset > 40) widget.onReply();
                    setState(() => _dragOffset = 0);
                  },
                  onHorizontalDragCancel: () {
                    setState(() => _dragOffset = 0);
                  },
                  child: Transform.translate(
                    offset: Offset(isMine ? -_dragOffset : _dragOffset, 0),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: isSticker
                              ? EdgeInsets.zero
                              : (type == 'text'
                                  ? const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8)
                                  : const EdgeInsets.all(4)),
                          decoration: BoxDecoration(
                            gradient: (isMine && !isSticker)
                                ? const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF8B5CF6),
                                      Color(0xFF06B6D4),
                                    ],
                                  )
                                : null,
                            color: isSticker
                                ? Colors.transparent
                                : (isMine
                                    ? null
                                    : Colors.white.withOpacity(0.05)),
                            borderRadius: BorderRadius.circular(18).copyWith(
                              bottomRight:
                                  isMine ? const Radius.circular(4) : null,
                              bottomLeft:
                                  !isMine ? const Radius.circular(4) : null,
                            ),
                            border: (!isMine && !isSticker)
                                ? Border.all(
                                    color: Colors.white.withOpacity(0.08))
                                : null,
                            boxShadow: isSticker
                                ? null
                                : [
                                    BoxShadow(
                                      color: isMine
                                          ? const Color(0xFF8B5CF6)
                                              .withOpacity(0.25)
                                          : Colors.black.withOpacity(0.15),
                                      blurRadius: isMine ? 8 : 2,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                          ),
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.78,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (message['is_forwarded'] == true)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      bottom: 4, left: 4, right: 4, top: 2),
                                  child: Row(
                                    children: [
                                      Icon(Icons.share,
                                          size: 10,
                                          color: isMine
                                              ? Colors.white70
                                              : Colors.white54),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Forwarded',
                                        style: TextStyle(
                                          color: isMine
                                              ? Colors.white70
                                              : Colors.white54,
                                          fontSize: 10,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (message['reply_to'] != null)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: const Border(
                                      left: BorderSide(
                                          color: Color(0xFF8B5CF6), width: 3),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (message['reply_to_sender'] ??
                                                'Unknown')
                                            .toString(),
                                        style: const TextStyle(
                                            color: Color(0xFF8B5CF6),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        (message['reply_to_content'] ?? '')
                                            .toString(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: isMine
                                                ? Colors.white70
                                                : Colors.white54,
                                            fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              if (isDeleted)
                                const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Text(
                                    'This message was deleted',
                                    style: TextStyle(
                                        color: Colors.white38,
                                        fontStyle: FontStyle.italic,
                                        fontSize: 13),
                                  ),
                                )
                              else if (isSticker)
                                _stickerBubble(sticker)
                              else if (singleEmoji)
                                _EmojiOnly(emoji: text.trim())
                              else if (hasAlbum)
                                _albumBubble(images)
                              else if (type == 'image' && mediaUrl != null)
                                _imageBubble(mediaUrl, isViewOnce: isViewOnce)
                              else if (type == 'video' && mediaUrl != null)
                                _videoBubble(mediaUrl, isViewOnce: isViewOnce)
                              else if (type == 'audio' && mediaUrl != null)
                                _audioBubble(mediaUrl)
                              else if (type == 'gif' && mediaUrl != null)
                                _gifBubble(mediaUrl)
                              else if (type == 'file' && mediaUrl != null)
                                _fileBubble(mediaUrl)
                              else if (type == 'location')
                                _locationBubble()
                              else if (type == 'contact')
                                _contactBubble()
                              else
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    RichText(
                                      text: TextSpan(
                                        children: _Linkify.parse(
                                          text,
                                          isMine: isMine,
                                          onOpenUrl: (url) => launchUrl(
                                              Uri.parse(url),
                                              mode: LaunchMode
                                                  .externalApplication),
                                          onMention: (_) {},
                                        ),
                                      ),
                                    ),
                                    if (inviteCode != null)
                                      _InviteCard(
                                          code: inviteCode,
                                          onJoined: () {}),
                                    if (slug != null)
                                      _SlugCard(
                                          slug: slug, onMessage: () {}),
                                    if (linkPreview != null &&
                                        linkPreview.isNotEmpty)
                                      _LinkPreviewBubble(
                                        preview: linkPreview,
                                        onTap: () {
                                          final u =
                                              linkPreview['url'] as String?;
                                          if (u != null) {
                                            launchUrl(Uri.parse(u),
                                                mode: LaunchMode
                                                    .externalApplication);
                                          }
                                        },
                                      ),
                                  ],
                                ),
                              if (!isSticker && !singleEmoji) ...[
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _fmtTime(message['created_at']),
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isMine
                                            ? Colors.white70
                                            : Colors.white38,
                                      ),
                                    ),
                                    if (isMine) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        message['is_read'] == true
                                            ? Icons.done_all
                                            : Icons.done,
                                        size: 12,
                                        color: message['is_read'] == true
                                            ? Colors.white
                                            : Colors.white60,
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (_dragOffset > 20)
                          Positioned(
                            left: isMine ? 4 : null,
                            right: isMine ? null : 4,
                            top: 0,
                            bottom: 0,
                            child: Opacity(
                              opacity: (_dragOffset / 60).clamp(0.0, 1.0),
                              child: const Icon(Icons.reply,
                                  color: Color(0xFF8B5CF6), size: 20),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (reactions.isNotEmpty)
                  Positioned(
                    bottom: -12,
                    right: isMine ? null : 0,
                    left: isMine ? 0 : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1a103c),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: reactions.entries.take(5).map((e) {
                          final cnt = (e.value as List).length;
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 2),
                            child: Text(
                              '${e.key}${cnt > 1 ? cnt : ''}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageAvatar() {
    final u = widget.userCache[widget.message['sender_id']];
    final name = (u?['display_name'] ?? 'U').toString();
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => widget.onOpenProfile(
          widget.message['sender_id'],
          name,
          u?['avatar_url'],
        ),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: const Color(0xFF8B5CF6).withOpacity(0.3),
          backgroundImage: u?['avatar_url'] != null
              ? CachedNetworkImageProvider(u!['avatar_url'])
              : null,
          child: u?['avatar_url'] == null
              ? Text(name[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 12))
              : null,
        ),
      ),
    );
  }

  Widget _stickerBubble(Map<String, dynamic>? sticker) {
    if (sticker == null) return const SizedBox.shrink();
    final url = sticker['url'] as String;
    final type = sticker['sticker_type'] ?? 'static';
    return SizedBox(
      width: 160,
      height: 160,
      child: type == 'video'
          ? _StickerVideoPreview(url: url)
          : CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              memCacheWidth: 400,
            ),
    );
  }

  Widget _imageBubble(String url, {required bool isViewOnce}) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () => widget.onOpenImage(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: 260, maxHeight: 320),
              child: CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 200,
                  height: 200,
                  color: Colors.white.withOpacity(0.05),
                  child: const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF8B5CF6), strokeWidth: 2),
                  ),
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 200,
                  height: 200,
                  color: Colors.white.withOpacity(0.05),
                  child:
                      const Icon(Icons.broken_image, color: Colors.white54),
                ),
              ),
            ),
          ),
        ),
        if (isViewOnce)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_fire_department,
                      size: 10, color: Colors.orange),
                  SizedBox(width: 4),
                  Text('View once',
                      style: TextStyle(color: Colors.white, fontSize: 10)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _albumBubble(List images) {
    final n = images.length;
    final cls = n == 2 ? 2 : n == 3 ? 3 : n == 4 ? 4 : 5;
    return GestureDetector(
      onTap: () => widget.onOpenImage(
          (images[0] is Map ? images[0]['url'] : images[0]).toString()),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 300,
          height: cls == 3 ? 200 : cls == 2 ? 150 : 200,
          child: _albumLayout(images, cls),
        ),
      ),
    );
  }

  Widget _albumLayout(List images, int cls) {
    String urlOf(dynamic i) => (i is Map ? i['url'] : i).toString();
    final max = math.min(images.length, cls);
    if (cls == 2) {
      return Row(children: [
        Expanded(child: _albImg(urlOf(images[0]))),
        const SizedBox(width: 2),
        Expanded(child: _albImg(urlOf(images[1]))),
      ]);
    }
    if (cls == 3) {
      return Row(children: [
        Expanded(flex: 2, child: _albImg(urlOf(images[0]))),
        const SizedBox(width: 2),
        Expanded(
          child: Column(children: [
            Expanded(child: _albImg(urlOf(images[1]))),
            const SizedBox(height: 2),
            Expanded(child: _albImg(urlOf(images[2]))),
          ]),
        ),
      ]);
    }
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, mainAxisSpacing: 2, crossAxisSpacing: 2),
      itemCount: max,
      itemBuilder: (_, i) {
        final showMore = i == 4 && images.length > 5;
        return Stack(
          fit: StackFit.expand,
          children: [
            _albImg(urlOf(images[i])),
            if (showMore)
              Container(
                color: Colors.black54,
                alignment: Alignment.center,
                child: Text('+${images.length - 5}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
              ),
          ],
        );
      },
    );
  }

  Widget _albImg(String url) => CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        memCacheWidth: 400,
      );

  Widget _videoBubble(String url, {required bool isViewOnce}) {
    final controller = widget.videoControllers.putIfAbsent(url, () {
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      c.initialize().then((_) => widget.onVideoInit());
      return c;
    });
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 240,
            height: 180,
            color: Colors.black,
            child: controller.value.isInitialized
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoPlayer(controller),
                      const Center(
                        child: Icon(Icons.play_circle_fill,
                            color: Colors.white, size: 50),
                      ),
                    ],
                  )
                : const Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF8B5CF6), strokeWidth: 2),
                  ),
          ),
        ),
        if (isViewOnce)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_fire_department,
                      size: 10, color: Colors.orange),
                  SizedBox(width: 4),
                  Text('View once',
                      style: TextStyle(color: Colors.white, fontSize: 10)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _audioBubble(String url) {
    final isCurrent = widget.playingAudioId == widget.message['id'];
    final position = isCurrent ? widget.audioPosition : Duration.zero;
    final total = isCurrent && widget.audioDuration != Duration.zero
        ? widget.audioDuration
        : Duration(seconds: (widget.message['duration'] ?? 0) as int);
    final progress = total.inMilliseconds > 0
        ? position.inMilliseconds / total.inMilliseconds
        : 0.0;
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => widget.onPlayAudio(widget.message['id'], url),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: widget.isMine
                    ? Colors.white.withOpacity(0.25)
                    : const Color(0xFF8B5CF6).withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isCurrent && position > Duration.zero
                    ? Icons.pause
                    : Icons.play_arrow,
                color: widget.isMine
                    ? Colors.white
                    : const Color(0xFF8B5CF6),
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: Colors.white.withOpacity(0.1),
                    valueColor: AlwaysStoppedAnimation(
                      widget.isMine ? Colors.white : const Color(0xFF8B5CF6),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _fmtDur(isCurrent ? position : total),
                  style: TextStyle(
                    color: widget.isMine ? Colors.white70 : Colors.white54,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gifBubble(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260, maxHeight: 320),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: 200,
            height: 200,
            color: Colors.white.withOpacity(0.05),
          ),
        ),
      ),
    );
  }

  Widget _fileBubble(String url) {
    final name = (widget.message['file_name'] ?? 'File').toString();
    final size = (widget.message['file_size'] ?? '').toString();
    return GestureDetector(
      onTap: () => widget.onOpenFile(url, name),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.insert_drive_file,
                  color: Color(0xFF8B5CF6)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                  if (size.isNotEmpty)
                    Text(size,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _locationBubble() {
    final lat = (widget.message['location_lat'] ?? 0).toDouble();
    final lng = (widget.message['location_lng'] ?? 0).toDouble();
    final label =
        (widget.message['location_label'] ?? 'Shared location').toString();
    final isLive = widget.message['location_live'] == true;
    return GestureDetector(
      onTap: () => widget.onOpenLocation(lat, lng),
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: isLive
              ? Colors.red.withOpacity(0.08)
              : const Color(0xFF8B5CF6).withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isLive
                ? Colors.red.withOpacity(0.3)
                : const Color(0xFF8B5CF6).withOpacity(0.2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isLive
                      ? [
                          Colors.red.withOpacity(0.25),
                          Colors.orange.withOpacity(0.15)
                        ]
                      : [
                          const Color(0xFF06B6D4).withOpacity(0.25),
                          const Color(0xFF8B5CF6).withOpacity(0.25)
                        ],
                ),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Center(
                child: Icon(Icons.location_on,
                    color: isLive ? Colors.red : const Color(0xFF8B5CF6),
                    size: 36),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Icon(Icons.place,
                      size: 14,
                      color: isLive ? Colors.red : const Color(0xFF8B5CF6)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactBubble() {
    final c = Map<String, dynamic>.from(widget.message['contact'] ?? {});
    final name = (c['display_name'] ?? c['username'] ?? 'Contact').toString();
    final username = (c['username'] ?? 'user').toString();
    final avatar = c['avatar_url'] as String?;
    return GestureDetector(
      onTap: () => widget.onOpenProfile(
        (c['uid'] ?? '').toString(),
        name,
        avatar,
      ),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF8B5CF6).withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.2)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFF8B5CF6).withOpacity(0.3),
              backgroundImage:
                  avatar != null ? CachedNetworkImageProvider(avatar) : null,
              child: avatar == null
                  ? Text(name[0].toUpperCase(),
                      style: const TextStyle(color: Colors.white))
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  Text('@$username',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }

  bool _isSingleEmoji(String s) {
    final t = s.trim();
    final runes = t.runes.toList();
    if (runes.length == 1) return true;
    if (runes.length <= 4 && runes.isNotEmpty) {
      final c = runes.first;
      return (c >= 0x1F300 && c <= 0x1FAFF) ||
          (c >= 0x2600 && c <= 0x27BF);
    }
    return false;
  }

  String _fmtTime(dynamic ts) {
    final d = _parse(ts);
    if (d == null) return '';
    return DateFormat('HH:mm').format(d);
  }

  String _fmtDur(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  DateTime? _parse(dynamic t) {
    if (t == null) return null;
    if (t is Timestamp) return t.toDate();
    if (t is String) return DateTime.tryParse(t);
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// LINKIFY
// ═══════════════════════════════════════════════════════════════════════
class _Linkify {
  static final _codeBlockR = RegExp(r'```([^`]+)```');
  static final _inlineCodeR = RegExp(r'`([^`]+)`');
  static final _spoilerR = RegExp(r'\|\|([^|]+)\|\|');
  static final _underlineR = RegExp(r'__([^_]+)__');
  static final _boldR = RegExp(r'\*\*([^*]+)\*\*');
  static final _strikeR = RegExp(r'~~([^~]+)~~');
  static final _mdLinkR = RegExp(r'\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)');
  static final _urlR = RegExp(r'(https?://[^\s<]+)');
  static final _mentionR = RegExp(r'(^|\s)@([a-zA-Z0-9_]{2,30})');

  static List<InlineSpan> parse(
    String text, {
    required bool isMine,
    required void Function(String url) onOpenUrl,
    required void Function(String username) onMention,
  }) {
    final spans = <InlineSpan>[];
    final buf = StringBuffer();

    void flush() {
      if (buf.isEmpty) return;
      spans.add(TextSpan(
        text: buf.toString(),
        style: TextStyle(
          color: isMine ? Colors.white : Colors.white.withOpacity(0.92),
          fontSize: 13.5,
          height: 1.4,
        ),
      ));
      buf.clear();
    }

    void addSpan(InlineSpan s) {
      flush();
      spans.add(s);
    }

    final patterns = <_MdPattern>[
      _MdPattern(_codeBlockR, (m) => _code(m.group(1)!)),
      _MdPattern(_inlineCodeR, (m) => _code(m.group(1)!)),
      _MdPattern(_spoilerR, (m) => _spoiler(m.group(1)!)),
      _MdPattern(_underlineR, (m) => _underline(m.group(1)!)),
      _MdPattern(_boldR, (m) => _bold(m.group(1)!)),
      _MdPattern(_strikeR, (m) => _strike(m.group(1)!)),
      _MdPattern(_mdLinkR, (m) => _link(m.group(1)!, m.group(2)!, onOpenUrl)),
      _MdPattern(_urlR, (m) => _link(m.group(0)!, m.group(0)!, onOpenUrl)),
      _MdPattern(
          _mentionR, (m) => _mention(m.group(2)!, onMention, isMine: isMine)),
    ];

    var i = 0;
    while (i < text.length) {
      _MdPattern? matched;
      RegExpMatch? mm;
      for (final p in patterns) {
        final sub = text.substring(i);
        final m = p.re.firstMatch(sub);
        if (m != null && m.start == 0) {
          matched = p;
          mm = m;
          break;
        }
      }
      if (matched != null && mm != null) {
        addSpan(matched.build(mm));
        i += mm.end;
      } else {
        buf.write(text[i]);
        i++;
      }
    }
    flush();
    return spans;
  }

  static InlineSpan _code(String s) => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFF8B5CF6).withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(s,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.white)),
        ),
      );

  static InlineSpan _spoiler(String s) => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _SpoilerSpan(text: s),
      );

  static InlineSpan _underline(String s) => TextSpan(
        text: s,
        style: const TextStyle(decoration: TextDecoration.underline),
      );

  static InlineSpan _bold(String s) => TextSpan(
        text: s,
        style: const TextStyle(fontWeight: FontWeight.w700),
      );

  static InlineSpan _strike(String s) => TextSpan(
        text: s,
        style: const TextStyle(decoration: TextDecoration.lineThrough),
      );

  static InlineSpan _link(
      String label, String url, void Function(String) onOpenUrl) {
    return TextSpan(
      text: label,
      style: const TextStyle(
        color: Color(0xFF8B5CF6),
        decoration: TextDecoration.underline,
      ),
      recognizer: TapGestureRecognizer()..onTap = () => onOpenUrl(url),
    );
  }

  static InlineSpan _mention(String username, void Function(String) onMention,
      {required bool isMine}) {
    return TextSpan(
      text: '@$username',
      style: TextStyle(
        color: isMine ? Colors.white : const Color(0xFF06B6D4),
        backgroundColor: isMine
            ? Colors.white.withOpacity(0.15)
            : const Color(0xFF06B6D4).withOpacity(0.15),
        fontWeight: FontWeight.w600,
      ),
      recognizer: TapGestureRecognizer()..onTap = () => onMention(username),
    );
  }
}

class _MdPattern {
  final RegExp re;
  final InlineSpan Function(RegExpMatch) build;
  _MdPattern(this.re, this.build);
}

class _SpoilerSpan extends StatefulWidget {
  final String text;
  const _SpoilerSpan({required this.text});
  @override
  State<_SpoilerSpan> createState() => _SpoilerSpanState();
}

class _SpoilerSpanState extends State<_SpoilerSpan> {
  bool _revealed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _revealed = !_revealed),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: _revealed
              ? const Color(0xFF8B5CF6).withOpacity(0.12)
              : const Color(0xFF8B5CF6).withOpacity(0.35),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          widget.text,
          style: TextStyle(
            color: _revealed ? Colors.white : Colors.transparent,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MEDIA EDITOR SCREEN
// ═══════════════════════════════════════════════════════════════════════
class _EditorResult {
  final File file;
  const _EditorResult(this.file);
}

class _MediaEditorScreen extends StatefulWidget {
  final File initialFile;
  final bool isVideo;
  const _MediaEditorScreen({
    required this.initialFile,
    required this.isVideo,
  });

  @override
  State<_MediaEditorScreen> createState() => _MediaEditorScreenState();
}

class _MediaEditorScreenState extends State<_MediaEditorScreen> {
  final GlobalKey _canvasKey = GlobalKey();
  final _textController = TextEditingController();

  late String _mode;
  VideoPlayerController? _videoController;
  Uint8List? _originalBytes;
  ui.Image? _originalImage;
  double _imgW = 0, _imgH = 0;

  int _rotation = 0;
  double _brightness = 1.0;
  double _contrast = 1.0;
  double _saturation = 1.0;

  final List<_DrawStroke> _strokes = [];
  final List<_TextOverlay> _texts = [];

  String _tool = 'draw';
  Color _drawColor = const Color(0xFF8B5CF6);
  double _drawSize = 5;

  double _trimStart = 0, _trimEnd = 0;
  double _videoDuration = 0;

  @override
  void initState() {
    super.initState();
    _mode = widget.isVideo ? 'video' : 'photo';
    if (widget.isVideo) {
      _initVideo();
    } else {
      _initImage();
    }
  }

  Future<void> _initImage() async {
    final bytes = await widget.initialFile.readAsBytes();
    final img = await decodeImageFromList(bytes);
    if (!mounted) return;
    setState(() {
      _originalBytes = bytes;
      _originalImage = img;
      _imgW = img.width.toDouble();
      _imgH = img.height.toDouble();
    });
  }

  Future<void> _initVideo() async {
    final c = VideoPlayerController.file(widget.initialFile);
    await c.initialize();
    if (!mounted) return;
    setState(() {
      _videoController = c;
      _videoDuration = c.value.duration.inMilliseconds / 1000;
      _trimStart = 0;
      _trimEnd = _videoDuration;
    });
    c.setLooping(true);
    c.play();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _export() async {
  if (_mode == 'photo') {
    final boundary = _canvasKey.currentContext!.findRenderObject()
        as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return;
    final out = File(
        '${(await getTemporaryDirectory()).path}/edit_${const Uuid().v4()}.png');
    await out.writeAsBytes(data.buffer.asUint8List());
    if (!mounted) return;
    Navigator.pop(context, _EditorResult(out));
    return;
  }

  // Video — return original (no trim)
  if (!mounted) return;
  Navigator.pop(context, _EditorResult(widget.initialFile));
  return;
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.isVideo ? 'Edit video' : 'Edit photo',
            style: const TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.check, color: Color(0xFF8B5CF6)),
            onPressed: _export,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _mode == 'photo' ? _photoCanvas() : _videoCanvas(),
            ),
          ),
          if (_mode == 'photo' && _tool == 'draw') _drawBar(),
          if (_mode == 'video' && _tool == 'trim') _trimBar(),
          _toolBar(),
        ],
      ),
    );
  }

  Widget _photoCanvas() {
    if (_originalImage == null) {
      return const CircularProgressIndicator(color: Color(0xFF8B5CF6));
    }
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height - 200;
    final scale = math.min(w / _imgW, h / _imgH);
    final cw = _imgW * scale;
    final ch = _imgH * scale;

    return RepaintBoundary(
      key: _canvasKey,
      child: SizedBox(
        width: cw,
        height: ch,
        child: Stack(
          children: [
            Positioned.fill(
              child: RotatedBox(
                quarterTurns: _rotation ~/ 90,
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(
                    _colorMatrix(_brightness, _contrast, _saturation),
                  ),
                  child: RawImage(image: _originalImage, fit: BoxFit.contain),
                ),
              ),
            ),
            for (final t in _texts)
              Positioned(
                left: t.offset.dx * cw,
                top: t.offset.dy * ch,
                child: Text(
                  t.text,
                  style: TextStyle(
                    color: t.color,
                    fontSize: t.size,
                    fontWeight: FontWeight.bold,
                    shadows: const [
                      Shadow(color: Colors.black, blurRadius: 4)
                    ],
                  ),
                ),
              ),
            if (_tool == 'draw')
              Positioned.fill(
                child: GestureDetector(
                  onPanStart: (d) {
                    setState(() {
                      _strokes.add(_DrawStroke(
                          color: _drawColor,
                          size: _drawSize,
                          points: [d.localPosition]));
                    });
                  },
                  onPanUpdate: (d) {
                    setState(() => _strokes.last.points.add(d.localPosition));
                  },
                ),
              ),
            Positioned.fill(
              child: CustomPaint(
                painter: _StrokePainter(_strokes),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _videoCanvas() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return const CircularProgressIndicator(color: Color(0xFF8B5CF6));
    }
    return AspectRatio(
      aspectRatio: _videoController!.value.aspectRatio,
      child: Stack(
        children: [
          VideoPlayer(_videoController!),
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_trimStart.toStringAsFixed(1)}s — ${_trimEnd.toStringAsFixed(1)}s',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _drawBar() {
    const colors = [
      Color(0xFF8B5CF6),
      Color(0xFF06B6D4),
      Color(0xFFEF4444),
      Color(0xFFFBBF24),
      Color(0xFF10B981),
      Colors.white,
      Colors.black,
    ];
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Colors.black54,
      child: Row(
        children: [
          for (final c in colors)
            GestureDetector(
              onTap: () => setState(() => _drawColor = c),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _drawColor == c ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ),
          const Spacer(),
          const Icon(Icons.circle, size: 8, color: Colors.white70),
          Expanded(
            child: Slider(
              value: _drawSize,
              min: 1,
              max: 30,
              activeColor: const Color(0xFF8B5CF6),
              onChanged: (v) => setState(() => _drawSize = v),
            ),
          ),
          const Icon(Icons.circle, size: 16, color: Colors.white70),
        ],
      ),
    );
  }

  Widget _trimBar() {
    if (_videoDuration <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.black54,
      child: Row(
        children: [
          Text(_trimStart.toStringAsFixed(1) + 's',
              style: const TextStyle(color: Colors.white, fontSize: 11)),
          Expanded(
            child: RangeSlider(
              values: RangeValues(_trimStart, _trimEnd),
              min: 0,
              max: _videoDuration,
              activeColor: const Color(0xFF8B5CF6),
              onChanged: (v) {
                setState(() {
                  _trimStart = v.start;
                  _trimEnd = v.end;
                });
                _videoController?.seekTo(
                    Duration(milliseconds: (_trimStart * 1000).round()));
              },
            ),
          ),
          Text(_trimEnd.toStringAsFixed(1) + 's',
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _toolBar() {
    return Container(
      height: 72,
      color: Colors.black87,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (_mode == 'photo') _toolBtn('draw', Icons.brush, 'Draw'),
          if (_mode == 'photo') _toolBtn('text', Icons.text_fields, 'Text'),
          if (_mode == 'photo') _toolBtn('rotate', Icons.rotate_right, 'Rotate'),
          if (_mode == 'photo') _toolBtn('filter', Icons.tune, 'Filter'),
          if (_mode == 'video') _toolBtn('trim', Icons.content_cut, 'Trim'),
        ],
      ),
    );
  }

  Widget _toolBtn(String id, IconData icon, String label) {
    final active = _tool == id;
    return GestureDetector(
      onTap: () => _onTool(id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF8B5CF6).withOpacity(0.3)
              : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: active ? Colors.white : Colors.white70, size: 20),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: active ? Colors.white : Colors.white70,
                    fontSize: 10)),
          ],
        ),
      ),
    );
  }

  void _onTool(String id) {
    if (id == 'rotate') {
      setState(() => _rotation = (_rotation + 90) % 360);
      return;
    }
    if (id == 'text') {
      _showAddTextDialog();
      return;
    }
    if (id == 'filter') {
      _showFilterSheet();
      return;
    }
    setState(() => _tool = id);
  }

  Future<void> _showAddTextDialog() async {
    _textController.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1a103c),
        title:
            const Text('Add text', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _textController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter text...',
            hintStyle: TextStyle(color: Colors.white38),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add',
                style: TextStyle(color: Color(0xFF8B5CF6))),
          ),
        ],
      ),
    );
    if (ok == true && _textController.text.trim().isNotEmpty) {
      setState(() {
        _texts.add(_TextOverlay(
          text: _textController.text.trim(),
          color: Colors.white,
          size: 28,
          offset: const Offset(0.5, 0.5),
        ));
      });
    }
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a103c),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            _filterOption('Original', 1.0, 1.0, 1.0),
            _filterOption('B&W', 1.0, 1.1, 0.0),
            _filterOption('Warm', 1.0, 1.05, 1.3),
            _filterOption('Cool', 1.0, 1.05, 0.85),
            _filterOption('Vivid', 1.05, 1.3, 1.4),
            _filterOption('Fade', 1.1, 0.9, 0.8),
          ],
        ),
      ),
    );
  }

  Widget _filterOption(String label, double b, double c, double s) {
    return ListTile(
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: () {
        Navigator.pop(context);
        setState(() {
          _brightness = b;
          _contrast = c;
          _saturation = s;
        });
      },
    );
  }

  List<double> _colorMatrix(double b, double c, double s) {
    final sr = (1 - s) * 0.2126;
    final sg = (1 - s) * 0.7152;
    final sb = (1 - s) * 0.0722;
    return <double>[
      (sr + s) * c * b, sg * c * b, sb * c * b, 0, 0,
      sr * c * b, (sg + s) * c * b, sb * c * b, 0, 0,
      sr * c * b, sg * c * b, (sb + s) * c * b, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }
}

class _DrawStroke {
  final Color color;
  final double size;
  final List<Offset> points;
  _DrawStroke({required this.color, required this.size, required this.points});
}

class _StrokePainter extends CustomPainter {
  final List<_DrawStroke> strokes;
  _StrokePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      if (s.points.length < 2) continue;
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.size
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(s.points[0].dx, s.points[0].dy);
      for (var i = 1; i < s.points.length; i++) {
        path.lineTo(s.points[i].dx, s.points[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) =>
      old.strokes.length != strokes.length;
}

class _TextOverlay {
  final String text;
  final Color color;
  final double size;
  final Offset offset;
  _TextOverlay({
    required this.text,
    required this.color,
    required this.size,
    required this.offset,
  });
}
