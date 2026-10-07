import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoDeleteAudio = false;
  String _summaryStyle = 'Executive Summary';
  String _languagePriority = 'Auto-Detect';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoDeleteAudio = prefs.getBool('setting_auto_delete') ?? false;
      _summaryStyle =
          prefs.getString('setting_summary_style') ?? 'Executive Summary';
      _languagePriority =
          prefs.getString('setting_lang_priority') ?? 'Auto-Detect';
    });
  }

  Future<void> _saveSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Storage & Memory',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: SwitchListTile(
                title: const Text(
                  'Auto-Delete Audio',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'Delete heavy .wav files automatically after transcription is complete to save storage.',
                  style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                ),
                value: _autoDeleteAudio,
                activeThumbColor: AppTheme.primaryColor,
                onChanged: (val) {
                  setState(() => _autoDeleteAudio = val);
                  _saveSetting('setting_auto_delete', val);
                },
              ),
            ),

            const SizedBox(height: 32),
            const Text(
              'AI Preferences',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Default Summary Style',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _summaryStyle,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey[50],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.dividerColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.dividerColor),
                      ),
                    ),
                    items:
                        [
                              'Executive Summary',
                              'Bullet Points',
                              'Action Items Only',
                            ]
                            .map(
                              (style) => DropdownMenuItem(
                                value: style,
                                child: Text(style),
                              ),
                            )
                            .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _summaryStyle = val);
                        _saveSetting('setting_summary_style', val);
                      }
                    },
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'Language Priority',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _languagePriority,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey[50],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.dividerColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppTheme.dividerColor),
                      ),
                    ),
                    items:
                        [
                              'Auto-Detect',
                              'English Only',
                              'Hindi Only',
                              'Hinglish (Code-Mixed)',
                            ]
                            .map(
                              (lang) => DropdownMenuItem(
                                value: lang,
                                child: Text(lang),
                              ),
                            )
                            .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _languagePriority = val);
                        _saveSetting('setting_lang_priority', val);
                      }
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 48),
            Center(
              child: TextButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text(
                        'Delete Account',
                        style: TextStyle(color: AppTheme.dangerColor),
                      ),
                      content: const Text(
                        'Are you sure you want to permanently delete your account and all associated meetings? This cannot be undone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text(
                            'Delete Everything',
                            style: TextStyle(color: AppTheme.dangerColor),
                          ),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.dangerColor,
                        ),
                      ),
                    );
                    final success = await ApiService().deleteAccount();
                    if (!context.mounted) return;
                    if (true) {
                      Navigator.pop(context); // Close loading dialog
                      if (success) {
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/login',
                          (route) => false,
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Failed to delete account. Please try again later.',
                            ),
                          ),
                        );
                      }
                    }
                  }
                },
                icon: const Icon(
                  Icons.delete_forever,
                  color: AppTheme.dangerColor,
                ),
                label: const Text(
                  'Delete Account',
                  style: TextStyle(
                    color: AppTheme.dangerColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
