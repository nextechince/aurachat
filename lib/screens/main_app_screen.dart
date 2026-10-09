import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart' show LumaAuthProvider;
import '../../providers/chat_provider.dart';
import '../../services/call_service.dart';

class MainAppScreen extends StatefulWidget {
  const MainAppScreen({super.key});

  @override
  State<MainAppScreen> createState() => _MainAppScreenState();
}

class _MainAppScreenState extends State<MainAppScreen> {
  int _bottomIndex = 0;

  // Folder pills — 0 = All, 1 = Unread, 2 = Groups, 3 = Channels, 4 = Bots
  int _folderIndex = 0;

  final Map<String, Map<String, dynamic>> _userCache = {};
  final Set<String> _inFlight = {};
  List<String> _myBlockedUsers = [];

  // Scroll controller for folder pills
  final ScrollController _folderScroll = ScrollController();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<LumaAuthProvider>(context, listen: false);
      final chat = Provider.of<ChatProvider>(context, listen: false);

      if (auth.mockUserId != null) {
        chat.setMockUser(auth.mockUserId!);
      } else {
        chat.loadChats();
      }
      _listenToMyBlockedUsers();
    });
  }

  @override
  void dispose() {
    _folderScroll.dispose();
    super.dispose();
  }

  String get _myUid {
    final auth = Provider.of<LumaAuthProvider>(context, listen: false);
    final fromProvider = auth.currentUserId ?? auth.mockUserId;
    if (fromProvider != null && fromProvider.isNotEmpty) return fromProvider;
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  void _listenToMyBlockedUsers() {
    final uid = _myUid;
    if (uid.isEmpty) return;
    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists) return;
      setState(() {
        _myBlockedUsers =
            List<String>.from(doc.data()?['blocked_users'] ?? []);
      });
    });
  }

  Future<void> _fetchOtherUser(String uid) async {
    if (uid.isEmpty) return;
    if (_userCache.containsKey(uid)) return;
    if (_inFlight.contains(uid)) return;
    _inFlight.add(uid);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (doc.exists && doc.data() != null) {
        final d = doc.data()!;
        _userCache[uid] = {
          'uid': uid,
          'username': (d['username'] ?? '') as String,
          'display_name': (d['display_name'] ??
              d['username'] ??
              d['name'] ??
              'Unknown') as String,
          'avatar_url': d['avatar_url'],
          'email': d['email'],
          'is_bot': d['is_bot'] == true,
        };
      } else {
        _userCache[uid] = {
          'uid': uid,
          'username': '',
          'display_name': 'User',
          'avatar_url': null,
          'email': null,
          'is_bot': false,
        };
      }
      if (mounted) setState(() {});
    } catch (_) {
      _userCache[uid] = {
        'uid': uid,
        'username': '',
        'display_name': 'User',
        'avatar_url': null,
        'email': null,
        'is_bot': false,
      };
      if (mounted) setState(() {});
    } finally {
      _inFlight.remove(uid);
    }
  }

  String _formatChatTime(dynamic lastMessageAt) {
    if (lastMessageAt == null) return '';
    DateTime dt;
    if (lastMessageAt is Timestamp) {
      dt = lastMessageAt.toDate();
    } else if (lastMessageAt is DateTime) {
      dt = lastMessageAt;
    } else {
      return '';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(msgDay).inDays;
    if (diffDays == 0) return DateFormat('HH:mm').format(dt);
    if (diffDays == 1) return 'Yesterday';
    if (diffDays < 7) return DateFormat('EEE').format(dt);
    return DateFormat('MM/dd/yy').format(dt);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD — Scaffold with tabs + bottom nav
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: IndexedStack(
          index: _bottomIndex,
          children: [
            _buildChatsTab(),
            _buildContactsTab(),
            _buildStatusTab(),
            _buildSettingsTab(),
          ],
        ),
        floatingActionButton: _buildFAB(),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BOTTOM NAV — Chats / Contacts / Status / Settings (Telegram style)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildBottomNav() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final items = const [
      _NavItem(icon: Icons.chat_bubble_outline, active: Icons.chat_bubble, label: 'Chats'),
      _NavItem(icon: Icons.contacts_outlined, active: Icons.contacts, label: 'Contacts'),
      _NavItem(icon: Icons.donut_large_outlined, active: Icons.donut_large, label: 'Status'),
      _NavItem(icon: Icons.settings_outlined, active: Icons.settings, label: 'Settings'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF2F2F2F) : const Color(0xFFE4E4E5),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: List.generate(items.length, (i) {
              final item = items[i];
              final selected = i == _bottomIndex;
              final color = selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withOpacity(0.6);

              return Expanded(
                child: InkWell(
                  onTap: () => setState(() => _bottomIndex = i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(selected ? item.active : item.icon, size: 24, color: color),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FAB — Telegram blue circle, changes per tab
  // ═══════════════════════════════════════════════════════════════════════

  Widget? _buildFAB() {
    final theme = Theme.of(context);

    switch (_bottomIndex) {
      case 0:
        return FloatingActionButton(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: Colors.white,
          elevation: 2,
          onPressed: () => _showNewChatOptions(context),
          child: const Icon(Icons.edit_outlined),
        );
      case 1:
        return FloatingActionButton(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: Colors.white,
          elevation: 2,
          onPressed: () => Navigator.pushNamed(context, '/contacts'),
          child: const Icon(Icons.person_add_outlined),
        );
      case 2:
        return FloatingActionButton(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: Colors.white,
          elevation: 2,
          onPressed: () => Navigator.pushNamed(context, '/create_status'),
          child: const Icon(Icons.camera_alt_outlined),
        );
      default:
        return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CHATS TAB — app bar + folder pills + list
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildChatsTab() {
    final theme = Theme.of(context);

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _buildChatsAppBar(),
          _buildFolderPills(),
          Expanded(child: _buildChatsList()),
        ],
      ),
    );
  }

  Widget _buildChatsAppBar() {
    final theme = Theme.of(context);
    final auth = context.watch<LumaAuthProvider>();
    final avatar = auth.profile?['avatar_url'] as String?;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          // Profile avatar on left (Telegram style)
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/profile'),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
              backgroundImage: (avatar != null && avatar.isNotEmpty)
                  ? NetworkImage(avatar)
                  : null,
              child: (avatar == null || avatar.isEmpty)
                  ? Icon(Icons.person,
                      size: 20, color: theme.colorScheme.primary)
                  : null,
            ),
          ),
          const SizedBox(width: 12),

          // Title
          Expanded(
            child: Text(
              'Luma Chat',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),

          // Search
          IconButton(
            icon: Icon(Icons.search, color: theme.colorScheme.onSurface),
            onPressed: () => Navigator.pushNamed(context, '/global_search'),
          ),

          // ⋮ menu
          IconButton(
            icon: Icon(Icons.more_vert, color: theme.colorScheme.onSurface),
            onPressed: () => _showMenu(context),
          ),
        ],
      ),
    );
  }

  // ─── Folder pills row (All Chats / Unread / Groups / Channels / Bots) ───

  Widget _buildFolderPills() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Compute counts
    final chats = context.watch<ChatProvider>().chats;
    final myUid = _myUid;

    final counts = <int, int>{
      0: chats.length,
      1: chats.where((c) {
        final unread =
            (c['unread_counts'] as Map<String, dynamic>?)?[myUid] as num?;
        return (unread?.toInt() ?? 0) > 0;
      }).length,
      2: chats.where((c) => c['type'] == 'group').length,
      3: chats.where((c) => c['type'] == 'channel').length,
      4: chats.where((c) => c['type'] == 'bot' || c['is_bot'] == true).length,
    };

    final folders = [
      _Folder(label: 'All Chats', count: counts[0] ?? 0),
      _Folder(label: 'Unread', count: counts[1] ?? 0),
      _Folder(label: 'Groups', count: counts[2] ?? 0),
      _Folder(label: 'Channels', count: counts[3] ?? 0),
      _Folder(label: 'Bots', count: counts[4] ?? 0),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        controller: _folderScroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: folders.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final folder = folders[i];
          final selected = _folderIndex == i;

          return GestureDetector(
            onTap: () => setState(() => _folderIndex = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected
                    ? (isDark
                        ? const Color(0xFF2A3A52)
                        : const Color(0xFFE8EDF2))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    folder.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: selected
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.colorScheme.primary
                          : (isDark
                              ? const Color(0xFF3A3A3A)
                              : const Color(0xFFDDDDDD)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${folder.count}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? Colors.white
                            : theme.colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Chat list with filtering by folder ───

  Widget _buildChatsList() {
    final theme = Theme.of(context);

    return Consumer<ChatProvider>(
      builder: (context, chatProvider, _) {
        if (chatProvider.isLoading) {
          return Center(
            child: CircularProgressIndicator(color: theme.colorScheme.primary),
          );
        }

        final myUid = _myUid;
        final allChats = chatProvider.chats;

        // Filter by folder
        List<Map<String, dynamic>> visible = allChats.where((c) {
          // Filter archived out of main list
          final archivedFor = List<String>.from(c['archived_for'] ?? []);
          if (archivedFor.contains(myUid)) return false;

          final type = c['type'] as String? ?? 'direct';
          switch (_folderIndex) {
            case 0:
              return true;
            case 1:
              final unread =
                  (c['unread_counts'] as Map<String, dynamic>?)?[myUid] as num?;
              return (unread?.toInt() ?? 0) > 0;
            case 2:
              return type == 'group';
            case 3:
              return type == 'channel';
            case 4:
              return type == 'bot' || c['is_bot'] == true;
          }
          return true;
        }).toList();

        if (visible.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 4, bottom: 96),
          itemCount: visible.length,
          itemBuilder: (context, i) => _buildChatTile(visible[i]),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final labels = [
      ('No chats yet', 'Start a conversation by tapping the pencil.'),
      ('No unread chats', "You're all caught up!"),
      ('No groups', 'Create or join a group to get started.'),
      ('No channels', 'Subscribe to a channel to see it here.'),
      ('No bots', 'Talk to a bot or create your own.'),
    ];
    final t = labels[_folderIndex.clamp(0, labels.length - 1)];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 72,
              color: theme.colorScheme.onSurface.withOpacity(0.15),
            ),
            const SizedBox(height: 16),
            Text(
              t.$1,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              t.$2,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Telegram-exact chat tile ───

  Widget _buildChatTile(Map<String, dynamic> chat) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final chatId = chat['id'] as String? ?? '';
    final chatType = chat['type'] as String? ?? 'direct';
    final isGroup = chatType == 'group';
    final isChannel = chatType == 'channel';
    final isBot = chatType == 'bot' || chat['is_bot'] == true;
    final isDirect = chatType == 'direct';
    final myUid = _myUid;

    String name;
    String? avatar;
    String? otherUserId;

    if (isDirect) {
      final participants = List<String>.from(chat['participants'] ?? []);
      otherUserId = participants.firstWhere((id) => id != myUid, orElse: () => '');
      if (otherUserId.isNotEmpty && !_userCache.containsKey(otherUserId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _fetchOtherUser(otherUserId!);
        });
      }
      final cached = otherUserId.isNotEmpty ? _userCache[otherUserId] : null;
      if (cached != null) {
        name = cached['display_name'] as String? ?? 'User';
        avatar = cached['avatar_url'] as String?;
      } else {
        name = 'Loading…';
        avatar = null;
      }
    } else {
      name = (chat['name'] ?? chat['title'] ?? 'Unknown') as String;
      avatar = chat['avatar_url'] as String?;
    }

    final lastMessage = chat['last_message'] ?? '';
    final unreadCounts = chat['unread_counts'] as Map<String, dynamic>?;
    final unread = (unreadCounts?[myUid] as num?)?.toInt() ?? 0;

    final mutedFor = List<String>.from(chat['muted_for'] ?? []);
    final isMuted = mutedFor.contains(myUid);
    final isBlockedByMe = isDirect &&
        otherUserId != null &&
        otherUserId.isNotEmpty &&
        _myBlockedUsers.contains(otherUserId);
    final isPinned = List<String>.from(chat['pinned_for'] ?? []).contains(myUid);

    final route = isBot ? '/bot' : (isChannel ? '/channel' : '/chat');
    final routeArgs = isBot
        ? {'chatId': chatId, 'botName': name}
        : isChannel
            ? {'channelId': chatId, 'channelName': name}
            : {
                'chatId': chatId,
                'chatName': name,
                'chatAvatar': avatar,
                'isGroup': isGroup,
                'otherUserId': otherUserId,
              };

    // Detect sticker message
    final isSticker = lastMessage.toString().toLowerCase().contains('sticker');
    final previewText = isBlockedByMe
        ? 'Blocked'
        : isSticker
            ? '🌟 Sticker'
            : lastMessage;

    return InkWell(
      onTap: () => Navigator.pushNamed(context, route, arguments: routeArgs),
      onLongPress: () => _showChatContextMenu(
        context: context,
        chat: chat,
        chatId: chatId,
        isDirect: isDirect,
        isGroup: isGroup,
        isChannel: isChannel,
        otherUserId: otherUserId,
        isPinned: isPinned,
        isMuted: isMuted,
        isBlockedByMe: isBlockedByMe,
        name: name,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Avatar with verified badge
            Stack(
              children: [
                CircleAvatar(
                  radius: 27,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
                  backgroundImage: (avatar != null && avatar.isNotEmpty)
                      ? NetworkImage(avatar)
                      : null,
                  onBackgroundImageError: (_, __) {},
                  child: (avatar == null || avatar.isEmpty)
                      ? Icon(
                          isChannel
                              ? Icons.campaign
                              : isGroup
                                  ? Icons.group
                                  : isBot
                                      ? Icons.smart_toy
                                      : Icons.person,
                          color: theme.colorScheme.primary,
                          size: 24,
                        )
                      : null,
                ),
                if (isChannel)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
                          width: 2,
                        ),
                      ),
                      child: const Icon(Icons.check, size: 10, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),

            // Name + message
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (isMuted) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.notifications_off,
                          size: 14,
                          color: theme.colorScheme.onSurface.withOpacity(0.4),
                        ),
                      ],
                      if (isPinned) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.push_pin,
                          size: 14,
                          color: theme.colorScheme.onSurface.withOpacity(0.4),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    previewText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: isBlockedByMe
                          ? theme.colorScheme.error
                          : unread > 0
                              ? theme.colorScheme.onSurface.withOpacity(0.75)
                              : theme.colorScheme.onSurface.withOpacity(0.55),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Time + ticks + unread badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    if (!isDirect && !isChannel) ...[
                      Icon(
                        Icons.done_all,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 2),
                    ],
                    Text(
                      _formatChatTime(chat['last_message_at']),
                      style: TextStyle(
                        fontSize: 12,
                        color: unread > 0
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface.withOpacity(0.4),
                        fontWeight:
                            unread > 0 ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                if (unread > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Text(
                      unread > 999 ? '999+' : '$unread',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FLOATING CONTEXT MENU (Telegram style — appears near finger)
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _showChatContextMenu({
    required BuildContext context,
    required Map<String, dynamic> chat,
    required String chatId,
    required bool isDirect,
    required bool isGroup,
    required bool isChannel,
    required String? otherUserId,
    required bool isPinned,
    required bool isMuted,
    required bool isBlockedByMe,
    required String name,
  }) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final myUid = _myUid;
    final archivedFor = List<String>.from(chat['archived_for'] ?? []);
    final isArchived = archivedFor.contains(myUid);

    final selected = await showMenu<String>(
      context: context,
      position: position,
      color: isDark ? const Color(0xFF2B2B2B) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          value: 'pin',
          child: _menuRow(
            icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin,
            label: isPinned ? 'Unpin' : 'Pin',
            theme: theme,
          ),
        ),
        PopupMenuItem(
          value: 'mute',
          child: _menuRow(
            icon: isMuted
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            label: isMuted ? 'Unmute' : 'Mute',
            theme: theme,
          ),
        ),
        PopupMenuItem(
          value: 'read',
          child: _menuRow(
            icon: Icons.mark_chat_read_outlined,
            label: 'Mark as read',
            theme: theme,
          ),
        ),
        if (isDirect)
          PopupMenuItem(
            value: 'block',
            child: _menuRow(
              icon: isBlockedByMe ? Icons.block_flipped : Icons.block,
              label: isBlockedByMe ? 'Unblock' : 'Block user',
              theme: theme,
              danger: !isBlockedByMe,
            ),
          ),
        PopupMenuItem(
          value: 'archive',
          child: _menuRow(
            icon: isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
            label: isArchived ? 'Unarchive' : 'Archive',
            theme: theme,
          ),
        ),
        PopupMenuItem(
          value: 'clear',
          child: _menuRow(
            icon: Icons.cleaning_services_outlined,
            label: 'Clear history',
            theme: theme,
          ),
        ),
        if (isGroup || isChannel)
          PopupMenuItem(
            value: 'leave',
            child: _menuRow(
              icon: Icons.exit_to_app,
              label: isChannel ? 'Leave channel' : 'Exit group',
              theme: theme,
              danger: true,
            ),
          ),
        PopupMenuItem(
          value: 'delete',
          child: _menuRow(
            icon: Icons.delete_outline,
            label: 'Delete chat',
            theme: theme,
            danger: true,
          ),
        ),
      ],
    );

    if (!mounted || selected == null) return;

    switch (selected) {
      case 'pin':
        await _togglePin(chatId, myUid, !isPinned);
        break;
      case 'mute':
        await _toggleMute(chatId, myUid, !isMuted);
        break;
      case 'read':
        await _markAsRead(chatId, myUid);
        break;
      case 'block':
        if (otherUserId != null && otherUserId.isNotEmpty) {
          await _toggleBlock(otherUserId, !isBlockedByMe);
        }
        break;
      case 'archive':
        await _toggleArchive(chatId, myUid, !isArchived);
        break;
      case 'clear':
        await _confirmClearMessages(chatId, myUid);
        break;
      case 'leave':
        await _confirmExitGroup(chatId, myUid, isChannel);
        break;
      case 'delete':
        await _confirmDeleteChat(chatId, myUid);
        break;
    }
  }

  Widget _menuRow({
    required IconData icon,
    required String label,
    required ThemeData theme,
    bool danger = false,
  }) {
    final color = danger ? theme.colorScheme.error : theme.colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 14),
        Text(label, style: TextStyle(fontSize: 15, color: color)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // FIRESTORE ACTIONS
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _togglePin(String chatId, String myUid, bool pin) async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
        'pinned_for':
            pin ? FieldValue.arrayUnion([myUid]) : FieldValue.arrayRemove([myUid]),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(pin ? 'Pinned' : 'Unpinned')),
        );
      }
    } catch (_) {}
  }

  Future<void> _toggleMute(String chatId, String myUid, bool mute) async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
        'muted_for':
            mute ? FieldValue.arrayUnion([myUid]) : FieldValue.arrayRemove([myUid]),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mute ? 'Muted' : 'Unmuted')),
        );
      }
    } catch (_) {}
  }

  Future<void> _markAsRead(String chatId, String myUid) async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
        'unread_counts.$myUid': 0,
      });
    } catch (_) {}
  }

  Future<void> _toggleBlock(String otherUserId, bool block) async {
    final myUid = _myUid;
    try {
      await FirebaseFirestore.instance.collection('users').doc(myUid).update({
        'blocked_users': block
            ? FieldValue.arrayUnion([otherUserId])
            : FieldValue.arrayRemove([otherUserId]),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(block ? 'Blocked' : 'Unblocked')),
        );
      }
    } catch (_) {}
  }

  Future<void> _toggleArchive(String chatId, String myUid, bool archive) async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
        'archived_for': archive
            ? FieldValue.arrayUnion([myUid])
            : FieldValue.arrayRemove([myUid]),
      });
    } catch (_) {}
  }

  Future<void> _confirmClearMessages(String chatId, String myUid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('Messages will be removed for you only.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
        'cleared_at.$myUid': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _confirmDeleteChat(String chatId, String myUid) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete chat?'),
        content: const Text('This removes the chat from your list.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
        'deleted_for': FieldValue.arrayUnion([myUid]),
      });
    } catch (_) {}
  }

  Future<void> _confirmExitGroup(String chatId, String myUid, bool isChannel) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isChannel ? 'Leave channel?' : 'Exit group?'),
        content: Text(isChannel
            ? 'You will stop receiving posts.'
            : 'You will no longer be a member.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Leave')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
        'participants': FieldValue.arrayRemove([myUid]),
      });
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════════════════════
  // SHEETS — new chat / menu / status / calls
  // ═══════════════════════════════════════════════════════════════════════

  void _showNewChatOptions(BuildContext context) {
    _showFlatSheet(
      context: context,
      children: [
        _sheetTile(
          icon: Icons.person_add_outlined,
          label: 'New Chat',
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/global_search');
          },
        ),
        _sheetTile(
          icon: Icons.group_add_outlined,
          label: 'New Group',
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/create_group');
          },
        ),
        _sheetTile(
          icon: Icons.campaign_outlined,
          label: 'New Channel',
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/create_channel');
          },
        ),
      ],
    );
  }

  void _showMenu(BuildContext context) {
    _showFlatSheet(
      context: context,
      children: [
        _sheetTile(
          icon: Icons.bookmark_outline,
          label: 'Saved Messages',
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/saved_messages');
          },
        ),
        _sheetTile(
          icon: Icons.archive_outlined,
          label: 'Archived Chats',
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/archived_chats');
          },
        ),
        _sheetTile(
          icon: Icons.smart_toy_outlined,
          label: 'Bot Studio',
          onTap: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/bot_creator');
          },
        ),
        _sheetTile(
          icon: Icons.logout,
          label: 'Log Out',
          danger: true,
          onTap: () async {
            Navigator.pop(context);
            await _confirmSignOut(context);
          },
        ),
      ],
    );
  }

  void _showFlatSheet({required BuildContext context, required List<Widget> children}) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.brightness == Brightness.dark
          ? const Color(0xFF1F1F1F)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final theme = Theme.of(context);
    final color = danger ? theme.colorScheme.error : theme.colorScheme.onSurface;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color, fontSize: 15)),
      onTap: onTap,
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to sign in again to use Luma Chat.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Log Out')),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    final auth = Provider.of<LumaAuthProvider>(context, listen: false);
    try {
      await auth.signOut();
    } catch (_) {}
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (r) => false);
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // OTHER TABS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildContactsTab() {
    final theme = Theme.of(context);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  'Contacts',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => Navigator.pushNamed(context, '/global_search'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Contacts — coming soon',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTab() {
    final theme = Theme.of(context);
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  'Status',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Status updates — coming soon',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    final theme = Theme.of(context);
    final auth = context.watch<LumaAuthProvider>();
    final name = auth.profile?['display_name'] ?? 'User';
    final avatar = auth.profile?['avatar_url'] as String?;

    return SafeArea(
      bottom: false,
      child: ListView(
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: CircleAvatar(
              radius: 26,
              backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
              backgroundImage: (avatar != null && avatar.isNotEmpty)
                  ? NetworkImage(avatar)
                  : null,
              child: (avatar == null || avatar.isEmpty)
                  ? Icon(Icons.person, color: theme.colorScheme.primary)
                  : null,
            ),
            title: Text(name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(auth.currentEmail ?? ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/profile'),
          ),
          const Divider(height: 0.5),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Appearance'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/appearance'),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Privacy & Security'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/security'),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/notifications_settings'),
          ),
          const Divider(height: 0.5),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text('Log out',
                style: TextStyle(color: theme.colorScheme.error)),
            onTap: () async {
              final auth = Provider.of<LumaAuthProvider>(context, listen: false);
              await auth.signOut();
              if (!context.mounted) return;
              Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════

class _NavItem {
  final IconData icon;
  final IconData active;
  final String label;
  const _NavItem({required this.icon, required this.active, required this.label});
}

class _Folder {
  final String label;
  final int count;
  const _Folder({required this.label, required this.count});
}
