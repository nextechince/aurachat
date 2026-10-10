import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_ios/local_auth_ios.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'themes/app_theme.dart';
import 'providers/auth_provider.dart' show LumaAuthProvider;
import 'providers/chat_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/bot_provider.dart';
import 'providers/moderation_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding/terms_screen.dart';
import 'screens/auth/phone_entry_screen.dart';
import 'screens/auth/email_verification_screen.dart';
import 'screens/auth/setup_profile_screen.dart';
import 'screens/main_app_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/bot/bot_store_screen.dart';
import 'screens/bot/bot_creator_screen.dart';
import 'screens/settings/privacy_settings_screen.dart';
import 'screens/settings/security_screen.dart';
import 'screens/settings/blocked_users_screen.dart';
import 'screens/settings/appearance_screen.dart';
import 'screens/settings/language_screen.dart';
import 'screens/settings/notifications_settings_screen.dart';
import 'screens/settings/data_storage_screen.dart';
import 'screens/settings/account_settings_screen.dart';
import 'screens/settings/bot_settings_screen.dart';
import 'screens/settings/restore_chats_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/profile/public_profile_screen.dart';
import 'screens/groups/create_group_screen.dart';
import 'screens/status/status_screen.dart';
import 'screens/status/create_status_screen.dart';
import 'screens/moderation/report_screen.dart';
import 'screens/moderation/appeal_screen.dart';
import 'screens/moderation/ban_guard.dart';
import 'screens/ai/ai_chatbot_screen.dart';
import 'screens/ai/ai_studio_screen.dart';
import 'screens/channel/channel_screen.dart';
import 'screens/channel/create_channel_screen.dart';
import 'screens/calls/call_screen.dart';
import 'screens/calls/incoming_call_screen.dart';
import 'screens/search/global_search_screen.dart';
import 'screens/contacts/contacts_screen.dart';
import 'screens/invite/invite_friends_screen.dart';
import 'screens/saved/saved_messages_screen.dart';
import 'screens/archive/archived_chats_screen.dart';
import 'services/notification_service.dart';
import 'services/push_notification_service.dart';
import 'services/call_notification_service.dart';
import 'services/online_status_service.dart';
import 'services/call_service.dart';
import 'services/call_signaling_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ============================================================================
// BACKGROUND FCM HANDLER
// ============================================================================
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final data = message.data;
  final type = data['type'] as String?;

  if (type == 'call') {
    final callService = CallNotificationService();
    await callService.initialize();

    final signal = CallSignal(
      type: CallSignalType.incoming,
      callId: data['call_id'],
      callerId: data['caller_id'],
      callerName: data['caller_name'],
      callerAvatar: data['caller_avatar'],
      channelName: data['channel_name'],
      isVideoCall: data['is_video_call'] == 'true',
    );

    await callService.showIncomingCallNotification(signal);
  }
}

// ============================================================================
// MAIN
// ============================================================================
void main() async {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  String? startupError;
  String? startupStack;

  try {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp();

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await NotificationService.init();
    await NotificationService.requestPermission();

    await CallNotificationService().initialize();

    final pushService = PushNotificationService();
    await pushService.initialize();

    ConnectivityService().initialize();
    CallService.initialize('8a2cea909f994b0d9e61146e99710277');

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    runApp(const LumaChatApp());
    return;
  } catch (e, stack) {
    startupError = e.toString();
    startupStack = stack.toString();
  }

  runApp(ErrorApp(error: startupError ?? 'Unknown error', stack: startupStack));
}

// ============================================================================
// ERROR APP
// ============================================================================
class ErrorApp extends StatelessWidget {
  final String error;
  final String? stack;

