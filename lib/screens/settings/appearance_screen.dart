import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Appearance',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Theme',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 8),

          _ThemeOption(
            title: 'Light',
            subtitle: 'Clean and bright',
            icon: Icons.wb_sunny,
            isSelected: themeProvider.isLightMode,
            onTap: () => themeProvider.setLightMode(),
          ),

          _ThemeOption(
            title: 'Dark',
            subtitle: 'Easy on the eyes',
            icon: Icons.nights_stay,
            isSelected: themeProvider.isDarkMode,
            onTap: () => themeProvider.setDarkMode(),
          ),

          _ThemeOption(
            title: 'System Default',
            subtitle: 'Follows your device settings',
            icon: Icons.settings_suggest,
            isSelected: themeProvider.isSystemMode,
            onTap: () => themeProvider.setSystemMode(),
          ),

          const SizedBox(height: 24),

          Text(
            'Preview',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).primaryColor,
            ),
          ),
          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Theme.of(context).primaryColor,
                      child: const Icon(Icons.person, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'John Doe',
                            style: TextStyle(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white
                                  : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Hey, how are you?',
                            style: TextStyle(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white54
                                  : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '2:30 PM',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white38
                            : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? Theme.of(context).primaryColor.withOpacity(0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? Theme.of(context).primaryColor
              : Colors.white.withOpacity(0.1),
        ),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected
                ? Theme.of(context).primaryColor
                : Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white54
                : Colors.black54,
          ),
        ),
        trailing: isSelected
            ? Icon(
                Icons.check_circle,
                color: Theme.of(context).primaryColor,
              )
            : Icon(
                Icons.circle_outlined,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white24
                    : Colors.grey,
              ),
        onTap: onTap,
      ),
    );
  }
}
