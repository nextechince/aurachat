import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart' show AuraAuthProvider;

/// Saved Messages — full rewrite to match the web version's functionality:
/// search, type filters, notes (create/edit), copy, forward, delete,
/// clear-all, and opening media/location/contact previews.
class SavedMessagesScreen extends StatefulWidget {
  const SavedMessagesScreen({super.key});

  @override
  State<SavedMessagesScreen> createState() => _SavedMessagesScreenState();
}

class _SavedMessagesScreenState extends State<SavedMessagesScreen> {
  static const Color _bg = Color(0xFF0A0A0F);
  static const Color _card = Color(0xFF1a103c);
  static const Color _purple = Color(0xFF8B5CF6);
  static const Color _cyan = Color(0xFF06B6D4);
  static const Color _amber = Color(0xFFFBBF24);

  final _searchController = TextEditingController();
  final _noteController = TextEditingController();

  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _filtered = [];
  String _filter = 'all';
  String _query = '';
  bool _loading = true;
  String? _userId;

  final List<Map<String, dynamic>> _filters = const [
    {'key': 'all', 'label': 'All', 'icon': Icons.layers},
    {'key': 'note', 'label': 'Notes', 'icon': Icons.edit_note},
    {'key': 'text', 'label': 'Text', 'icon': Icons.short_text},
    {'key': 'image', 'label': 'Photos', 'icon': Icons.image},
    {'key': 'video', 'label': 'Videos', 'icon': Icons.videocam},
    {'key': 'file', 'label': 'Files', 'icon': Icons.insert_drive_file},
    {'key': 'audio', 'label': 'Voice', 'icon': Icons.mic},
    {'key': 'location', 'label': 'Locations', 'icon': Icons.location_on},
    {'key': 'contact', 'label': 'Contacts', 'icon': Icons.contact_page},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _init() {
    final auth = Provider.of<AuraAuthProvider>(context, listen: false);
    _userId = auth.user?.uid ?? auth.mockUserId;
    if (_userId == null) {
      setState(() => _loading = false);
      return;
    }
    FirebaseFirestore.instance
        .collection('users')
        .doc(_userId)
        .collection('saved')
        .orderBy('saved_at', descending: true)
        .limit(500)
        .snapshots()
        .listen((snap) {
      _items = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      _applyFilters();
      if (mounted) setState(() => _loading = false);
    }, onError: (e) {
      debugPrint('Saved messages load error: $e');
      if (mounted) setState(() => _loading = false);
    });
  }

  void _applyFilters() {
    _filtered = _items.where((item) {
      final type = (item['media_type'] ?? 'text') as String;
      if (_filter != 'all' && type != _filter) return false;
      if (_query.isNotEmpty) {
        final haystack = [
          item['text'] ?? '',
          item['from_sender'] ?? '',
          item['from_chat'] ?? '',
          item['file_name'] ?? '',
        ].join(' ').toLowerCase();
        if (!haystack.contains(_query.toLowerCase())) return false;
      }
      return true;
    }).toList();
    if (mounted) setState(() {});
  }

  String _formatTime(dynamic ts) {
    if (ts == null) return '';
    final d = ts is Timestamp ? ts.toDate() : DateTime.now();
    return DateFormat('HH:mm').format(d);
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return '';
    final d = ts is Timestamp ? ts.toDate() : DateTime.now();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yest = today.subtract(const Duration(days: 1));
    final md = DateTime(d.year, d.month, d.day);
    if (md == today) return 'Today';
    if (md == yest) return 'Yesterday';
    return DateFormat('MMM d, yyyy').format(d);
  }

  Future<void> _openNewNote() async {
    _noteController.clear();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _noteDialog(title: 'New Note', controller: _noteController),
    );
    if (saved == true && _noteController.text.trim().isNotEmpty && _userId != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(_userId).collection('saved').add({
          'text': _noteController.text.trim(),
          'media_type': 'note',
          'saved_at': FieldValue.serverTimestamp(),
        });
        _toast('Note saved');
      } catch (e) {
        _toast('Failed: $e');
      }
    }
  }

  Future<void> _openEditNote(Map<String, dynamic> item) async {
    _noteController.text = item['text'] ?? '';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _noteDialog(title: 'Edit Note', controller: _noteController),
    );
    if (saved == true && _noteController.text.trim().isNotEmpty && _userId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_userId)
            .collection('saved')
            .doc(item['id'])
            .update({'text': _noteController.text.trim(), 'updated_at': FieldValue.serverTimestamp()});
        _toast('Note updated');
      } catch (e) {
        _toast('Failed: $e');
      }
    }
  }

  Widget _noteDialog({required String title, required TextEditingController controller}) {
    return AlertDialog(
      backgroundColor: _card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      content: TextField(
        controller: controller,
        maxLines: 5,
        autofocus: true,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Type your note, thought, or link...',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5))),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Save', style: TextStyle(color: _purple)),
        ),
      ],
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _copyItem(Map<String, dynamic> item) {
    final type = item['media_type'] ?? 'text';
    String text;
    if (type == 'location') {
      text = 'https://www.google.com/maps/search/?api=1&query=${item['location_lat']},${item['location_lng']}';
    } else {
      text = (item['text'] ?? '') as String;
    }
    if (text.isEmpty) {
      _toast('Nothing to copy');
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    _toast('Copied');
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete saved item?', style: TextStyle(color: Colors.white)),
        content: Text('This action cannot be undone.', style: TextStyle(color: Colors.white.withOpacity(0.5))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true && _userId != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(_userId).collection('saved').doc(item['id']).delete();
        _toast('Deleted');
      } catch (e) {
        _toast('Failed: $e');
      }
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear all saved?', style: TextStyle(color: Colors.white)),
        content: Text('All saved messages will be permanently deleted.', style: TextStyle(color: Colors.white.withOpacity(0.5))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.5)))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete All', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true && _userId != null) {
      try {
        final snap = await FirebaseFirestore.instance.collection('users').doc(_userId).collection('saved').get();
        final batch = FirebaseFirestore.instance.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
        _toast('All cleared');
      } catch (e) {
        _toast('Failed: $e');
      }
    }
  }

  Future<void> _openForward(Map<String, dynamic> item) async {
    if (_userId == null) return;
    final chatsSnap = await FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: _userId)
        .get();
    if (!mounted) return;
    final targetChatId = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(alignment: Alignment.centerLeft, child: Text('Forward to', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: chatsSnap.docs.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text('No chats found', style: TextStyle(color: Colors.white.withOpacity(0.3))),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: chatsSnap.docs.length,
                      itemBuilder: (context, i) {
                        final doc = chatsSnap.docs[i];
                        final data = doc.data();
                        final isGroup = data['type'] == 'group';
                        final isChannel = data['type'] == 'channel';
                        String name = (data['name'] ?? data['title'] ?? 'Chat') as String;
                        if (!isGroup && !isChannel) {
                          final participants = List<String>.from(data['participants'] ?? []);
                          final otherId = participants.firstWhere((id) => id != _userId, orElse: () => '');
                          final pData = data['participants_data']?[otherId];
                          if (pData != null) name = pData['username'] ?? pData['name'] ?? name;
                        }
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _purple.withOpacity(0.2),
                            child: Icon(isGroup ? Icons.group : isChannel ? Icons.campaign : Icons.person, color: _purple),
                          ),
                          title: Text(name, style: const TextStyle(color: Colors.white)),
                          onTap: () => Navigator.pop(context, doc.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
    if (targetChatId != null) {
      await _forwardTo(item, targetChatId);
    }
  }

  Future<void> _forwardTo(Map<String, dynamic> item, String targetChatId) async {
    try {
      final ref = FirebaseFirestore.instance.collection('chats').doc(targetChatId).collection('messages').doc();
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(_userId).get();
      final myName = userDoc.data()?['display_name'] ?? userDoc.data()?['username'] ?? 'You';
      final type = item['media_type'] ?? 'text';
      await ref.set({
        'id': ref.id,
        'sender_id': _userId,
        'type': type == 'note' ? 'text' : type,
        'content': item['text'],
        'media_url': item['media_url'],
        'file_name': item['file_name'],
        'file_size': item['file_size'],
        'location_lat': item['location_lat'],
        'location_lng': item['location_lng'],
        'location_label': item['location_label'],
        'contact': item['contact'],
        'poll': item['poll'],
        'forwarded_from': item['from_sender'] ?? 'Saved Messages',
        'created_at': FieldValue.serverTimestamp(),
        'is_read': false, 'is_edited': false, 'deleted_for_everyone': false,
        'deleted_for': [], 'reactions': {},
      });
      await FirebaseFirestore.instance.collection('chats').doc(targetChatId).update({
        'last_message': '📤 Forwarded from Saved',
        'last_message_at': FieldValue.serverTimestamp(),
      });
      _toast('Forwarded');
    } catch (e) {
      _toast('Forward failed: $e');
    }
  }

  Future<void> _openLocation(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) _toast('Could not open map');
    } catch (e) {
      _toast('Could not open map');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [_purple, _cyan])),
              child: const Icon(Icons.bookmark, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Saved Messages', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                  Text('${_items.length} item${_items.length != 1 ? 's' : ''}', style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.add, color: _purple), onPressed: _openNewNote),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white70),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: _card,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                builder: (context) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(2))),
                      const SizedBox(height: 8),
                      ListTile(
                        leading: const Icon(Icons.edit_note, color: _amber),
                        title: const Text('New Note', style: TextStyle(color: Colors.white)),
                        onTap: () { Navigator.pop(context); _openNewNote(); },
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete_forever, color: Colors.red),
                        title: const Text('Clear All Saved', style: TextStyle(color: Colors.red)),
                        onTap: () { Navigator.pop(context); _clearAll(); },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Container(
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(18)),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                onChanged: (v) { _query = v; _applyFilters(); },
                decoration: InputDecoration(
                  hintText: 'Search saved messages...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
                  prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.35), size: 18),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                          onPressed: () { _searchController.clear(); _query = ''; _applyFilters(); },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _filters.length,
              itemBuilder: (context, i) {
                final f = _filters[i];
                final selected = _filter == f['key'];
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () { setState(() => _filter = f['key']); _applyFilters(); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? _purple.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: selected ? _purple.withOpacity(0.5) : Colors.white.withOpacity(0.06)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(f['icon'], size: 12, color: selected ? Colors.white : Colors.white54),
                          const SizedBox(width: 6),
                          Text(f['label'], style: TextStyle(fontSize: 12, color: selected ? Colors.white : Colors.white54, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _purple))
                : _items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(30),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.bookmark_border, size: 54, color: _purple.withOpacity(0.3)),
                              const SizedBox(height: 16),
                              Text('No saved messages yet', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 15, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              Text(
                                'Long-press any message in a chat and tap Save, or tap + above to create a note.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _filtered.isEmpty
                        ? Center(child: Text('No matches', style: TextStyle(color: Colors.white.withOpacity(0.3))))
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                            itemCount: _filtered.length,
                            itemBuilder: (context, index) {
                              final item = _filtered[index];
                              final showDate = index == 0 || _formatDate(item['saved_at']) != _formatDate(_filtered[index - 1]['saved_at']);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (showDate)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      child: Center(
                                        child: Text(_formatDate(item['saved_at']), style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 11)),
                                      ),
                                    ),
                                  _buildSavedItem(item),
                                  const SizedBox(height: 6),
                                ],
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedItem(Map<String, dynamic> item) {
    final type = (item['media_type'] ?? 'text') as String;
    final isNote = type == 'note';

    Widget content;
    switch (type) {
      case 'note':
      case 'text':
        content = Text(item['text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4));
        break;
      case 'image':
        content = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(imageUrl: item['media_url'] ?? '', height: 160, fit: BoxFit.cover, width: double.infinity),
        );
        break;
      case 'video':
        content = Container(
          height: 140,
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
          child: const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 40)),
        );
        break;
      case 'file':
        content = Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: _purple.withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.insert_drive_file, color: _purple, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Text(item['file_name'] ?? 'File', style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis)),
        ]);
        break;
      case 'audio':
        content = Row(children: const [
          Icon(Icons.mic, color: _purple, size: 18),
          SizedBox(width: 10),
          Text('Voice message', style: TextStyle(color: Colors.white, fontSize: 12)),
        ]);
        break;
      case 'location':
        content = GestureDetector(
          onTap: () => _openLocation((item['location_lat'] ?? 0).toDouble(), (item['location_lng'] ?? 0).toDouble()),
          child: Row(children: [
            const Icon(Icons.location_on, color: _purple, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(item['location_label'] ?? 'Shared location', style: const TextStyle(color: Colors.white, fontSize: 12), overflow: TextOverflow.ellipsis)),
          ]),
        );
        break;
      case 'contact':
        final c = Map<String, dynamic>.from(item['contact'] ?? {});
        content = Row(children: [
          CircleAvatar(radius: 16, backgroundColor: _purple.withOpacity(0.3), backgroundImage: c['avatar_url'] != null ? NetworkImage(c['avatar_url']) : null, child: c['avatar_url'] == null ? Text((c['display_name'] ?? 'U')[0].toString().toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12)) : null),
          const SizedBox(width: 10),
          Expanded(child: Text(c['display_name'] ?? c['username'] ?? 'Contact', style: const TextStyle(color: Colors.white, fontSize: 12))),
        ]);
        break;
      default:
        content = Text(item['text'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13));
    }

    return Container(
      decoration: BoxDecoration(
        color: isNote ? _amber.withOpacity(0.05) : Colors.white.withOpacity(0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 20, height: 20,
                decoration: BoxDecoration(color: (isNote ? _amber : _purple).withOpacity(0.15), shape: BoxShape.circle),
                child: Icon(isNote ? Icons.edit : Icons.bookmark, size: 10, color: isNote ? _amber : _purple),
              ),
              const SizedBox(width: 8),
              if (isNote)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: _amber.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                  child: const Text('NOTE', style: TextStyle(color: _amber, fontSize: 9, fontWeight: FontWeight.bold)),
                )
              else ...[
                if (item['from_sender'] != null)
                  Flexible(child: Text(item['from_sender'], style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10.5, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                if (item['from_chat'] != null) ...[
                  const SizedBox(width: 4),
                  Flexible(child: Text('· ${item['from_chat']}', style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10), overflow: TextOverflow.ellipsis)),
                ],
              ],
              const Spacer(),
              Text(_formatTime(item['saved_at']), style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10)),
            ],
          ),
          const SizedBox(height: 8),
          content,
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06)))),
            child: Row(
              children: [
                if (isNote)
                  _actionBtn(Icons.edit, 'Edit', () => _openEditNote(item)),
                _actionBtn(Icons.copy, 'Copy', () => _copyItem(item)),
                _actionBtn(Icons.share, 'Forward', () => _openForward(item)),
                _actionBtn(Icons.delete, 'Delete', () => _deleteItem(item), color: Colors.red),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap, {Color color = _purple}) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.6))),
            ],
          ),
        ),
      ),
    );
  }
}