  const ErrorApp({super.key, required this.error, this.stack});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: Scaffold(
        backgroundColor: const Color(0xFF212121),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 24),
                const Text(
                  'Luma Chat Error',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The app failed to start. Screenshot this and send it to support.',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 32),
                const Text(
                  'ERROR:',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Text(
                    error,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 14,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                if (stack != null) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'STACK TRACE:',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      stack!,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// AUTH ROUTER — phone-first
// ============================================================================
class AuthRouter extends StatefulWidget {
  const AuthRouter({super.key});

  @override
  State<AuthRouter> createState() => _AuthRouterState();
}

class _AuthRouterState extends State<AuthRouter> {
  Widget? _targetScreen;
  bool _isChecking = true;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() => _showSplash = false);
        _checkAuthState();
      }
    });
  }

  Future<void> _checkAuthState() async {
    final prefs = await SharedPreferences.getInstance();

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        final data = userDoc.data();
        final hasUsername =
            (data?['username'] as String?)?.trim().isNotEmpty ?? false;
        final hasDisplayName =
            (data?['display_name'] as String?)?.trim().isNotEmpty ?? false;
        final complete = userDoc.exists && hasUsername && hasDisplayName;

        setState(() {
          _targetScreen =
              complete ? const MainAppScreen() : const SetupProfileScreen();
          _isChecking = false;
        });
      } catch (_) {
        setState(() {
          _targetScreen = const SetupProfileScreen();
          _isChecking = false;
        });
      }
      return;
    }

    final pendingPhone = prefs.getString('pending_phone');
    final pendingEmail = prefs.getString('pending_email');

    if (pendingPhone == null) {
      setState(() {
        _targetScreen = const PhoneEntryScreen();
        _isChecking = false;
      });
      return;
    }

    if (pendingEmail == null || pendingEmail.isEmpty) {
      setState(() {
        _targetScreen = const EmailVerificationScreen();
        _isChecking = false;
      });
      return;
    }

    setState(() {
      _targetScreen = const EmailVerificationScreen();
      _isChecking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_showSplash) return const SplashScreen();

    if (_isChecking) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }
    return _targetScreen!;
  }
}

// ============================================================================
// CALL LISTENER
// ============================================================================
class CallListener extends StatefulWidget {
  final Widget child;
  const CallListener({super.key, required this.child});

  @override
  State<CallListener> createState() => _CallListenerState();
}

