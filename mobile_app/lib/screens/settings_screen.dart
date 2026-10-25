import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _tokenController = TextEditingController();
  final _repoController = TextEditingController();
  final _geminiKeyController = TextEditingController();
  bool _isLoading = true;
  bool _isTestingToken = false;
  bool _isTestingGemini = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _tokenController.text = prefs.getString('github_token') ?? '';
      _repoController.text = prefs.getString('github_repo') ?? 'feriwidiyanto25-svg/apk-video';
      _geminiKeyController.text = prefs.getString('gemini_api_key') ?? '';
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('github_token', _tokenController.text.trim());
    await prefs.setString('github_repo', _repoController.text.trim());
    await prefs.setString('gemini_api_key', _geminiKeyController.text.trim());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pengaturan berhasil disimpan!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _testGitHubConnection() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Masukkan kode token terlebih dahulu.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isTestingToken = true);
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/user'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github+json',
        },
      );

      if (mounted) {
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final login = data['login'] ?? 'GitHub User';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Token Valid! Terhubung sebagai @$login'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Token Ditolak (${res.statusCode}). Periksa apakah token diawali ghp_ dan izin repo dicentang.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menghubungi GitHub: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTestingToken = false);
      }
    }
  }

  Future<void> _testGeminiConnection() async {
    final key = _geminiKeyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Masukkan Gemini API Key terlebih dahulu.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isTestingGemini = true);
    try {
      final res = await http.get(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$key'),
      ).timeout(const Duration(seconds: 10));

      if (mounted) {
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final List modelsList = data['models'] ?? [];
          final working = <String>[];
          for (var m in modelsList) {
            final List methods = m['supportedGenerationMethods'] ?? [];
            if (methods.contains('generateContent')) {
              final name = m['name']?.toString().replaceFirst('models/', '') ?? '';
              if (name.isNotEmpty) working.add(name);
            }
          }

          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Gemini Key Valid!'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Ditemukan ${working.length} model aktif untuk akun Anda:'),
                    const SizedBox(height: 10),
                    ...working.take(8).map((m) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Row(
                            children: [
                              const Icon(Icons.auto_awesome, size: 14, color: Colors.amber),
                              const SizedBox(width: 6),
                              Expanded(child: Text(m, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                            ],
                          ),
                        )),
                    if (working.length > 8)
                      Text('...dan ${working.length - 8} model lainnya', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Gemini Key Ditolak (${res.statusCode}): ${res.body}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal verifikasi Gemini: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTestingGemini = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan API & Akun'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1. GitHub Repository (Owner/Repo)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _repoController,
              decoration: const InputDecoration(
                hintText: 'contoh: feriwidiyanto25-svg/apk-video',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.folder_shared),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '2. GitHub Personal Access Token (PAT)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _tokenController,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'ghp_xxxxxxxxxxxxxxxxxxxx',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Izin wajib: repo dan workflow',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                TextButton.icon(
                  onPressed: _isTestingToken ? null : _testGitHubConnection,
                  icon: _isTestingToken
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified, size: 16, color: Colors.blueAccent),
                  label: const Text('Tes Token', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              '3. Google Gemini API Key (Opsional)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _geminiKeyController,
              obscureText: true,
              decoration: const InputDecoration(
                hintText: 'AIzaSyxxxxxxxxxxxxxxx (Gratis)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.auto_awesome),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Digunakan untuk naskah & judul AI',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                TextButton.icon(
                  onPressed: _isTestingGemini ? null : _testGeminiConnection,
                  icon: _isTestingGemini
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome, size: 16, color: Colors.amber),
                  label: const Text('Tes Gemini Key', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _saveSettings,
                icon: const Icon(Icons.save),
                label: const Text('Simpan Pengaturan', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
