import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  File? _selectedMedia;
  String? _selectedMediaName;
  int _selectedMediaSize = 0;
  bool _isImage = true;
  bool _isSubmitting = false;
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

            // Section 3: Unggah Media (Foto / Video)
            const Text(
              '3. Latar Belakang (Foto atau Video dari HP Anda)',
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

