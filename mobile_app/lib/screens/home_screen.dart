import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
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
  final _textController = TextEditingController();
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
    final topic = _textController.text.trim();
    if (topic.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ketik ide atau topik singkat terlebih dahulu di kolom teks!'),
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
            'Untuk membuat naskah otomatis dengan AI, harap masukkan Google Gemini API Key gratis Anda di tab Pengaturan.',
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
      final promptText = 'Buatkan naskah video pendek (YouTube Shorts / TikTok / Reels) berdurasi 30-45 detik mengenai topik berikut:\n'
          '"$topic"\n\n'
          'Aturan Penting:\n'
          '1. Gunakan Bahasa Indonesia yang santai, memikat, dan memiliki HOOK rasa penasaran yang kuat di 3 detik pertama.\n'
          '2. Jangan gunakan tanda kurung, instruksi visual, intro klise seperti "Halo guys", atau emoji.\n'
          '3. Tuliskan HANYA kata-kata yang akan diucapkan narator secara langsung (voiceover only).\n'
          '4. Panjang naskah 60-80 kata.';

      final models = ['gemini-1.5-flash', 'gemini-2.0-flash'];
      String? generatedScript;
      String? errorMsg;

      for (var model in models) {
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
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            generatedScript = data['candidates'][0]['content']['parts'][0]['text']?.toString().trim();
            if (generatedScript != null && generatedScript.isNotEmpty) {
              break;
            }
          } else {
            errorMsg = '(${response.statusCode}): ${response.body}';
          }
        } catch (e) {
          errorMsg = e.toString();
        }
      }

      if (generatedScript != null && generatedScript.isNotEmpty) {
        setState(() {
          _textController.text = generatedScript!;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✨ Naskah berhasil dibuat oleh Gemini! Anda dapat membacanya atau mengeditnya.'),
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
            content: Text('Gagal membuat naskah AI: $e'),
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
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan masukkan ide topik atau naskah video terlebih dahulu.')),
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
      // 1. Create GitHub Release
      setState(() => _submitStep = '1/4 Membuat Release Job di GitHub...');
      final releaseId = await GitHubService.createRelease(
        repo: repo,
        token: token,
        tag: jobId,
        title: 'Video Job: $jobId',
      );

      // 2. Upload Config JSON
      setState(() => _submitStep = '2/4 Mengunggah naskah & konfigurasi...');
      final configData = {
        'job_id': jobId,
        'topic': text,
        'script': text,
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
        topic: text,
        script: text,
        voice: _selectedVoice,
        status: 'rendering',
        localMediaPath: _selectedMedia!.path,
        createdAt: DateTime.now(),
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
        _textController.clear();
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
            // Section 1: Ide / Naskah
            const Text(
              '1. Topik Konten atau Naskah Suara',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _textController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Tulis naskah lengkap atau ketik topik singkat (Contoh: "5 Fakta Unik Tentang Kopi yang Jarang Diketahui Orang")',
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
                  _isGeneratingScript ? 'Menulis naskah dengan AI...' : '✨ Buat Naskah dengan AI (Gemini)',
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

            // Section 2: Pilihan Suara
            const Text(
              '2. Pilih Karakter Suara AI (Edge-TTS)',
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

            // Section 3: Pilihan Musik Latar
            const Text(
              '3. Pilih Musik Latar (BGM)',
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

            // Section 4: Unggah Media (Foto / Video)
            const Text(
              '4. Latar Belakang (Foto atau Video dari HP Anda)',
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