class _CallListenerState extends State<CallListener> {
  StreamSubscription<CallSignal>? _callSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _setupCallListening());
  }

  void _setupCallListening() {
    try {
      final authProvider = Provider.of<LumaAuthProvider>(context, listen: false);
      final userId = authProvider.currentUserId;
      if (userId == null) return;

      CallSignalingService.startListening(userId);
      _callSub = CallSignalingService.onCallSignal.listen((signal) {
        if (signal.type == CallSignalType.incoming && mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => IncomingCallScreen(signal: signal),
            ),
          );
        }
      });
    } catch (e) {
      debugPrint('CallListener setup error: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      final authProvider = Provider.of<LumaAuthProvider>(context);
      final userId = authProvider.currentUserId;
      if (userId != null) CallSignalingService.startListening(userId);
    } catch (_) {}
  }

  @override
  void dispose() {
    _callSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ============================================================================
// APP ROOT
// ============================================================================
class LumaChatApp extends StatefulWidget {
  const LumaChatApp({super.key});

  @override
  State<LumaChatApp> createState() => _LumaChatAppState();
}

class _LumaChatAppState extends State<LumaChatApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider =
          Provider.of<LumaAuthProvider>(context, listen: false);
      authProvider.listenToAuthChanges();

      final settingsProvider =
          Provider.of<SettingsProvider>(context, listen: false);
      settingsProvider.startForegroundTimer();

      PushNotificationService().onChatOpen = (chatId) {
        navigatorKey.currentState
            ?.pushNamed('/chat', arguments: {'chatId': chatId});
      };
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    CallSignalingService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _handleBackground();
    } else if (state == AppLifecycleState.resumed) {
      _handleResume();
    }
  }

  void _handleBackground() async {
    try {
      OnlineStatusService.setOffline();
      final settingsProvider =
          Provider.of<SettingsProvider>(context, listen: false);
      settingsProvider.stopForegroundTimer();
      settingsProvider.onAppBackground();
    } catch (e) {
      debugPrint('Background handler error: $e');
    }
  }

  void _handleResume() async {
    try {
      await OnlineStatusService.setOnline();
      final authProvider =
          Provider.of<LumaAuthProvider>(context, listen: false);
      authProvider.refreshSession();
      final settingsProvider =
          Provider.of<SettingsProvider>(context, listen: false);
      settingsProvider.startForegroundTimer();
      await settingsProvider.shouldShowLockScreen();
    } catch (e) {
      debugPrint('Resume handler error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LumaAuthProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => BotProvider()),
        ChangeNotifierProvider(create: (_) => ModerationProvider()),
      ],
      child: Consumer2<ThemeProvider, LumaAuthProvider>(
        builder: (context, themeProvider, authProvider, _) {
          return MaterialApp(
            title: 'Luma Chat',
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            initialRoute: '/',
            builder: (context, child) {
              return Column(
                children: [
                  const OfflineBanner(),
                  Expanded(
                    child: _AppLockWrapper(
                        child: child ?? const SizedBox.shrink()),
                  ),
                ],
              );
            },
            routes: {
              '/': (_) => const AuthRouter(),
              '/terms': (_) => const TermsScreen(),
              '/phone_entry': (_) => const PhoneEntryScreen(),
              '/email_verification': (_) => const EmailVerificationScreen(),
              '/setup_profile': (_) => const SetupProfileScreen(),
              '/main': (_) => const MainAppScreen(),
              '/chat': (_) => const ChatScreen(),
              '/bot_store': (_) => const BotStoreScreen(),
              '/bot_creator': (_) => const BotCreatorScreen(),
              '/privacy_settings': (_) => const PrivacySettingsScreen(),
              '/security': (_) => const SecurityScreen(),
              '/blocked_users': (_) => const BlockedUsersScreen(),
              '/appearance': (_) => const AppearanceScreen(),
              '/language': (_) => const LanguageScreen(),
              '/public_profile': (_) => const PublicProfileScreen(),
              '/profile': (_) => const ProfileScreen(),
              '/create_group': (_) => const CreateGroupScreen(),
              '/create_channel': (_) => const CreateChannelScreen(),
              '/status': (_) => const StatusScreen(),
              '/create_status': (_) => const CreateStatusScreen(),
              '/report': (_) => const ReportScreen(),
              '/appeal': (_) => const AppealScreen(),
              '/ai_chatbot': (_) => const AIChatbotScreen(),
              '/ai_studio': (_) => const AIStudioScreen(),
              '/channel': (context) {
                final args = ModalRoute.of(context)?.settings.arguments
                    as Map<String, dynamic>?;
                return ChannelChatScreen(
                  channelId: args?['channelId'] as String? ?? '',
                  channelName: args?['channelName'] as String? ?? 'Channel',
                );
              },
              '/calls': (_) => const CallScreen.pick(),
              '/global_search': (_) => const GlobalSearchScreen(),
              '/contacts': (_) => const ContactsScreen(),
              '/settings': (_) => const SettingsScreen(),
              '/notifications_settings': (_) =>
                  const NotificationsSettingsScreen(),
              '/data_storage': (_) => const DataStorageScreen(),
              '/account_settings': (_) => const AccountSettingsScreen(),
              '/bot_settings': (_) => const BotSettingsScreen(),
              '/invite_friends': (_) => const InviteFriendsScreen(),
              '/saved_messages': (_) => const SavedMessagesScreen(),
              '/archived_chats': (_) => const ArchivedChatsScreen(),
              '/restore_chats': (_) => const RestoreChatsScreen(),
            },
          );
        },
      ),
    );
  }
}

// ============================================================================
// APP LOCK WRAPPER
// ============================================================================
class _AppLockWrapper extends StatefulWidget {
  final Widget child;
  const _AppLockWrapper({required this.child});

  @override
  State<_AppLockWrapper> createState() => _AppLockWrapperState();
}

