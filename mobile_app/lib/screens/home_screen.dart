import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/job_model.dart';
import '../services/github_service.dart';

class HomeScreen extends StatefulWidget {
  final Function(int) onTabSwitch;

  const HomeScreen({super.key, required this.onTabSwitch});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _geminiKeyController = TextEditingController();
  final _topicController = TextEditingController();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _scriptController = TextEditingController();

  String _creationMode = 'ai'; // 'manual' or 'ai'
  bool _obscureGeminiKey = true;
  bool _isTestingGeminiKey = false;
  String _selectedVoice = 'id-ID-GadisNeural';
  String _selectedMusic = 'music1.mp3';
  File? _selectedMedia;
  String? _selectedMediaName;
  int _selectedMediaSize = 0;
  bool _isImage = true;
  bool _isSubmitting = false;
  bool _isGeneratingScript = false;
  String _submitStep = '';

  final List<Map<String, String>> _musicList = [
    {
      'id': 'music1.mp3',
      'name': '🎵 Musik 1 - Santai / Chill',
      'desc': 'Cocok untuk edukasi, cerita inspiratif, & fakta menarik',
    },
    {
      'id': 'music5.mp3',
      'name': '⚡ Musik 2 - Upbeat / Energik',
      'desc': 'Cocok untuk tips & trik, hiburan, & video seru',
    },
    {
      'id': 'music6.mp3',
      'name': '🕵️ Musik 3 - Misteri / Suspense',
      'desc': 'Cocok untuk misteri, konspirasi, & dark facts',
    },
    {
      'id': 'music7.mp3',
      'name': '🎬 Musik 4 - Sinematik / Emosional',
      'desc': 'Cocok untuk momen penting, sejarah, & drama',
    },
    {
      'id': 'music8.mp3',
      'name': '🚀 Musik 5 - Inspiratif / Motivasi',
      'desc': 'Cocok untuk motivasi bisnis, sukses, & cerita epik',
    },
    {
      'id': 'none',
      'name': '🔇 Tanpa Musik (Hanya Narasi)',
      'desc': 'Hanya suara narasi tanpa musik latar',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedKey = prefs.getString('gemini_api_key') ?? '';
    if (mounted && savedKey.isNotEmpty) {
      setState(() {
        _geminiKeyController.text = savedKey;
      });
    }
  }

  @override
  void dispose() {
    _geminiKeyController.dispose();
    _topicController.dispose();
    _titleController.dispose();
    _descController.dispose();
    _scriptController.dispose();
    super.dispose();
  }

  void _copyText(String text, String label) {
    if (text.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: text.trim()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ $label berhasil disalin ke clipboard!'),
        backgroundColor: Colors.green[700],
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _testGeminiConnection() async {
    final key = _geminiKeyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Masukkan Google Gemini API Key terlebih dahulu.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isTestingGeminiKey = true);
    try {
      final res = await http.get(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$key'),
      ).timeout(const Duration(seconds: 8));

      if (mounted) {
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final List modelsList = data['models'] ?? [];
          int count = 0;
          for (var m in modelsList) {
            final List methods = m['supportedGenerationMethods'] ?? [];
            if (methods.contains('generateContent')) count++;
          }

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('gemini_api_key', key);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Gemini Key Valid ($count model aktif ditemukan)!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Gemini Key Ditolak (${res.statusCode}). Periksa kembali API Key Anda.'),
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
        setState(() => _isTestingGeminiKey = false);
      }
    }
  }

  Future<void> _pickMedia() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final size = await file.length();

      // Check size limit (max 60 MB to prevent long uploads on cellular data)
      if (size > 60 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ukuran file melebihi 60 MB. Harap pilih video/foto yang lebih ringkas.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final ext = result.files.single.extension?.toLowerCase() ?? '';
      setState(() {
        _selectedMedia = file;
        _selectedMediaName = result.files.single.name;
        _selectedMediaSize = size;
        _isImage = ['jpg', 'jpeg', 'png', 'webp'].contains(ext);
      });
    }
  }

  Future<void> _generateScriptWithGemini() async {
    final geminiKey = _geminiKeyController.text.trim();
    if (geminiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Harap masukkan Google Gemini API Key Anda terlebih dahulu!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ketik ide atau topik video terlebih dahulu di kolom Ide / Topik!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', geminiKey);

    setState(() => _isGeneratingScript = true);

    try {
      final promptText = '''
Bertindaklah sebagai pembuat konten video pendek viral profesional (YouTube Shorts, Instagram Reels, Facebook Reels / FB Pro, TikTok).
Buatkan konten video pendek berdurasi 45-60 detik mengenai topik berikut:
"$topic"

Aturan Penting:
1. title: Judul video yang sangat memikat, click-worthy, memicu rasa penasaran, dan dilengkapi hashtag utama (maksimal 70 karakter, contoh: "5 Rahasia Kopi yang Bikin Melongo! ☕🔥 #shorts").
2. description: Deskripsi lengkap siap copy-paste ke Facebook & YouTube. Berikan kalimat pengantar yang memikat, ajakan interaksi (like/share/komentar), dan 6-8 hashtag populer relevan (seperti #shorts #reels #fbpro #viral #faktaunik).
3. script: Naskah narasi suara Bahasa Indonesia santai, padat, dan mendalam (panjang 110-140 kata, untuk durasi 45-60 detik) dengan HOOK penasaran yang kuat di 3 detik pertama, penjelasan fakta menarik yang memikat penonton, serta penutup ajakan diskusi. Tuliskan HANYA kata-kata yang diucapkan narator secara langsung (voiceover only). Jangan gunakan tanda kurung, intro klise "Halo guys", atau instruksi visual.

Kembalikan respon HANYA dalam format JSON murni yang valid tanpa teks penjelasan di luar JSON:
{
  "title": "...",
  "description": "...",
  "script": "..."
}
''';

      // 1. Dynamic Discovery: Ambil semua model yang aktif & didukung oleh Google untuk API Key ini
      List<String> candidateModels = [];
      try {
        final listUrl = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$geminiKey');
        final listRes = await http.get(listUrl).timeout(const Duration(seconds: 8));
        if (listRes.statusCode == 200) {
          final listData = jsonDecode(listRes.body);
          final List modelsList = listData['models'] ?? [];
          for (var m in modelsList) {
            final List methods = m['supportedGenerationMethods'] ?? [];
            if (methods.contains('generateContent')) {
              final name = m['name']?.toString() ?? '';
              final clean = name.replaceFirst('models/', '');
              if (clean.isNotEmpty) {
                candidateModels.add(clean);
              }
            }
          }
        }
      } catch (_) {}

      // 2. Prioritaskan model: utamakan model Flash & versi terbaru
      candidateModels.sort((a, b) {
        int score(String name) {
          int s = 0;
          if (name.contains('flash')) s += 100;
          if (name.contains('3.')) s += 60;
          if (name.contains('2.5')) s += 50;
          if (name.contains('2.0')) s += 30;
          if (name.contains('1.5')) s += 20;
          if (name.contains('pro')) s += 10;
          if (name.contains('exp')) s -= 5;
          return s;
        }
        return score(b).compareTo(score(a));
      });

      // 3. Cadangan lengkap jika daftar model tidak dapat dijangkau
      final fallbackList = [
        'gemini-2.5-flash',
        'gemini-2.5-pro',
        'gemini-2.0-flash-exp',
        'gemini-1.5-flash',
        'gemini-1.5-flash-latest',
        'gemini-1.5-pro',
        'gemini-1.5-pro-latest',
        'gemini-pro',
      ];
      for (var fb in fallbackList) {
        if (!candidateModels.contains(fb)) {
          candidateModels.add(fb);
        }
      }

      String? rawResponse;
      String? usedModel;
      String? errorMsg;

      for (var model in candidateModels) {
        try {
          final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$geminiKey');
          final response = await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': promptText}
                  ]
                }
              ]
            }),
          ).timeout(const Duration(seconds: 15));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            rawResponse = data['candidates'][0]['content']['parts'][0]['text']?.toString().trim();
            if (rawResponse != null && rawResponse.isNotEmpty) {
              usedModel = model;
              break;
            }
          } else {
            errorMsg = '$model (${response.statusCode}): ${response.body}';
          }
        } catch (e) {
          errorMsg = '$model: $e';
        }
      }

      if (rawResponse != null && rawResponse.isNotEmpty) {
        String cleanJson = rawResponse;
        if (cleanJson.contains('```json')) {
          cleanJson = cleanJson.split('```json')[1].split('```')[0].trim();
        } else if (cleanJson.contains('```')) {
          cleanJson = cleanJson.split('```')[1].split('```')[0].trim();
        }

        final firstBrace = cleanJson.indexOf('{');
        final lastBrace = cleanJson.lastIndexOf('}');
        if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
          cleanJson = cleanJson.substring(firstBrace, lastBrace + 1);
        }

        try {
          final decoded = jsonDecode(cleanJson);
          if (decoded is Map) {
            setState(() {
              if (decoded['title'] != null) _titleController.text = decoded['title'].toString().trim();
              if (decoded['description'] != null) _descController.text = decoded['description'].toString().trim();
              if (decoded['script'] != null) _scriptController.text = decoded['script'].toString().trim();
            });
          }
        } catch (_) {
          final titleMatch = RegExp(r'"title"\s*:\s*"([^"]+)"').firstMatch(cleanJson);
          final scriptMatch = RegExp(r'"script"\s*:\s*"([^"]+)"').firstMatch(cleanJson);
          final descMatch = RegExp(r'"description"\s*:\s*"([^"]+)"').firstMatch(cleanJson);

          setState(() {
            if (titleMatch != null) _titleController.text = titleMatch.group(1)!;
            if (descMatch != null) _descController.text = descMatch.group(1)!.replaceAll(r'\n', '\n');
            if (scriptMatch != null) {
              _scriptController.text = scriptMatch.group(1)!;
            } else {
              _scriptController.text = rawResponse!;
            }
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✨ Naskah, Judul & Deskripsi berhasil dibuat ($usedModel)!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Gagal membuat naskah: $errorMsg');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal membuat konten AI: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingScript = false);
      }
    }
  }

  Future<void> _submitJob() async {
    final script = _scriptController.text.trim();
    final topic = _topicController.text.trim();
    final title = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : 'Video Shorts';
    final description = _descController.text.trim();

    if (script.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan masukkan teks Suara Narasi terlebih dahulu.')),
      );
      return;
    }

    if (_selectedMedia == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan pilih foto atau video latar terlebih dahulu.')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final repo = prefs.getString('github_repo') ?? '';
    final token = prefs.getString('github_token') ?? '';
    final geminiKey = _geminiKeyController.text.trim().isNotEmpty
        ? _geminiKeyController.text.trim()
        : (prefs.getString('gemini_api_key') ?? '');

    if (_geminiKeyController.text.trim().isNotEmpty) {
      await prefs.setString('gemini_api_key', _geminiKeyController.text.trim());
    }

    if (repo.isEmpty || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Harap atur GitHub Repo dan Token di tab Pengaturan terlebih dahulu!'),
          backgroundColor: Colors.orange,
        ),
      );
      widget.onTabSwitch(2); // Go to settings tab
      return;
    }

    setState(() {
      _isSubmitting = true;
      _submitStep = 'Membuat Job di GitHub...';
    });

    final jobId = 'job-${DateTime.now().millisecondsSinceEpoch}';
    int? createdReleaseId;

    try {
      // 1. Create GitHub Release with Title and Description
      setState(() => _submitStep = '1/4 Menyiapkan Job di GitHub...');
      final releaseId = await GitHubService.createRelease(
        repo: repo,
        token: token,
        tag: jobId,
        title: title,
        body: description,
      );
      createdReleaseId = releaseId;

      // 2. Upload Config JSON
      setState(() => _submitStep = '2/4 Mengunggah naskah & konfigurasi...');
      final configData = {
        'job_id': jobId,
        'topic': topic.isNotEmpty ? topic : title,
        'title': title,
        'description': description,
        'script': script,
        'voice': _selectedVoice,
        'bgm': _selectedMusic,
        'gemini_api_key': geminiKey,
      };
      final configBytes = Uint8List.fromList(utf8.encode(jsonEncode(configData)));
      await GitHubService.uploadReleaseAsset(
        repo: repo,
        token: token,
        releaseId: releaseId,
        fileName: 'config.json',
        bytes: configBytes,
        contentType: 'application/json',
      );

      // 3. Upload Media Asset
      setState(() => _submitStep = '3/4 Mengunggah media (${(_selectedMediaSize / (1024 * 1024)).toStringAsFixed(1)} MB)...');
      final mediaBytes = await _selectedMedia!.readAsBytes();
      await GitHubService.uploadReleaseAsset(
        repo: repo,
        token: token,
        releaseId: releaseId,
        fileName: _selectedMediaName!,
        bytes: mediaBytes,
      );

      // 4. Trigger GitHub Actions Workflow
      setState(() => _submitStep = '4/4 Menjalankan mesin render di Cloud...');
      await GitHubService.triggerRenderWorkflow(
        repo: repo,
        token: token,
        jobId: jobId,
      );

      // 5. Save Job to Local History
      final newJob = JobModel(
        id: jobId,
        topic: topic.isNotEmpty ? topic : title,
        script: script,
        voice: _selectedVoice,
        status: 'rendering',
        localMediaPath: _selectedMedia!.path,
        createdAt: DateTime.now(),
        videoTitle: title,
        videoDescription: description,
      );

      final rawJobs = prefs.getStringList('jobs_history') ?? [];
      rawJobs.insert(0, jsonEncode(newJob.toJson()));
      await prefs.setStringList('jobs_history', rawJobs);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job berhasil dikirim! Sedang dirender di cloud...'),
            backgroundColor: Colors.green,
          ),
        );
        // Reset form
        _topicController.clear();
        _titleController.clear();
        _descController.clear();
        _scriptController.clear();
        setState(() {
          _selectedMedia = null;
          _selectedMediaName = null;
          _isSubmitting = false;
        });
        // Switch to history tab
        widget.onTabSwitch(1);
      }
    } catch (e) {
      // Clean up incomplete release on GitHub if upload failed
      if (createdReleaseId != null) {
        try {
          await GitHubService.deleteRelease(repo: repo, token: token, tag: jobId);
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _isSubmitting = false);
        final cleanMsg = e.toString().replaceAll('Exception: ', '').trim();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('Gagal Mengunggah', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(cleanMsg, style: const TextStyle(fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buat Video Shorts / Reels'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section 1: Pilihan Metode Pembuatan (Manual vs AI)
            const Text(
              '1. Metode Pembuatan Naskah',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _creationMode = 'manual'),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _creationMode == 'manual' ? const Color(0xFF6366F1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.edit_note,
                              size: 20,
                              color: _creationMode == 'manual' ? Colors.white : Colors.grey[400],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Manual',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: _creationMode == 'manual' ? Colors.white : Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _creationMode = 'ai'),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _creationMode == 'ai' ? const Color(0xFF6366F1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 18,
                              color: _creationMode == 'ai' ? Colors.white : Colors.grey[400],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Otomatis AI',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: _creationMode == 'ai' ? Colors.white : Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bagian AI: Hanya Tampil Saat Memilih "Otomatis AI"
            if (_creationMode == 'ai') ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Input Google Gemini API Key
                    Row(
                      children: [
                        const Icon(Icons.key, color: Colors.amber, size: 16),
                        const SizedBox(width: 6),
                        const Text(
                          'Google Gemini API Key (Gratis):',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _isTestingGeminiKey ? null : _testGeminiConnection,
                          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                          child: _isTestingGeminiKey
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Tes Key', style: TextStyle(fontSize: 12, color: Colors.amber)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _geminiKeyController,
                      obscureText: _obscureGeminiKey,
                      decoration: InputDecoration(
                        hintText: 'AIzaSyxxxxxxxxxxxxxxx',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        prefixIcon: const Icon(Icons.security, size: 18, color: Colors.grey),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureGeminiKey ? Icons.visibility_off : Icons.visibility,
                            size: 18,
                            color: Colors.grey,
                          ),
                          onPressed: () => setState(() => _obscureGeminiKey = !_obscureGeminiKey),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Input Ide / Topik (Multiline ke bawah seperti WhatsApp)
                    const Text(
                      'Ide / Topik Video:',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _topicController,
                      minLines: 2,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        hintText: 'Ketik topik atau ide cerita yang ingin dibuat video...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Tombol Buat Naskah AI
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isGeneratingScript ? null : _generateScriptWithGemini,
                        icon: _isGeneratingScript
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.auto_awesome, size: 18),
                        label: Text(
                          _isGeneratingScript ? 'Menulis naskah & judul AI...' : '✨ Buat Naskah, Judul & Deskripsi AI',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),

            // Judul Video
            Row(
              children: [
                const Text(
                  'Judul Video',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_titleController.text.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _copyText(_titleController.text, 'Judul'),
                    icon: const Icon(Icons.copy, size: 14, color: Colors.indigoAccent),
                    label: const Text('Salin', style: TextStyle(fontSize: 12, color: Colors.indigoAccent)),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: 'Contoh: 5 Rahasia Kopi yang Bikin Melongo! ☕🔥 #shorts',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.copy, size: 18, color: Colors.grey),
                  onPressed: () => _copyText(_titleController.text, 'Judul'),
                  tooltip: 'Salin Judul',
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Deskripsi Video (Siap Upload)
            Row(
              children: [
                const Text(
                  'Deskripsi Video',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_descController.text.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _copyText(_descController.text, 'Deskripsi'),
                    icon: const Icon(Icons.copy, size: 14, color: Colors.indigoAccent),
                    label: const Text('Salin', style: TextStyle(fontSize: 12, color: Colors.indigoAccent)),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _descController,
              minLines: 2,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: 'Deskripsi lengkap & hashtag (#shorts #reels #fbpro #viral)...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: const Color(0xFF1E293B),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.copy, size: 18, color: Colors.grey),
                  onPressed: () => _copyText(_descController.text, 'Deskripsi'),
                  tooltip: 'Salin Deskripsi',
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Suara Narasi (Point 4: Ganti label menjadi "Suara Narasi")
            Row(
              children: [
                const Text(
                  'Suara Narasi',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_scriptController.text.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _copyText(_scriptController.text, 'Suara Narasi'),
                    icon: const Icon(Icons.copy, size: 14, color: Colors.indigoAccent),
                    label: const Text('Salin', style: TextStyle(fontSize: 12, color: Colors.indigoAccent)),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _scriptController,
              minLines: 3,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: 'Tulis teks naskah yang akan dibacakan oleh AI dan muncul sebagai subtitle karaoke...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 18),

            // Suara AI (Point 5: "Suara AI", Radio Button Sejajar Wanita & Pria)
            const Text(
              'Suara AI',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _selectedVoice = 'id-ID-GadisNeural'),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _selectedVoice == 'id-ID-GadisNeural'
                            ? Colors.redAccent.withOpacity(0.15)
                            : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _selectedVoice == 'id-ID-GadisNeural' ? Colors.redAccent : Colors.white12,
                          width: 1.5,
                        ),
                      ),
                      child: RadioListTile<String>(
                        value: 'id-ID-GadisNeural',
                        groupValue: _selectedVoice,
                        title: const Text('Wanita', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        activeColor: Colors.redAccent,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedVoice = val);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _selectedVoice = 'id-ID-ArdiNeural'),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _selectedVoice == 'id-ID-ArdiNeural'
                            ? Colors.redAccent.withOpacity(0.15)
                            : const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _selectedVoice == 'id-ID-ArdiNeural' ? Colors.redAccent : Colors.white12,
                          width: 1.5,
                        ),
                      ),
                      child: RadioListTile<String>(
                        value: 'id-ID-ArdiNeural',
                        groupValue: _selectedVoice,
                        title: const Text('Pria', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        activeColor: Colors.redAccent,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedVoice = val);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Pilihan Musik Latar (BGM)
            const Text(
              'Musik Latar (BGM)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedMusic,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1E293B),
                  items: _musicList.map((m) {
                    return DropdownMenuItem<String>(
                      value: m['id'],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(m['name']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(m['desc']!, style: TextStyle(fontSize: 11, color: Colors.grey[400])),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedMusic = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Latar Belakang (Foto atau Video dari HP)
            const Text(
              'Latar Belakang (Foto atau Video dari HP)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickMedia,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selectedMedia != null ? Colors.greenAccent : Colors.grey[700]!,
                    width: 1.2,
                  ),
                ),
                child: _selectedMedia == null
                    ? Column(
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          const Text(
                            'Ketuk untuk memilih Foto atau Video dari Galeri',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Format: JPG, PNG, MP4 (Maks. 60 MB)',
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Icon(
                            _isImage ? Icons.image : Icons.videocam,
                            size: 40,
                            color: Colors.greenAccent,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedMediaName ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Ukuran: ${(_selectedMediaSize / (1024 * 1024)).toStringAsFixed(1)} MB (${_isImage ? 'Foto' : 'Video'})',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _pickMedia,
                            child: const Text('Ganti'),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 30),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submitJob,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSubmitting
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Text(_submitStep, style: const TextStyle(fontSize: 14)),
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.rocket_launch),
                          SizedBox(width: 8),
                          Text(
                            'Mulai Buat Video Shorts',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
