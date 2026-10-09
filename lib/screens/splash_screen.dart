import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<double> _scale;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );

    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
      ),
    );

    _controller.forward();
    _selfNavigateIfNeeded();
  }

  Future<void> _selfNavigateIfNeeded() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted || _hasNavigated) return;
    _hasNavigated = true;

    final prefs = await SharedPreferences.getInstance();
    final pendingPhone = prefs.getString('pending_phone');
    final pendingEmail = prefs.getString('pending_email');
    final currentUser = FirebaseAuth.instance.currentUser;

    // Signed-in Firebase user → main or setup
    if (currentUser != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        final data = doc.data();
        final hasUsername = (data?['username'] as String?)?.trim().isNotEmpty ?? false;
        final hasName = (data?['display_name'] as String?)?.trim().isNotEmpty ?? false;

        if (doc.exists && hasUsername && hasName) {
          Navigator.pushReplacementNamed(context, '/main');
        } else {
          Navigator.pushReplacementNamed(context, '/setup_profile');
        }
      } catch (_) {
        Navigator.pushReplacementNamed(context, '/setup_profile');
      }
      return;
    }

    // No user — check pending flow
    if (pendingPhone == null) {
      Navigator.pushReplacementNamed(context, '/phone_entry');
      return;
    }
    Navigator.pushReplacementNamed(context, '/email_verification');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Telegram-style: solid bg, centered logo, app name, subtle tagline
    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF212121)
          : const Color(0xFFFFFFFF),
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Logo (flat blue rounded square — Telegram style) ──
                ScaleTransition(
                  scale: _scale,
                  child: FadeTransition(
                    opacity: _fade,
                    child: Container(
                      width: 112,
                      height: 112,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.chat_bubble_rounded,
                          color: Colors.white,
                          size: 56,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── App name ──
                FadeTransition(
                  opacity: _fade,
                  child: Text(
                    'Luma Chat',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // ── Tagline (Telegram style — small, muted) ──
                FadeTransition(
                  opacity: _fade,
                  child: Text(
                    'Fast. Simple. Secure.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                      letterSpacing: 0.2,
                    ),
                  ),
                ),

                const SizedBox(height: 64),

                // ── Subtle loading bar (much softer than a spinner) ──
                FadeTransition(
                  opacity: _fade,
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        theme.colorScheme.primary.withOpacity(0.7),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