class _AppLockWrapperState extends State<_AppLockWrapper> {
  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);
    if (settingsProvider.isLocked) {
      return LockScreen(onUnlocked: settingsProvider.unlock);
    }

    final app = CallListener(child: widget.child);

    final currentUser = FirebaseAuth.instance.currentUser;
    final userId = currentUser?.uid;

    if (userId == null) return app;

    return StreamBuilder<DocumentSnapshot>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(userId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          );
        }

        final userData = snapshot.data?.data() as Map<String, dynamic>?;
        final isBanned = userData?['is_banned'] == true;
        final bannedUntil = userData?['banned_until'] as Timestamp?;

        if (isBanned && bannedUntil != null) {
          final banExpiry = bannedUntil.toDate();
          if (DateTime.now().isAfter(banExpiry)) {
            FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .update({
              'is_banned': false,
              'banned_until': null,
              'ban_reason': null,
              'ban_report_id': null,
              'ban_level': null,
            });
            return app;
          }
        }

        if (isBanned) {
          final banStatus = {
            'is_banned': true,
            'banned_until': bannedUntil?.toDate(),
            'ban_reason': userData?['ban_reason'],
            'ban_level': userData?['ban_level'],
            'ban_report_id': userData?['ban_report_id'],
          };
          return BannedScreen(banStatus: banStatus);
        }

        return app;
      },
    );
  }
}

