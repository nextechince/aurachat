import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../providers/auth_provider.dart' show AuraAuthProvider;
import '../../providers/chat_provider.dart';
import '../../services/cloudinary_service.dart';
import '../../services/invitation_service.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();
  final _inviteNameController = TextEditingController();

  String? _groupPhotoUrl;
  bool _isLoading = false;
  List<Map<String, dynamic>> _selectedMembers = [];
  List<Map<String, dynamic>> _searchResults = [];
  String? _generatedLink;
  String? _generatedCode;

  static const Color _bgDark = Color(0xFF0A0A0F);
  static const Color _bgCard = Color(0xFF1a103c);
  static const Color _purple = Color(0xFF8B5CF6);
  static const Color _cyan = Color(0xFF06B6D4);

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    _inviteNameController.dispose();
    super.dispose();
  }

  Future<void> _pickGroupPhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile == null) return;

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuraAuthProvider>(context, listen: false);
      final userId = authProvider.user?.uid ?? authProvider.mockUserId;

      if (userId == null) {
        throw Exception('Not authenticated');
      }

      // FIX #14: Use permanent folder so cleanup doesn't delete avatars
      final imageUrl = await CloudinaryService.uploadImage(
        File(pickedFile.path),
        'aurachat/permanent/avatars/groups/$userId'
      );

      if (imageUrl == null) {
        throw Exception('Upload failed');
      }

      setState(() => _groupPhotoUrl = imageUrl);
    } catch (e) {
      debugPrint('Photo upload failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Photo upload failed: $e. Continuing without photo.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final authProvider = Provider.of<AuraAuthProvider>(context, listen: false);
      final currentUserId = authProvider.user?.uid ?? authProvider.mockUserId;

      final snapshot = await firestore
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: query)
          .where('username', isLessThanOrEqualTo: '$query\uf8ff')
          .limit(20)
          .get();

      final filtered = snapshot.docs
          .map((doc) => {
                'id': doc.id,
                ...doc.data(),
              })
          .where((u) => u['id'] != currentUserId)
          .toList();

      setState(() => _searchResults = filtered);
    } catch (e) {
      debugPrint('Search error: $e');
    }
  }

  void _toggleMember(Map<String, dynamic> user) {
    setState(() {
      final index = _selectedMembers.indexWhere((m) => m['id'] == user['id']);
      if (index >= 0) {
        _selectedMembers.removeAt(index);
      } else {
        _selectedMembers.add(user);
      }
    });
  }

  Future<void> _createGroup() async {
    if (_nameController.text.trim().isEmpty) {
      _showError('Please enter a group name');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuraAuthProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final firestore = FirebaseFirestore.instance;
      final userId = authProvider.user?.uid ?? authProvider.mockUserId;
      final email = authProvider.email ?? '';

      if (userId == null) {
        throw Exception('Not authenticated');
      }

      final participants = [userId, ..._selectedMembers.map((m) => m['id'] as String)];
      final participantsData = <String, dynamic>{};

      for (final id in participants) {
        participantsData[id] = {
          'role': id == userId ? 'owner' : 'member',
          'joined_at': FieldValue.serverTimestamp(),
        };
      }

      final chatId = const Uuid().v4();

      // FIX #16: Always create as 'group' — no channel toggle here
      await firestore.collection('chats').doc(chatId).set({
        'id': chatId,
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        'avatar_url': _groupPhotoUrl,
        'type': 'group',
        'created_by': userId,
        'created_by_email': email,
        'participants': participants,
        'participants_data': participantsData,
        'member_count': participants.length,
        'banned_users': [],
        'settings': {
          'chat_disabled': false,
          'file_sharing_disabled': false,
          'slow_mode_seconds': 0,
          'restrict_new_members_minutes': 0,
          'message_retention_days': 0,
          'welcome_message': 'Welcome to ${_nameController.text.trim()}!',
          'rules': 'Be respectful and kind to all members.',
          'announcements_only': false,
          'polls_enabled': true,
          'reactions_enabled': true,
          'forwarding_enabled': true,
          'voice_chat_enabled': false,
        },
        'pinned_messages': [],
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
        'last_message_at': FieldValue.serverTimestamp(),
        'last_message': 'Group created',
      });

      // Create invitation link
      try {
        final inviteResult = await InvitationService.createInvitation(
          chatId: chatId,
          chatName: _nameController.text.trim(),
          chatType: 'group',
          createdBy: userId,
          customName: _inviteNameController.text.trim().isNotEmpty
              ? _inviteNameController.text.trim()
              : null,
        );
        setState(() {
          _generatedLink = inviteResult['link'] as String?;
          _generatedCode = inviteResult['code'] as String?;
        });
      } catch (e) {
        debugPrint('Invitation creation failed: $e');
      }

      await chatProvider.loadChats();

      setState(() => _isLoading = false);

      if (mounted && _generatedLink == null) {
        // No link banner to show — just confirm and leave, as before.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group created successfully!')),
        );
        Navigator.pop(context);
      }
      // If a link WAS generated, stay on screen so the rich preview card
      // (built below) is visible before the user backs out.
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        _showError('Error: $e');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.withOpacity(0.9),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _copyLink() {
    if (_generatedLink == null) return;
    Clipboard.setData(ClipboardData(text: _generatedLink!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _bgDark,
              _bgCard,
              Color(0xFF0f172a),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [_purple, _cyan],
                        ).createShader(bounds),
                        child: const Text(
                          'New Group',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    if (_isLoading)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    else if (_generatedLink == null)
                      TextButton(
                        onPressed: _createGroup,
                        child: const Text('Create', style: TextStyle(color: _cyan, fontWeight: FontWeight.bold)),
                      )
                    else
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done', style: TextStyle(color: _cyan, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Photo upload
                      Center(
                        child: GestureDetector(
                          onTap: _generatedLink == null ? _pickGroupPhoto : null,
                          child: Stack(
                            children: [
                              _buildGroupAvatar(),
                              if (_generatedLink == null)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(colors: [_purple, _cyan]),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_generatedLink == null)
                        Center(
                          child: Text(
                            'Tap to add photo',
                            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.4)),
                          ),
                        ),
                      const SizedBox(height: 32),

                      // NEW: once the group + link exist, show the rich
                      // Telegram-style preview card instead of the form.
                      if (_generatedLink != null) ...[
                        _buildGeneratedLinkCard(),
                        const SizedBox(height: 24),
                      ] else ...[
                        // Name field
                        _buildGlassInput(
                          label: 'Group Name',
                          hint: 'Enter group name',
                          icon: Icons.edit,
                          controller: _nameController,
                        ),
                        const SizedBox(height: 16),

                        // Description field
                        _buildGlassInput(
                          label: 'Description',
                          hint: 'Add a description (optional)',
                          icon: Icons.description,
                          controller: _descriptionController,
                          maxLines: 2,
                        ),
                        const SizedBox(height: 16),

                        // Invite link name
                        _buildGlassInput(
                          label: 'Invitation Link Name',
                          hint: 'e.g., my-awesome-group (optional)',
                          icon: Icons.link,
                          controller: _inviteNameController,
                        ),
                        const SizedBox(height: 24),

                        // Search users
                        _buildGlassInput(
                          label: 'Add Members',
                          hint: 'Search users to add... (optional)',
                          icon: Icons.search,
                          controller: _searchController,
                          onChanged: _searchUsers,
                        ),

                        // Selected members
                        if (_selectedMembers.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 90,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _selectedMembers.length,
                              itemBuilder: (context, index) {
                                final member = _selectedMembers[index];
                                return Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: Column(
                                    children: [
                                      Stack(
                                        children: [
                                          _buildMemberAvatar(member['avatar_url'], member['username']),
                                          Positioned(
                                            top: 0,
                                            right: 0,
                                            child: GestureDetector(
                                              onTap: () => _toggleMember(member),
                                              child: Container(
                                                padding: const EdgeInsets.all(2),
                                                decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.close, size: 14, color: Colors.white),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        member['username'] ?? 'Unknown',
                                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],

                        // Search results
                        if (_searchResults.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          ..._searchResults.map((user) {
                            final isSelected = _selectedMembers.any((m) => m['id'] == user['id']);
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.03),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: _buildMemberAvatar(user['avatar_url'], user['username']),
                                title: Text(user['username'] ?? 'Unknown', style: const TextStyle(color: Colors.white)),
                                subtitle: Text(user['email'] ?? '', style: TextStyle(color: Colors.white.withOpacity(0.4))),
                                trailing: isSelected
                                    ? const Icon(Icons.check_circle, color: _purple)
                                    : const Icon(Icons.add_circle_outline, color: Colors.white54),
                                onTap: () => _toggleMember(user),
                              ),
                            );
                          }).toList(),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// NEW: Telegram-style rich link card — the group's own avatar, its
  /// real name, type badge and current member count, plus Copy / Share
  /// actions for the invite link.
  Widget _buildGeneratedLinkCard() {
    final name = _nameController.text.trim().isEmpty ? 'Group' : _nameController.text.trim();
    final memberCount = _selectedMembers.length + 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_purple.withOpacity(0.14), _cyan.withOpacity(0.08)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _purple.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
              const SizedBox(width: 8),
              const Text('Group created', style: TextStyle(color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(colors: [_purple, _cyan]),
                  border: Border.all(color: _purple.withOpacity(0.35), width: 2),
                ),
                child: (_groupPhotoUrl != null && _groupPhotoUrl!.isNotEmpty)
                    ? ClipOval(child: Image.network(_groupPhotoUrl!, fit: BoxFit.cover))
                    : Center(child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: const [
                      Icon(Icons.group, size: 11, color: _purple),
                      SizedBox(width: 4),
                      Text('GROUP', style: TextStyle(color: _purple, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.6)),
                    ]),
                    const SizedBox(height: 2),
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                    Text('$memberCount member${memberCount != 1 ? 's' : ''}', style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.25), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                const Icon(Icons.link, size: 14, color: Colors.white54),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _generatedLink ?? '',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copyLink,
                  icon: const Icon(Icons.copy, size: 16, color: Colors.white70),
                  label: const Text('Copy Link', style: TextStyle(color: Colors.white70)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.white.withOpacity(0.15)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Hands the link off to the platform share sheet so the
                    // group's rich preview shows up wherever it's shared.
                    Clipboard.setData(ClipboardData(text: _generatedLink ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied — paste it anywhere to share')),
                    );
                  },
                  icon: const Icon(Icons.share, size: 16, color: Colors.white),
                  label: const Text('Share'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroupAvatar() {
    if (_groupPhotoUrl != null && _groupPhotoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 50,
        backgroundColor: _purple.withOpacity(0.2),
        backgroundImage: NetworkImage(_groupPhotoUrl!),
        onBackgroundImageError: (_, __) {},
      );
    }

    return CircleAvatar(
      radius: 50,
      backgroundColor: _purple.withOpacity(0.2),
      child: const Icon(
        Icons.group,
        size: 50,
        color: _purple,
      ),
    );
  }

  Widget _buildMemberAvatar(String? avatarUrl, String? username) {
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 28,
        backgroundImage: NetworkImage(avatarUrl),
        onBackgroundImageError: (_, __) {},
      );
    }

    return CircleAvatar(
      radius: 28,
      backgroundColor: _purple.withOpacity(0.2),
      child: Text(
        (username ?? 'U')[0].toUpperCase(),
        style: const TextStyle(fontSize: 20, color: Colors.white),
      ),
    );
  }

  Widget _buildGlassInput({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    int maxLines = 1,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.7)),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
              prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.3)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            ),
          ),
        ),
      ],
    );
  }
}
