import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PhoneEntryScreen extends StatefulWidget {
  const PhoneEntryScreen({super.key});

  @override
  State<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends State<PhoneEntryScreen> {
  final _phoneController = TextEditingController();
  String _countryCode = '+1';
  bool _isLoading = false;
  String? _error;

  static const _countryCodes = [
    ('+1', '🇺🇸 US'),
    ('+44', '🇬🇧 UK'),
    ('+91', '🇮🇳 IN'),
    ('+234', '🇳🇬 NG'),
    ('+27', '🇿🇦 ZA'),
    ('+254', '🇰🇪 KE'),
    ('+233', '🇬🇭 GH'),
    ('+33', '🇫🇷 FR'),
    ('+49', '🇩🇪 DE'),
    ('+81', '🇯🇵 JP'),
    ('+86', '🇨🇳 CN'),
    ('+55', '🇧🇷 BR'),
    ('+52', '🇲🇽 MX'),
    ('+61', '🇦🇺 AU'),
  ];

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final raw = _phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    if (raw.isEmpty || raw.length < 6) {
      setState(() => _error = 'Enter a valid phone number');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final full = '$_countryCode$raw';

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_phone', full);
    await prefs.setInt(
      'pending_phone_timestamp',
      DateTime.now().millisecondsSinceEpoch,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);
    Navigator.pushReplacementNamed(context, '/email_verification');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),

              // Logo — blue rounded square
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Icon(
                    Icons.chat_bubble_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              Text(
                'Your phone number',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'We use it for account recovery. You can add a username later.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 40),

              // Country code + phone field
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Country code dropdown
                  Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: theme.brightness == Brightness.dark
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFFF1F1F1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _countryCode,
                        icon: Icon(
                          Icons.arrow_drop_down,
                          color: theme.colorScheme.primary,
                        ),
                        dropdownColor: theme.brightness == Brightness.dark
                            ? const Color(0xFF2A2A2A)
                            : Colors.white,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        items: _countryCodes.map((c) {
                          return DropdownMenuItem(
                            value: c.$1,
                            child: Text('${c.$2}  ${c.$1}'),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _countryCode = v);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Phone number field
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(15),
                      ],
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 18,
                        letterSpacing: 1.2,
                      ),
                      decoration: const InputDecoration(
                        hintText: '123 456 7890',
                      ),
                    ),
                  ),
                ],
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _continue,
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Continue'),
                ),
              ),

              const SizedBox(height: 16),

              Center(
                child: Text(
                  'By continuing you agree to our Terms & Privacy Policy',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.4),
                  ),
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