// ============================================================================
// LOCK SCREEN
// ============================================================================
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _isAuthenticating = false;
  bool _showPasscode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _attemptAutoAuth());
  }

  Future<void> _attemptAutoAuth() async {
    if (_isAuthenticating) return;
    _isAuthenticating = true;

    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);

    if (settingsProvider.biometricLock) {
      final localAuth = LocalAuthentication();
      try {
        final didAuth = await localAuth.authenticate(
          localizedReason: 'Unlock Luma Chat',
          authMessages: const [
            AndroidAuthMessages(
              signInTitle: 'Biometric Authentication',
              cancelButton: 'Cancel',
              biometricHint: 'Verify your identity',
              biometricNotRecognized: 'Not recognized, try again',
              biometricRequiredTitle: 'Biometric authentication required',
              biometricSuccess: 'Authentication successful',
              deviceCredentialsRequiredTitle: 'Device credentials required',
              deviceCredentialsSetupDescription:
                  'Please set up device credentials',
              goToSettingsButton: 'Go to Settings',
              goToSettingsDescription:
                  'Please set up biometric authentication in your device settings',
            ),
            IOSAuthMessages(
              cancelButton: 'Cancel',
              goToSettingsButton: 'Go to Settings',
              goToSettingsDescription:
                  'Please set up biometric authentication in your device settings',
              lockOut: 'Please re-enable biometric authentication',
            ),
          ],
          options: const AuthenticationOptions(
            biometricOnly: false,
            stickyAuth: true,
            sensitiveTransaction: true,
            useErrorDialogs: true,
          ),
        );

        if (didAuth && mounted) {
          widget.onUnlocked();
          return;
        }
      } catch (e) {
        debugPrint('Biometric auth failed: $e');
      }
    }

    if (settingsProvider.appPasscode && mounted) {
      setState(() => _showPasscode = true);
    }
    _isAuthenticating = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: _showPasscode
              ? _PasscodeEntry(
                  correctPasscode:
                      Provider.of<SettingsProvider>(context, listen: false)
                          .passcode,
                  onUnlocked: widget.onUnlocked,
                  onCancel: () => setState(() => _showPasscode = false),
                )
              : _buildPrompt(theme),
        ),
      ),
    );
  }

  Widget _buildPrompt(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.15),
            shape: BoxShape.circle,
            border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
          ),
          child: Icon(Icons.lock_outline,
              size: 48, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 32),
        Text('Luma is Locked',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text('Authentication required to continue',
            style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5))),
        const SizedBox(height: 48),
        GestureDetector(
          onTap: () {
            final sp = Provider.of<SettingsProvider>(context, listen: false);
            if (sp.appPasscode) {
              setState(() => _showPasscode = true);
            } else {
              _attemptAutoAuth();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Text('Enter Passcode',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// PASSCODE ENTRY
// ============================================================================
class _PasscodeEntry extends StatefulWidget {
  final String correctPasscode;
  final VoidCallback onUnlocked;
  final VoidCallback onCancel;

  const _PasscodeEntry({
    required this.correctPasscode,
    required this.onUnlocked,
    required this.onCancel,
  });

  @override
  State<_PasscodeEntry> createState() => _PasscodeEntryState();
}

class _PasscodeEntryState extends State<_PasscodeEntry> {
  String _entered = '';
  String _error = '';

  void _onDigit(String d) {
    if (_entered.length < 6) {
      setState(() {
        _entered += d;
        _error = '';
      });
      if (_entered.length == 6) _verify();
    }
  }

  void _onBackspace() {
    if (_entered.isNotEmpty) {
      setState(() {
        _entered = _entered.substring(0, _entered.length - 1);
        _error = '';
      });
    }
  }

  void _verify() {
    if (_entered == widget.correctPasscode) {
      widget.onUnlocked();
    } else {
      setState(() {
        _error = 'Incorrect passcode';
        _entered = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.15),
              shape: BoxShape.circle,
              border:
                  Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
            ),
            child: Icon(Icons.pin_outlined,
                size: 32, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 24),
          Text('Enter Passcode',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Enter your 6-digit PIN to unlock',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.4))),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(6, (i) {
              final filled = i < _entered.length;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      filled ? theme.colorScheme.primary : theme.dividerColor,
                ),
              );
            }),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(_error,
                style: const TextStyle(color: Colors.redAccent, fontSize: 14)),
          ],
          const SizedBox(height: 40),
          SizedBox(
            width: 300,
            child: GridView.count(
              shrinkWrap: true,
              crossAxisCount: 3,
              childAspectRatio: 1.2,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: [
                for (var i = 1; i <= 9; i++) _digit(i.toString()),
                _action(Icons.fingerprint, () {
                  final sp =
                      Provider.of<SettingsProvider>(context, listen: false);
                  if (sp.biometricLock) _tryBiometric();
                }),
                _digit('0'),
                _action(Icons.backspace_outlined, _onBackspace),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
        ],
      ),
    );
  }

  Future<void> _tryBiometric() async {
    final localAuth = LocalAuthentication();
    try {
      final ok = await localAuth.authenticate(
        localizedReason: 'Unlock Luma Chat',
        options:
            const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
      if (ok && mounted) widget.onUnlocked();
    } catch (e) {
      debugPrint('Biometric retry failed: $e');
    }
  }

  Widget _digit(String d) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => _onDigit(d),
      child: Container(
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? Colors.white.withOpacity(0.06)
              : Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Center(
          child: Text(d,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }

  Widget _action(IconData icon, VoidCallback onTap) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? Colors.white.withOpacity(0.04)
              : Colors.black.withOpacity(0.02),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Center(
          child: Icon(icon,
              color: theme.colorScheme.onSurface.withOpacity(0.6), size: 24),
        ),
      ),
    );
  }
}

// ============================================================================
// OFFLINE BANNER — single-value connectivity API
// ============================================================================
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _offline = false;
  StreamSubscription<ConnectivityResult>? _sub;

  @override
  void initState() {
    super.initState();
    _check();
    _sub = Connectivity().onConnectivityChanged.listen((result) {
      if (!mounted) return;
      setState(() => _offline = result == ConnectivityResult.none);
    });
  }

  Future<void> _check() async {
    final result = await Connectivity().checkConnectivity();
    if (!mounted) return;
    setState(() => _offline = result == ConnectivityResult.none);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: _offline ? 28 : 0,
      color: const Color(0xFFE53935),
      child: _offline
          ? const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wifi_off_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'No internet connection',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

// ============================================================================
// CONNECTIVITY SERVICE — single-value API
// ============================================================================
class ConnectivityService {
  static final ConnectivityService _i = ConnectivityService._();
  factory ConnectivityService() => _i;
  ConnectivityService._();

  StreamSubscription<ConnectivityResult>? _sub;
  final ValueNotifier<bool> isOnline = ValueNotifier(true);

  void initialize() {
    _sub?.cancel();
    _sub = Connectivity().onConnectivityChanged.listen((result) {
      isOnline.value = result != ConnectivityResult.none;
    });
    _checkNow();
  }

  Future<void> _checkNow() async {
    final result = await Connectivity().checkConnectivity();
    isOnline.value = result != ConnectivityResult.none;
  }

  Future<bool> checkOnline() async {
    final result = await Connectivity().checkConnectivity();
    return result != ConnectivityResult.none;
  }

  void dispose() {
    _sub?.cancel();
    isOnline.dispose();
  }
}
