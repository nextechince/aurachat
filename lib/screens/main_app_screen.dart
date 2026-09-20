import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart' show AuraAuthProvider;
import '../../providers/chat_provider.dart';
import '../../screens/status/status_screen.dart';
import '../../screens/calls/call_screen.dart';
import '../../services/call_service.dart';
import '../../services/app_localizations.dart';

class MainAppScreen extends StatefulWidget {
  const MainAppScreen({super.key});

  @override
  State<MainAppScreen> createState() => _MainAppScreenState();
}

class _MainAppScreenState extends State<MainAppScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentIndex = 0;

  final Map<String, Map<String, dynamic>> _userCache = {};
  final Set<String> _inFlight = {};

  // NEW: per-user block cache so tiles/long-press can show Block vs Unblock
  // without a fresh network round trip on every open.
  List<String> _myBlockedUsers = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() => _currentIndex = _tabController.index);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider =
          Provider.of<AuraAuthProvider>(context, listen: false);
      final chatProvider =
          Provider.of<ChatProvider>(context, listen: false);

      if (authProvider.mockUserId != null) {
        chatProvider.setMockUser(authProvider.mockUserId!);
      } else {
        chatProvider.loadChats();
      }

      _listenToMyBlockedUsers();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _myUid {
    final auth = Provider.of<AuraAuthProvider>(context, listen: false);
    final fromProvider = auth.currentUserId ?? auth.mockUserId;
    if (fromProvider != null && fromProvider.isNotEmpty) {
      return fromProvider;
    }
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }

  void _listenToMyBlockedUsers() {
    final uid = _myUid;
    if (uid.isEmpty) return;
    FirebaseFirestore.instance.collection('users').doc(uid).snapshots().listen((doc) {
      if (!mounted || !doc.exists) return;
      setState(() {
        _myBlockedUsers = List<String>.from(doc.data()?['blocked_users'] ?? []);
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
    } catch (e) {
      debugPrint('fetchOtherUser error ($uid): $e');
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

  // NEW: format last_message_at into a real time/date label instead of
  // a hardcoded "Now".
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
    return DateFormat('MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverAppBar(
                expandedHeight: 120,
                floating: true,
                pinned: true,
                elevation: 0,
                backgroundColor: const Color(0xFF0A0A0F),
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(left: 20, bottom: 60),
                  title: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
                    ).createShader(bounds),
                    child: const Text(
                      'AURA',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF8B5CF6).withOpacity(0.1),
                          const Color(0xFF06B6D4).withOpacity(0.05),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.search, color: Colors.white70),
                    onPressed: () =>
                        Navigator.pushNamed(context, '/global_search'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white70),
                    onPressed: () => _showMenu(context),
                  ),
                ],
                bottom: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.white.withOpacity(0.4),
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 14,
                  ),
                  tabs: [
                    Tab(text: AppLocalizations.get('chats')),
                    Tab(text: AppLocalizations.get('status')),
                    Tab(text: AppLocalizations.get('calls')),
                  ],
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildChatsTab(),
              _buildStatusTab(),
              _buildCallsTab(),
            ],
          ),
        ),
        floatingActionButton: _buildFAB(),
      ),
    );
  }

  Widget? _buildFAB() {
    switch (_currentIndex) {
      case 0:
        return _glowFAB(
          icon: Icons.chat_bubble,
          onPressed: () => _showNewChatOptions(context),
        );
      case 1:
        return _glowFAB(
          icon: Icons.camera_alt,
          onPressed: () => _showAddStatusOptions(context),
        );
      case 2:
        return _glowFAB(
          icon: Icons.add_call,
          onPressed: () => _showNewCallOptions(context),
        );
      default:
        return null;
    }
  }

  Widget _glowFAB({required IconData icon, required VoidCallback onPressed}) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: onPressed,
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Icon(icon, color: Colors.white),
      ),
    );
  }

  // ==================== CHATS TAB ====================

  Widget _buildChatsTab() {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        if (chatProvider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Color(0xFF8B5CF6)),
            ),
          );
        }

        final myUid = _myUid;
        // NEW: split out archived chats so the main list only shows active
        // ones, while still surfacing an entry point to reach the archive.
        final allChats = chatProvider.chats;
        final archivedChats = allChats.where((c) {
          final archivedFor = List<String>.from(c['archived_for'] ?? []);
          return archivedFor.contains(myUid);
        }).toList();
        final visibleChats = allChats.where((c) {
          final archivedFor = List<String>.from(c['archived_for'] ?? []);
          return !archivedFor.contains(myUid);
        }).toList();

        if (allChats.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 80,
                  color: Colors.white.withOpacity(0.1),
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.get('no_chats'),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.get('start_conversation'),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.2),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8),
          itemCount: visibleChats.length + (archivedChats.isNotEmpty ? 1 : 0),
          itemBuilder: (context, index) {
            if (archivedChats.isNotEmpty && index == 0) {
              return _buildArchivedRow(archivedChats.length);
            }
            final chatIndex = archivedChats.isNotEmpty ? index - 1 : index;
            return _buildChatTile(visibleChats[chatIndex]);
          },
        );
      },
    );
  }

  Widget _buildArchivedRow(int count) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.archive, color: Colors.white70, size: 20),
        ),
        title: const Text('Archived Chats', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(12)),
          child: Text('$count', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        onTap: _openArchivedChats,
      ),
    );
  }

  void _openArchivedChats() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ArchivedChatsScreen(
          myUid: _myUid,
          buildChatTile: _buildChatTile,
        ),
      ),
    );
  }

  // ==================== CHAT TILE ====================

  Widget _buildChatTile(Map<String, dynamic> chat) {
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
      otherUserId = participants.firstWhere(
        (id) => id != myUid,
        orElse: () => '',
      );

      if (otherUserId.isNotEmpty && !_userCache.containsKey(otherUserId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _fetchOtherUser(otherUserId!);
        });
      }

      final cached =
          otherUserId.isNotEmpty ? _userCache[otherUserId] : null;

      if (cached != null) {
        name = cached['display_name'] as String? ?? 'User';
        avatar = cached['avatar_url'] as String?;
      } else {
        name = 'Loading...';
        avatar = null;
      }
    } else {
      name = (chat['name'] ?? chat['title'] ?? 'Unknown') as String;
      avatar = chat['avatar_url'] as String?;
    }

    final lastMessage = chat['last_message'] ?? '';

    final unreadCounts = chat['unread_counts'] as Map<String, dynamic>?;
    final unread = (unreadCounts?[myUid] as num?)?.toInt() ?? 0;

    // NEW: mute + block/archive state for this tile.
    final mutedFor = List<String>.from(chat['muted_for'] ?? []);
    final isMuted = mutedFor.contains(myUid);
    final isBlockedByMe = isDirect && otherUserId != null && otherUserId.isNotEmpty && _myBlockedUsers.contains(otherUserId);

    String route;
    Map<String, dynamic> routeArgs;
    if (isBot) {
      route = '/bot';
      routeArgs = {'chatId': chatId, 'botName': name};
    } else if (isChannel) {
      route = '/channel';
      routeArgs = {'channelId': chatId, 'channelName': name};
    } else {
      route = '/chat';
      routeArgs = {
        'chatId': chatId,
        'chatName': name,
        'chatAvatar': avatar,
        'isGroup': isGroup,
        'otherUserId': otherUserId,
      };
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8B5CF6).withOpacity(0.2),
                blurRadius: 10,
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFF1a103c),
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
                    color: const Color(0xFF8B5CF6),
                    size: 22,
                  )
                : null,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isChannel) _pill('CHANNEL', const Color(0xFF8B5CF6)),
            if (isGroup) _pill('GROUP', const Color(0xFF06B6D4)),
            if (isBot) _pill('BOT', const Color(0xFF8B5CF6)),
            if (isMuted) ...[
              const SizedBox(width: 6),
              Icon(Icons.notifications_off, size: 14, color: Colors.white.withOpacity(0.35)),
            ],
          ],
        ),
        subtitle: Text(
          isBlockedByMe ? 'Blocked' : lastMessage,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isBlockedByMe
                ? Colors.red.withOpacity(0.7)
                : unread > 0
                    ? Colors.white.withOpacity(0.75)
                    : Colors.white.withOpacity(0.4),
            fontSize: 13,
            fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              // NEW: real formatted time instead of a hardcoded "Now".
              _formatChatTime(chat['last_message_at']),
              style: TextStyle(
                color: unread > 0
                    ? const Color(0xFF8B5CF6)
                    : Colors.white.withOpacity(0.3),
                fontSize: 11,
                fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (unread > 0) ...[
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withOpacity(0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        onTap: () {
          Navigator.pushNamed(context, route, arguments: routeArgs);
        },
        // NEW: long-press opens the glassmorphism chat options sheet.
        onLongPress: () => _showChatOptions(
          chat: chat,
          chatId: chatId,
          isGroup: isGroup,
          isChannel: isChannel,
          isDirect: isDirect,
          otherUserId: otherUserId,
          name: name,
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusTab() => const StatusScreen();

  Widget _buildCallsTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.phone_outlined,
            size: 80,
            color: Colors.white.withOpacity(0.1),
          ),
          const SizedBox(height: 16),
          Text(
            'Tap + to start a call',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== CHAT LONG-PRESS OPTIONS (NEW) ====================

  Widget _glassSheet({required Widget child}) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1a103c).withOpacity(0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
          ),
          child: child,
        ),
      ),
    );
  }

  void _showChatOptions({
    required Map<String, dynamic> chat,
    required String chatId,
    required bool isGroup,
    required bool isChannel,
    required bool isDirect,
    required String? otherUserId,
    required String name,
  }) {
    final myUid = _myUid;
    final archivedFor = List<String>.from(chat['archived_for'] ?? []);
    final isArchived = archivedFor.contains(myUid);
    final mutedFor = List<String>.from(chat['muted_for'] ?? []);
    final isMuted = mutedFor.contains(myUid);
    final isBlockedByMe = isDirect && otherUserId != null && otherUserId.isNotEmpty && _myBlockedUsers.contains(otherUserId);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _glassSheet(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 8),

                _optionTile(
                  icon: isMuted ? Icons.notifications_active : Icons.notifications_off,
                  color: const Color(0xFFFBBF24),
                  label: isMuted ? 'Unmute' : 'Mute',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _toggleMute(chatId, myUid, !isMuted);
                  },
                ),

                if (isDirect) ...[
                  _optionTile(
                    icon: isBlockedByMe ? Icons.block_flipped : Icons.block,
                    color: Colors.red,
                    label: isBlockedByMe ? 'Unblock' : 'Block',
                    danger: !isBlockedByMe,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      if (otherUserId != null && otherUserId.isNotEmpty) {
                        _toggleBlock(otherUserId, !isBlockedByMe);
                      }
                    },
                  ),
                ],

                if (isGroup || isChannel)
                  _optionTile(
                    icon: Icons.exit_to_app,
                    color: Colors.red,
                    label: isChannel ? 'Leave Channel' : 'Exit Group',
                    danger: true,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _confirmExitGroup(chatId, myUid, isChannel);
                    },
                  ),

                _optionTile(
                  icon: isArchived ? Icons.unarchive : Icons.archive,
                  color: const Color(0xFF06B6D4),
                  label: isArchived ? 'Unarchive' : 'Archive',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _toggleArchive(chatId, myUid, !isArchived);
                  },
                ),

                _optionTile(
                  icon: Icons.cleaning_services,
                  color: const Color(0xFF8B5CF6),
                  label: 'Clear Messages',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _confirmClearMessages(chatId, myUid);
                  },
                ),

                _optionTile(
                  icon: Icons.delete_outline,
                  color: Colors.red,
                  label: 'Delete Chat',
                  danger: true,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _confirmDeleteChat(chatId, myUid);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _optionTile({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color.withOpacity(0.18), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: danger ? Colors.red : Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleMute(String chatId, String myUid, bool mute) async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
        'muted_for': mute ? FieldValue.arrayUnion([myUid]) : FieldValue.arrayRemove([myUid]),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mute ? 'Muted' : 'Unmuted')),
        );
      }
    } catch (e) {
      debugPrint('Toggle mute error: $e');
    }
  }

  Future<void> _toggleBlock(String otherUserId, bool block) async {
    final myUid = _myUid;
    try {
      await FirebaseFirestore.instance.collection('users').doc(myUid).update({
        'blocked_users': block ? FieldValue.arrayUnion([otherUserId]) : FieldValue.arrayRemove([otherUserId]),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(block ? 'Blocked' : 'Unblocked')),
        );
      }
    } catch (e) {
      debugPrint('Toggle block error: $e');
    }
  }

  Future<void> _toggleArchive(String chatId, String myUid, bool archive) async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
        'archived_for': archive ? FieldValue.arrayUnion([myUid]) : FieldValue.arrayRemove([myUid]),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(archive ? 'Chat archived' : 'Chat unarchived')),
        );
      }
    } catch (e) {
      debugPrint('Toggle archive error: $e');
    }
  }

  void _confirmClearMessages(String chatId, String myUid) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a103c),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear messages?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This clears the message history for you only. The other participant(s) keep their copy.',
          style: TextStyle(color: Colors.white.withOpacity(0.6)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                // Written as cleared_at.{uid}; the chat screen filters out
                // any message created at/before this timestamp for this user.
                await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
                  'cleared_at.$myUid': FieldValue.serverTimestamp(),
                });
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Messages cleared')));
              } catch (e) {
                debugPrint('Clear messages error: $e');
              }
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteChat(String chatId, String myUid) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a103c),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete chat?', style: TextStyle(color: Colors.white)),
        content: Text('This removes the chat from your list.', style: TextStyle(color: Colors.white.withOpacity(0.6))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
                  'deleted_for': FieldValue.arrayUnion([myUid]),
                });
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat deleted')));
              } catch (e) {
                debugPrint('Delete chat error: $e');
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmExitGroup(String chatId, String myUid, bool isChannel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a103c),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isChannel ? 'Leave channel?' : 'Exit group?', style: const TextStyle(color: Colors.white)),
        content: Text(
          isChannel ? 'You will stop receiving posts from this channel.' : 'You will no longer be a member of this group.',
          style: TextStyle(color: Colors.white.withOpacity(0.6)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
                  'participants': FieldValue.arrayRemove([myUid]),
                  'participants_data.$myUid': FieldValue.delete(),
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(isChannel ? 'Left channel' : 'Left group')),
                  );
                }
              } catch (e) {
                debugPrint('Exit group error: $e');
              }
            },
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ==================== NEW CHAT SHEET ====================

  void _showNewChatOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a103c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _handle(),
            const SizedBox(height: 20),
            _buildOptionTile(
              icon: Icons.person_add,
              label: AppLocalizations.get('new_chat'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/global_search');
              },
            ),
            _buildOptionTile(
              icon: Icons.group_add,
              label: AppLocalizations.get('new_group'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/create_group');
              },
            ),
            _buildOptionTile(
              icon: Icons.campaign,
              label: AppLocalizations.get('new_channel'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/create_channel');
              },
            ),
          ],
        ),
      ),
    );
  }

  // ==================== STATUS SHEET ====================

  void _showAddStatusOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a103c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _handle(),
            const SizedBox(height: 20),
            _buildOptionTile(
              icon: Icons.camera_alt,
              label: AppLocalizations.get('camera'),
              onTap: () => Navigator.pop(context),
            ),
            _buildOptionTile(
              icon: Icons.photo_library,
              label: AppLocalizations.get('gallery'),
              onTap: () => Navigator.pop(context),
            ),
            _buildOptionTile(
              icon: Icons.text_fields,
              label: AppLocalizations.get('text_status'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== NEW CALL SHEET ====================

  void _showNewCallOptions(BuildContext context) {
    final channelName = CallService.generateChannelName();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a103c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _handle(),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                children: [
                  Text(
                    'Share this code to join',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    channelName,
                    style: const TextStyle(
                      color: Color(0xFF8B5CF6),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildOptionTile(
              icon: Icons.person_search,
              label: 'Call from Contacts',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CallScreen.pick()),
                );
              },
            ),
            _buildOptionTile(
              icon: Icons.phone,
              label: 'Start Voice Call',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallScreen.active(
                      channelName: channelName,
                      isVideoCall: false,
                      targetUserId: 'unknown',
                      targetUserName: 'Unknown',
                    ),
                  ),
                );
              },
            ),
            _buildOptionTile(
              icon: Icons.videocam,
              label: 'Start Video Call',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallScreen.active(
                      channelName: channelName,
                      isVideoCall: true,
                      targetUserId: 'unknown',
                      targetUserName: 'Unknown',
                    ),
                  ),
                );
              },
            ),
            _buildOptionTile(
              icon: Icons.dialpad,
              label: 'Join by Code',
              onTap: () {
                Navigator.pop(context);
                _showCallCodeDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCallCodeDialog(BuildContext context) {
    final codeController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a103c),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Join Call', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: codeController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter channel name...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final code = codeController.text.trim();
              if (code.isNotEmpty) {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CallScreen.active(
                      channelName: code,
                      isVideoCall: true,
                      targetUserId: 'unknown',
                      targetUserName: 'Unknown',
                    ),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
            ),
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  // ==================== ⋮ MENU ====================

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a103c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _handle(),
              const SizedBox(height: 18),
              _menuTile(
                icon: Icons.bookmark,
                iconColor: const Color(0xFF8B5CF6),
                label: 'Saved Messages',
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.pushNamed(context, '/saved_messages');
                },
              ),
              _menuTile(
                icon: Icons.archive,
                iconColor: const Color(0xFF06B6D4),
                label: 'Archived Chats',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _openArchivedChats();
                },
              ),
              _menuTile(
                icon: Icons.settings,
                iconColor: const Color(0xFF8B5CF6),
                label: 'Settings',
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.pushNamed(context, '/settings');
                },
              ),
              _menuTile(
                icon: Icons.person,
                iconColor: const Color(0xFF06B6D4),
                label: 'Profile',
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.pushNamed(context, '/profile');
                },
              ),
              _menuTile(
                icon: Icons.smart_toy,
                iconColor: const Color(0xFF8B5CF6),
                label: 'BotCreator',
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.pushNamed(context, '/bot_creator');
                },
              ),
              _menuTile(
                icon: Icons.logout,
                iconColor: const Color(0xFFEF4444),
                label: 'Log Out',
                labelColor: const Color(0xFFEF4444),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _confirmSignOut(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
    Color? labelColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: labelColor ?? Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a103c),
        title: const Text('Log out?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'You will need to sign in again to use AURA Chat.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withOpacity(0.5)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;

    final authProvider =
        Provider.of<AuraAuthProvider>(context, listen: false);
    try {
      await authProvider.signOut();
    } catch (_) {}

    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  // ==================== SHARED UI ====================

  Widget _handle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = const Color(0xFF8B5CF6),
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.2),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }
}

/// NEW: Archived Chats screen — reuses MainAppScreen's own chat-tile
/// builder (passed in) so the look, long-press options (including
/// Unarchive) and navigation all stay identical to the main list.
class _ArchivedChatsScreen extends StatelessWidget {
  final String myUid;
  final Widget Function(Map<String, dynamic> chat) buildChatTile;

  const _ArchivedChatsScreen({required this.myUid, required this.buildChatTile});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0F),
        elevation: 0,
        title: const Text('Archived Chats', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white70),
      ),
      body: Consumer<ChatProvider>(
        builder: (context, chatProvider, child) {
          final archived = chatProvider.chats.where((c) {
            final archivedFor = List<String>.from(c['archived_for'] ?? []);
            return archivedFor.contains(myUid);
          }).toList();

          if (archived.isEmpty) {
            return Center(
              child: Text('No archived chats', style: TextStyle(color: Colors.white.withOpacity(0.3))),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(top: 8),
            itemCount: archived.length,
            itemBuilder: (context, index) => buildChatTile(archived[index]),
          );
        },
      ),
    );
  }
}
