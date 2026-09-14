import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart' show AuraAuthProvider;

class BotProfileScreen extends StatefulWidget {
  final String botId;
  final String botName;

  const BotProfileScreen({
    super.key,
    required this.botId,
    this.botName = 'Bot',
  });

  @override
  State<BotProfileScreen> createState() => _BotProfileScreenState();
}

class _BotProfileScreenState extends State<BotProfileScreen> {
  Map<String, dynamic>? _botData;
  bool _loading = true;
  bool _initialised = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialised) {
      _initialised = true;
      _loadBot();
    }
  }

  String get _myUid {
    final auth = Provider.of<AuraAuthProvider>(context, listen: false);
    return auth.currentUserId ??
        FirebaseAuth.instance.currentUser?.uid ??
        '';
  }

  Future<void> _loadBot() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('bots')
          .doc(widget.botId)
          .get();
      if (!doc.exists) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      if (mounted) {
        setState(() {
          _botData = doc.data();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('loadBot error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════════════
  void _toast(String m, {bool success = false, bool error = false}) {
    if (!mounted) return;
    final bg = success
        ? const Color(0xFF4ADE80).withOpacity(0.12)
        : error
            ? const Color(0xFFEF4444).withOpacity(0.12)
            : const Color(0xFF14121A);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        backgroundColor: bg,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _copyToken() async {
    final token = _botData?['token'] as String?;
    if (token == null || token.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: token));
    _toast('Token copied ✓', success: true);
  }

  Future<void> _copyBaseUrl() async {
    final token = _botData?['token'] as String?;
    if (token == null || token.isEmpty) return;
    // Match web: <origin>/api/bot/<token>
    // In Flutter, we don't have `origin`, so we use your backend base.
    // Replace with your actual API host if different.
    const apiHost = 'https://aurachat-85f54.web.app'; // ← change if different
    final url = '$apiHost/api/bot/$token';
    await Clipboard.setData(ClipboardData(text: url));
    _toast('Base URL copied ✓', success: true);
  }

  Future<void> _shareBot() async {
    final url =
        'https://aurachat-85f54.web.app/bot_profile.html?id=${widget.botId}';
    await Clipboard.setData(ClipboardData(text: url));
    _toast('Link copied ✓', success: true);
  }

  void _startBotChat() {
    _toast('Bot must be running on a server');
  }

  void _editBot() {
    if (_botData == null) return;
    Navigator.pushNamed(
      context,
      '/bot_creator',
      arguments: {
        'editBotId': widget.botId,
        'editUsername': _botData?['username'],
      },
    );
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
            center: Alignment(-0.6, -0.6),
            radius: 1.4,
            colors: [
              Color(0x1FA855F7),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFA855F7),
                        ),
                      )
                    : _botData == null
                        ? _build404()
                        : _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F).withOpacity(0.85),
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
          const SizedBox(width: 4),
          const Text(
            'Bot Profile',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _build404() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined,
                size: 64, color: Colors.white.withOpacity(0.15)),
            const SizedBox(height: 16),
            Text(
              'Bot not found',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final data = _botData!;
    final isOwner = data['owner_id'] == _myUid;
    final name = data['name'] as String? ?? 'Bot';
    final username = data['username'] as String? ?? 'bot';
    final avatarUrl = data['avatar_url'] as String?;
    final about = data['about'] as String? ?? 'No description yet.';
    final subscribers = data['subscribers'] as int? ?? 0;

    // Commands — fallback matches web's ['/start', '/help']
    final commandsRaw = data['commands'];
    List<String> commands = ['/start', '/help'];
    if (commandsRaw is List && commandsRaw.isNotEmpty) {
      commands = commandsRaw.map((e) => e.toString()).toList();
    }

    final token = data['token'] as String? ?? '';
    const apiHost = 'https://aurachat-85f54.web.app';
    final apiBase = '$apiHost/api/bot/$token';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── HERO ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
            child: Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFFA855F7), Color(0xFF7E22CE)],
                    ),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFA855F7).withOpacity(0.4),
                        blurRadius: 40,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: (avatarUrl != null && avatarUrl.isNotEmpty)
                        ? Image.network(
                            avatarUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.smart_toy,
                              color: Colors.white,
                              size: 44,
                            ),
                          )
                        : const Icon(
                            Icons.smart_toy,
                            color: Colors.white,
                            size: 44,
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.02,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '@$username',
                  style: const TextStyle(
                    color: Color(0xFFC084FC),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFA855F7), Color(0xFF7E22CE)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFA855F7).withOpacity(0.4),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.smart_toy, color: Colors.white, size: 12),
                      SizedBox(width: 6),
                      Text(
                        'BOT',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ─── STATS ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: _statBox(
                    value: subscribers.toString(),
                    label: 'Subscribers',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _statBox(
                    value: commands.length.toString(),
                    label: 'Commands',
                  ),
                ),
              ],
            ),
          ),

          // ─── ABOUT ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.05)),
                bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionLabel('About'),
                const SizedBox(height: 8),
                Text(
                  about,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),

          // ─── COMMANDS ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionLabel('Commands'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: commands
                      .map((c) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFA855F7)
                                  .withOpacity(0.12),
                              border: Border.all(
                                color: const Color(0xFFA855F7)
                                    .withOpacity(0.2),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              c,
                              style: const TextStyle(
                                color: Color(0xFFC084FC),
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),

          // ─── ACTIONS ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              children: [
                _actionButton(
                  icon: Icons.chat_bubble,
                  label: 'Send Message',
                  primary: true,
                  onTap: _startBotChat,
                ),
                const SizedBox(height: 8),
                _actionButton(
                  icon: Icons.share,
                  label: 'Share Bot',
                  onTap: _shareBot,
                ),
                if (isOwner) ...[
                  const SizedBox(height: 8),
                  _actionButton(
                    icon: Icons.edit,
                    label: 'Edit in BotCreator',
                    onTap: _editBot,
                  ),
                ],
              ],
            ),
          ),

          // ─── TOKEN (owner only) ───────────────────────────────
          if (isOwner && token.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel(
                    'API Token — private',
                    icon: Icons.vpn_key,
                  ),
                  const SizedBox(height: 8),
                  _tokenBox(
                    text: token,
                    onCopy: _copyToken,
                  ),
                  const SizedBox(height: 16),
                  const _SectionLabel(
                    'Your API Base URL',
                    icon: Icons.link,
                  ),
                  const SizedBox(height: 8),
                  _tokenBox(
                    text: apiBase,
                    onCopy: _copyBaseUrl,
                  ),
                  const SizedBox(height: 12),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12.5,
                        height: 1.55,
                        fontFamily: 'Inter',
                      ),
                      children: const [
                        TextSpan(text: 'Use this token with '),
                        TextSpan(
                          text: 'aura-bot-api',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFFC084FC),
                            backgroundColor: Color(0x1FA855F7),
                          ),
                        ),
                        TextSpan(text: ' (Node.js) or '),
                        TextSpan(
                          text: 'aura-bot',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFFC084FC),
                            backgroundColor: Color(0x1FA855F7),
                          ),
                        ),
                        TextSpan(
                            text:
                                ' (Python). Host your bot on any server — AURA never runs bots for you.'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _statBox({required String value, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFA855F7).withOpacity(0.05),
        border: Border.all(
          color: const Color(0xFFA855F7).withOpacity(0.15),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFC084FC),
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.3),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
          decoration: BoxDecoration(
            gradient: primary
                ? const LinearGradient(
                    colors: [Color(0xFFA855F7), Color(0xFF7E22CE)],
                  )
                : null,
            color: primary ? null : const Color(0xFFA855F7).withOpacity(0.08),
            border: primary
                ? null
                : Border.all(
                    color: const Color(0xFFA855F7).withOpacity(0.2),
                  ),
            borderRadius: BorderRadius.circular(11),
            boxShadow: primary
                ? [
                    BoxShadow(
                      color: const Color(0xFFA855F7).withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tokenBox({
    required String text,
    required VoidCallback onCopy,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        border: Border.all(
          color: const Color(0xFFA855F7).withOpacity(0.25),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: const TextStyle(
                color: Color(0xFFC084FC),
                fontSize: 11.5,
                fontFamily: 'monospace',
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onCopy,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFA855F7).withOpacity(0.15),
                  border: Border.all(
                    color: const Color(0xFFA855F7).withOpacity(0.3),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.copy,
                    color: Color(0xFFC084FC), size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Reusable section label
// ═══════════════════════════════════════════════════════════════
class _SectionLabel extends StatelessWidget {
  final String text;
  final IconData? icon;

  const _SectionLabel(this.text, {this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: const Color(0xFFC084FC), size: 12),
          const SizedBox(width: 6),
        ],
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Color(0xFFC084FC),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}
