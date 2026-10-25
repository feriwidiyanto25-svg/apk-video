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
  final _topicController = TextEditingController();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _scriptController = TextEditingController();

  String _selectedVoice = 'id-ID-GadisNeural';
  String _selectedMusic = 'music1.mp3';
  File? _selectedMedia;
  String? _selectedMediaName;
  int _selectedMediaSize = 0;
  bool _isImage = true;
  bool _isSubmitting = false;
  bool _isGeneratingScript = false;
  String _submitStep = '';

  final List<Map<String, String>> _voices = [
    {
      'id': 'id-ID-GadisNeural',
      'name': 'Gadis (Wanita)',
      'desc': 'Suara ramah, ceria, cocok untuk tips, edukasi, dan hiburan'
    },
    {
      'id': 'id-ID-ArdiNeural',
      'name': 'Ardi (Laki-laki)',
      'desc': 'Suara berwibawa, tegas, cocok untuk berita, misteri, motivasi'
    },
  ];

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
  void dispose() {
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
    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ketik ide atau topik singkat terlebih dahulu di kolom Topik!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final geminiKey = prefs.getString('gemini_api_key') ?? '';

    if (geminiKey.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.key, color: Colors.amber),
              SizedBox(width: 8),
              Text('Gemini API Key Diperlukan'),
            ],
          ),
          content: const Text(
            'Untuk membuat naskah, judul, dan deskripsi otomatis dengan AI, harap masukkan Google Gemini API Key gratis Anda di tab Pengaturan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                widget.onTabSwitch(2); // Go to settings tab
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Ke Pengaturan', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _isGeneratingScript = true);

    try {
      final promptText = '''
Bertindaklah sebagai pembuat konten video pendek viral profesional (YouTube Shorts, Instagram Reels, Facebook Reels / FB Pro, TikTok).
Buatkan konten video pendek berdurasi 30-45 detik mengenai topik berikut:
"$topic"

Aturan Penting:
1. title: Judul video yang sangat memikat, click-worthy, memicu rasa penasaran, dan dilengkapi hashtag utama (maksimal 70 karakter, contoh: "5 Rahasia Kopi yang Bikin Melongo! ☕🔥 #shorts").
2. description: Deskripsi lengkap siap copy-paste ke Facebook & YouTube. Berikan kalimat pengantar yang memikat, ajakan interaksi (like/share/komentar), dan 6-8 hashtag populer relevan (seperti #shorts #reels #fbpro #viral #faktaunik).
3. script: Naskah narasi suara Bahasa Indonesia santai (60-80 kata) dengan HOOK penasaran yang kuat di 3 detik pertama. Tuliskan HANYA kata-kata yang diucapkan narator secara langsung (voiceover only). Jangan gunakan tanda kurung, intro "Halo guys", atau instruksi visual.

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

      // 2. Prioritaskan model: utamakan model Flash & versi terbaru (2.5, 3.x, 2.0, 1.5)
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

      // 3. Cadangan lengkap jika endpoint daftar model tidak dapat dijangkau
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

        // Extract pure JSON object boundaries if preamble/postamble text exists
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
          // Fallback parsing regex
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
    final topic = _topicController.text.trim();
    final script = _scriptController.text.trim().isNotEmpty
        ? _scriptController.text.trim()
        : topic;
    final title = _titleController.text.trim().isNotEmpty
        ? _titleController.text.trim()
        : (topic.isNotEmpty ? topic : 'Video Shorts');
    final description = _descController.text.trim();

    if (script.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan masukkan topik atau naskah video terlebih dahulu.')),
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
    final geminiKey = prefs.getString('gemini_api_key') ?? '';

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

    try {
      // 1. Create GitHub Release with Title and Description
      setState(() => _submitStep = '1/4 Membuat Release Job di GitHub...');
      final releaseId = await GitHubService.createRelease(
        repo: repo,
        token: token,
        tag: jobId,
        title: title,
        body: description,
      );

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
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Terjadi kesalahan: $e'), backgroundColor: Colors.red),
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
            // Section 1: Ide / Topik Utama
            const Text(
              '1. Ide / Topik Utama Video',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _topicController,
              decoration: InputDecoration(
                hintText: 'Contoh: 5 Rahasia Kopi yang Jarang Diketahui Orang',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
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
                  _isGeneratingScript ? 'Menulis naskah & judul...' : '✨ Buat Naskah, Judul & Deskripsi AI',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1), // Indigo
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Section 2: Judul & Deskripsi Siap Upload
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.indigo.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.content_paste_go, color: Colors.indigoAccent, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        '2. Judul, Deskripsi & Naskah Suara',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Dibuat otomatis oleh AI atau ketik manual. Anda bisa langsung salin saat mau upload ke FB/YouTube.',
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                  const SizedBox(height: 12),

                  // Judul Video
                  Row(
                    children: [
                      const Text('Judul Video (YouTube / FB):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
                  const SizedBox(height: 4),
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      hintText: 'Judul memikat dengan hashtag (Contoh: 5 Rahasia Kopi! ☕🔥 #shorts)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.copy, size: 18, color: Colors.grey),
                        onPressed: () => _copyText(_titleController.text, 'Judul'),
                        tooltip: 'Salin Judul',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Deskripsi Video
                  Row(
                    children: [
                      const Text('Deskripsi & Kumpulan Hashtag:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
                  const SizedBox(height: 4),
                  TextField(
                    controller: _descController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Deskripsi lengkap dan kumpulan hashtag viral (#shorts #reels #fbpro #viral)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.copy, size: 18, color: Colors.grey),
                        onPressed: () => _copyText(_descController.text, 'Deskripsi'),
                        tooltip: 'Salin Deskripsi',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Naskah Suara
                  const Text(
                    'Naskah Suara Narasi (Edge-TTS & Subtitle):',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _scriptController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Teks yang akan dibacakan oleh AI dan muncul sebagai subtitle karaoke dinamis.',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Section 3: Pilihan Suara
            const Text(
              '3. Pilih Karakter Suara AI (Edge-TTS)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Column(
              children: _voices.map((v) {
                final isSelected = _selectedVoice == v['id'];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.redAccent.withOpacity(0.15) : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? Colors.redAccent : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: RadioListTile<String>(
                    value: v['id']!,
                    groupValue: _selectedVoice,
                    title: Text(v['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(v['desc']!, style: const TextStyle(fontSize: 12)),
                    activeColor: Colors.redAccent,
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedVoice = val);
                    },
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),

            // Section 4: Pilihan Musik Latar
            const Text(
              '4. Pilih Musik Latar (BGM)',
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

            // Section 5: Unggah Media (Foto / Video)
            const Text(
              '5. Latar Belakang (Foto atau Video dari HP Anda)',
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
