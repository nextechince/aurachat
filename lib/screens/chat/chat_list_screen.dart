import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../providers/auth_provider.dart' show AuraAuthProvider;
import '../../providers/chat_provider.dart';
import '../../services/notification_service.dart';
import '../../utils/verified_badge.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  Timer? _refreshTimer;

  /// ─────────────────────────────────────────────────────────
  /// USER CACHE — same pattern as chats.html's `userCache = {}`
  /// Prevents tiles from flashing "Unknown" every rebuild
  /// ─────────────────────────────────────────────────────────
  final Map<String, Map<String, dynamic>> _userCache = {};
  final Set<String> _userFetchInFlight = {};

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Fetch a user once, cache forever
  Future<Map<String, dynamic>?> _fetchUser(String userId) async {
    if (_userCache.containsKey(userId)) return _userCache[userId];
    if (_userFetchInFlight.contains(userId)) return null; // wait for in-flight

    _userFetchInFlight.add(userId);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        // Normalize — same fallback chain as chats.html
        final normalized = {
          'uid': userId,
          'username': data['username'] ?? 'Unknown',
          'display_name': data['display_name'] ??
              data['username'] ??
              data['name'] ??
              'Unknown',
          'avatar_url': data['avatar_url'],
          'email': data['email'],
          'is_bot': data['is_bot'] == true,
          'about': data['about'] ?? '',
          'is_online': data['is_online'] == true,
          'last_seen': data['last_seen'],
        };
        _userCache[userId] = normalized;
        _userFetchInFlight.remove(userId);
        return normalized;
      }
    } catch (e) {
      debugPrint('fetchUser error ($userId): $e');
    }
    _userFetchInFlight.remove(userId);
    final fallback = {
      'uid': userId,
      'username': 'Unknown',
      'display_name': 'Unknown',
      'avatar_url': null,
      'email': null,
      'is_bot': false,
      'about': '',
      'is_online': false,
      'last_seen': null,
    };
    _userCache[userId] = fallback;
    return fallback;
  }

  /// Bulk-fetch users and setState when done (so tiles rebuild with real data)
  void _prefetchUsers(List<String> userIds, String currentUserId) async {
    final missing = userIds
        .where((id) => id != currentUserId && !_userCache.containsKey(id))
        .toSet()
        .toList();
    if (missing.isEmpty) return;

    // Firestore whereIn max 10 per query — batch
    for (var i = 0; i < missing.length; i += 10) {
      final batch = missing.sublist(
        i,
        i + 10 > missing.length ? missing.length : i + 10,
      );
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        for (final doc in snap.docs) {
          if (!doc.exists) continue;
          final data = doc.data();
          _userCache[doc.id] = {
            'uid': doc.id,
            'username': data['username'] ?? 'Unknown',
            'display_name': data['display_name'] ??
                data['username'] ??
                data['name'] ??
                'Unknown',
            'avatar_url': data['avatar_url'],
            'email': data['email'],
            'is_bot': data['is_bot'] == true,
            'about': data['about'] ?? '',
            'is_online': data['is_online'] == true,
            'last_seen': data['last_seen'],
          };
        }
      } catch (e) {
        debugPrint('bulk fetch error: $e');
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuraAuthProvider>(context);
    final userId = authProvider.user?.uid ?? authProvider.mockUserId;

    if (userId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: userId)
            .orderBy('last_message_at', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final chats = snapshot.data!.docs;
          if (chats.isEmpty) {
            return _buildEmptyState();
          }

          // Collect all "other user" IDs from direct chats
          final otherUserIds = <String>{};
          for (final doc in chats) {
            final chat = doc.data() as Map<String, dynamic>;
            final type = chat['type'] ?? 'direct';
            if (type == 'direct') {
              final parts = List<String>.from(chat['participants'] ?? []);
              for (final p in parts) {
                if (p != userId) otherUserIds.add(p);
              }
            }
          }

          // Prefetch users in background (triggers setState when ready)
          _prefetchUsers(otherUserIds.toList(), userId);

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chat = chats[index].data() as Map<String, dynamic>;
              chat['id'] = chats[index].id;

              final type = chat['type'] ?? 'direct';
              final isGroupOrChannel = ['group', 'channel', 'bot'].contains(type);
              final lastMessage = chat['last_message'] ?? '';
              final lastMessageType = chat['last_message_type'] ?? 'text';

              // Robust timestamp
              DateTime? lastMessageAt;
              if (chat['last_message_at'] != null) {
                final val = chat['last_message_at'];
                if (val is DateTime) lastMessageAt = val;
                else if (val is Timestamp) lastMessageAt = val.toDate();
                else if (val is String) lastMessageAt = DateTime.tryParse(val);
              }

              // Unread — matches chats.html's `unread_counts.{uid}`
              final unreadCounts = chat['unread_counts'] as Map<String, dynamic>?;
              final unreadCount = unreadCounts?[userId] ?? 0;

              // Pinned — matches chats.html's `pinned_for` array
              final pinnedFor = List<String>.from(chat['pinned_for'] ?? []);
              final isPinned = pinnedFor.contains(userId);

              if (isGroupOrChannel) {
                return _buildGroupOrChannelTile(
                  context,
                  chat,
                  lastMessage,
                  lastMessageType,
                  lastMessageAt,
                  unreadCount,
                  isPinned,
                );
              } else {
                return _buildDirectChatTile(
                  context,
                  chat,
                  lastMessage,
                  lastMessageType,
                  lastMessageAt,
                  unreadCount,
                  isPinned,
                  userId,
                );
              }
            },
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // GROUP / CHANNEL / BOT TILE
  // ═══════════════════════════════════════════════════════════
  Widget _buildGroupOrChannelTile(
    BuildContext context,
    Map<String, dynamic> chat,
    String lastMessage,
    String lastMessageType,
    DateTime? lastMessageAt,
    int unreadCount,
    bool isPinned,
  ) {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final name = chat['name'] ?? chat['title'] ?? 'Unknown';
    final avatarUrl = chat['avatar_url'] as String?;
    final type = chat['type'] as String? ?? 'group';
    final createdByEmail = chat['created_by_email'] as String?;

    return Slidable(
      key: ValueKey(chat['id']),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => chatProvider.archiveChat(chat['id']),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            icon: Icons.archive,
            label: 'Archive',
          ),
          SlidableAction(
            onPressed: (_) => _showDeleteDialog(context, chat['id']),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: 'Delete',
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onLongPress: () => _showChatOptions(context, chat, true),
        leading: Stack(
          children: [
            _buildAvatar(avatarUrl, name, type == 'channel'),
            if (isPinned)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(0xFF8B5CF6),
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.push_pin, size: 10, color: Colors.white),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: VerifiedUsername(
                username: name,
                email: createdByEmail,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                badgeSize: 14,
                spacing: 4,
              ),
            ),
            if (lastMessageAt != null)
              Text(
                _formatChatListTime(lastMessageAt),
                style: TextStyle(
                  color: unreadCount > 0
                      ? const Color(0xFF8B5CF6)
                      : Colors.white.withOpacity(0.4),
                  fontSize: 12,
                ),
              ),
          ],
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                _getMessagePreview(lastMessage, lastMessageType),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: unreadCount > 0
                      ? Colors.white.withOpacity(0.8)
                      : Colors.white.withOpacity(0.5),
                  fontSize: 13,
                  fontWeight: unreadCount > 0
                      ? FontWeight.w500
                      : FontWeight.normal,
                ),
              ),
            ),
            if (unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        onTap: () {
          if (type == 'channel') {
            Navigator.pushNamed(
              context,
              '/channel',
              arguments: {
                'channelId': chat['id'],
                'channelName': name,
              },
            );
          } else if (type == 'bot') {
            Navigator.pushNamed(
              context,
              '/bot',
              arguments: {
                'chatId': chat['id'],
                'botName': name,
              },
            );
          } else {
            Navigator.pushNamed(
              context,
              '/chat',
              arguments: {
                'chatId': chat['id'],
                'chatName': name,
                'isGroup': true,
              },
            );
          }
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // DIRECT CHAT TILE — no more FutureBuilder
  // ═══════════════════════════════════════════════════════════
  Widget _buildDirectChatTile(
    BuildContext context,
    Map<String, dynamic> chat,
    String lastMessage,
    String lastMessageType,
    DateTime? lastMessageAt,
    int unreadCount,
    bool isPinned,
    String userId,
  ) {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    final participants = List<String>.from(chat['participants'] ?? []);
    final otherUserId = participants.firstWhere(
      (id) => id != userId,
      orElse: () => '',
    );
    if (otherUserId.isEmpty) return const SizedBox.shrink();

    // Use cache — if not yet loaded, show placeholder, then prefetch triggers setState
    final cached = _userCache[otherUserId];
    if (cached == null) {
      _fetchUser(otherUserId); // kick off fetch; setState happens in prefetch
      return _buildLoadingTile(context, chat['id']);
    }

    final displayName = cached['display_name'] as String? ?? 'Unknown';
    final avatarUrl = cached['avatar_url'] as String?;
    final email = cached['email'] as String?;
    final isOnline = cached['is_online'] as bool? ?? false;
    final isBot = cached['is_bot'] as bool? ?? false;

    return Slidable(
      key: ValueKey(chat['id']),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => chatProvider.archiveChat(chat['id']),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            icon: Icons.archive,
            label: 'Archive',
          ),
          SlidableAction(
            onPressed: (_) => _showDeleteDialog(context, chat['id']),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: 'Delete',
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onLongPress: () =>
            _showDirectChatOptions(context, chat['id'], displayName),
        leading: Stack(
          children: [
            _buildAvatar(avatarUrl, displayName, false, isBot: isBot),
            if (isOnline && !isBot)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF0A0A0F),
                      width: 2,
                    ),
                  ),
                ),
              ),
            if (isPinned)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(0xFF8B5CF6),
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Icons.push_pin, size: 10, color: Colors.white),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: VerifiedUsername(
                username: displayName,
                email: email,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                badgeSize: 14,
                spacing: 4,
              ),
            ),
            if (lastMessageAt != null)
              Text(
                _formatChatListTime(lastMessageAt),
                style: TextStyle(
                  color: unreadCount > 0
                      ? const Color(0xFF8B5CF6)
                      : Colors.white.withOpacity(0.4),
                  fontSize: 12,
                ),
              ),
          ],
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                _getMessagePreview(lastMessage, lastMessageType),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: unreadCount > 0
                      ? Colors.white.withOpacity(0.8)
                      : Colors.white.withOpacity(0.5),
                  fontSize: 13,
                  fontWeight: unreadCount > 0
                      ? FontWeight.w500
                      : FontWeight.normal,
                ),
              ),
            ),
            if (unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        onTap: () {
          Navigator.pushNamed(
            context,
            '/chat',
            arguments: {
              'chatId': chat['id'],
              'chatName': displayName,
              'isGroup': false,
              'otherUserId': otherUserId,
            },
          );
        },
      ),
    );
  }

  // Placeholder tile while user data loads — prevents blank rows
  Widget _buildLoadingTile(BuildContext context, String chatId) {
    return ListTile(
      key: ValueKey(chatId),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const CircleAvatar(
        radius: 26,
        backgroundColor: Color(0xFF1a103c),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
          ),
        ),
      ),
      title: Container(
        height: 12,
        width: 120,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      subtitle: Container(
        height: 10,
        width: 80,
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // AVATAR — with proper fallback
  // ═══════════════════════════════════════════════════════════
  Widget _buildAvatar(
    String? url,
    String name,
    bool isChannel, {
    bool isBot = false,
  }) {
    // Placeholder: initial letter or icon
    Widget fallback;
    if (isBot) {
      fallback = Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Color(0x4D8B5CF6), Color(0x4006B6D4)],
          ),
        ),
        child: const Center(
          child: Icon(Icons.smart_toy, color: Color(0xFF8B5CF6), size: 24),
        ),
      );
    } else if (isChannel) {
      fallback = const Center(
        child: Icon(Icons.campaign, color: Color(0xFF8B5CF6), size: 24),
      );
    } else {
      final initial = (name.isNotEmpty ? name[0] : '?').toUpperCase();
      fallback = Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 26,
      backgroundColor: const Color(0xFF1a103c),
      child: ClipOval(
        child: (url != null && url.isNotEmpty)
            ? Image.network(
                url,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                // Error → show fallback
                errorBuilder: (context, error, stackTrace) => fallback,
                // Loading → subtle shimmer
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    width: 52,
                    height: 52,
                    color: const Color(0xFF1a103c),
                  );
                },
              )
            : fallback,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // HELPERS
  // ═══════════════════════════════════════════════════════════
  String _getMessagePreview(String message, String type) {
    switch (type) {
      case 'image':
        return '📷 Photo';
      case 'video':
        return '🎥 Video';
      case 'audio':
        return '🎤 Voice message';
      case 'file':
        return '📎 File';
      case 'location':
        return '📍 Location';
      case 'contact':
        return '👤 Contact';
      case 'poll':
        return '📊 Poll';
      default:
        return message.isEmpty ? 'No messages yet' : message;
    }
  }

  String _formatChatListTime(DateTime? dateTime) {
    if (dateTime == null) return '';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate =
        DateTime(dateTime.year, dateTime.month, dateTime.day);
    final diffDays = today.difference(messageDate).inDays;

    if (diffDays == 0) {
      final diffMinutes = now.difference(dateTime).inMinutes;
      if (diffMinutes < 1) return 'Now';
      if (diffMinutes < 60) return '${diffMinutes}m';
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } else if (diffDays == 1) {
      return 'Yesterday';
    } else if (diffDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dateTime.weekday - 1];
    } else if (dateTime.year == now.year) {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dateTime.month - 1]} ${dateTime.day}';
    } else {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[dateTime.month - 1]} ${dateTime.day}, ${dateTime.year}';
    }
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Failed to load chats',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Colors.white.withOpacity(0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a conversation!',
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // BOTTOM SHEETS + DIALOGS (kept identical to your original)
  // ═══════════════════════════════════════════════════════════
  void _showChatOptions(
      BuildContext context, Map<String, dynamic> chat, bool isGroup) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a103c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
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
            ListTile(
              leading: const Icon(Icons.push_pin, color: Color(0xFF8B5CF6)),
              title:
                  const Text('Pin Chat', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Provider.of<ChatProvider>(context, listen: false)
                    .togglePinChat(chat['id']);
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive, color: Colors.blue),
              title: const Text('Archive',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Provider.of<ChatProvider>(context, listen: false)
                    .archiveChat(chat['id']);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Chat',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteDialog(context, chat['id']);
              },
            ),
            if (isGroup)
              ListTile(
                leading:
                    const Icon(Icons.exit_to_app, color: Colors.orange),
                title: const Text('Leave Group',
                    style: TextStyle(color: Colors.orange)),
                onTap: () {
                  Navigator.pop(context);
                  _showLeaveDialog(context, chat['id']);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showDirectChatOptions(
      BuildContext context, String chatId, String userName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a103c),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
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
            ListTile(
              leading: const Icon(Icons.push_pin, color: Color(0xFF8B5CF6)),
              title:
                  const Text('Pin Chat', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Provider.of<ChatProvider>(context, listen: false)
                    .togglePinChat(chatId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive, color: Colors.blue),
              title: const Text('Archive',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                Provider.of<ChatProvider>(context, listen: false)
                    .archiveChat(chatId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Chat',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showDeleteDialog(context, chatId);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Colors.orange),
              title: const Text('Block User',
                  style: TextStyle(color: Colors.orange)),
              onTap: () {
                Navigator.pop(context);
                _showBlockDialog(context, chatId, userName);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, String chatId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a103c),
        title:
            const Text('Delete Chat?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will delete the chat from your list. Messages will still be visible to other participants.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Provider.of<ChatProvider>(context, listen: false)
                  .deleteChat(chatId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showLeaveDialog(BuildContext context, String chatId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a103c),
        title:
            const Text('Leave Group?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'You will no longer receive messages from this group.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Provider.of<ChatProvider>(context, listen: false)
                  .leaveChat(chatId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _showBlockDialog(
      BuildContext context, String chatId, String userName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1a103c),
        title: Text('Block $userName?',
            style: const TextStyle(color: Colors.white)),
        content: Text(
          'You will no longer receive messages from $userName.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: Colors.white.withOpacity(0.5))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: implement block
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }
}
