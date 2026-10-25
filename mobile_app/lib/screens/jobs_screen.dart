import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import '../models/job_model.dart';
import '../services/github_service.dart';
import 'player_screen.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  List<JobModel> _jobs = [];
  Timer? _pollingTimer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadJobs();
    _syncFromCloud();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadJobs() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJobs = prefs.getStringList('jobs_history') ?? [];
    setState(() {
      _jobs = rawJobs
          .map((item) => JobModel.fromJson(jsonDecode(item)))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _isLoading = false;
    });
  }

  Future<void> _saveJobs() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJobs = _jobs.map((j) => jsonEncode(j.toJson())).toList();
    await prefs.setStringList('jobs_history', rawJobs);
  }

  Future<void> _syncFromCloud() async {
    final prefs = await SharedPreferences.getInstance();
    final repo = prefs.getString('github_repo') ?? '';
    final token = prefs.getString('github_token') ?? '';

    if (repo.isEmpty || token.isEmpty) return;

    try {
      final cloudJobs = await GitHubService.fetchJobReleases(repo: repo, token: token);
      final existingIds = _jobs.map((j) => j.id).toSet();
      bool hasChanges = false;

      for (var cj in cloudJobs) {
        final id = cj['id'] as String;
        if (!existingIds.contains(id)) {
          _jobs.add(JobModel(
            id: id,
            topic: cj['title'] ?? id,
            script: '',
            voice: '',
            status: cj['status'],
            videoUrl: cj['videoUrl'],
            createdAt: cj['createdAt'],
            videoTitle: cj['title'],
            videoDescription: cj['description'],
          ));
          hasChanges = true;
        } else {
          final existing = _jobs.firstWhere((j) => j.id == id);
          if (cj['title'] != null && (existing.videoTitle == null || existing.videoTitle!.isEmpty)) {
            existing.videoTitle = cj['title'];
            hasChanges = true;
          }
          if (cj['description'] != null && (existing.videoDescription == null || existing.videoDescription!.isEmpty)) {
            existing.videoDescription = cj['description'];
            hasChanges = true;
          }
          if (existing.status != 'completed' && cj['status'] == 'completed') {
            existing.status = 'completed';
            existing.videoUrl = cj['videoUrl'];
            hasChanges = true;
          }
        }
      }

      if (hasChanges && mounted) {
        _jobs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        setState(() {});
        await _saveJobs();
      }
    } catch (_) {}
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 8), (timer) {
      _checkPendingJobs();
    });
  }

  Future<void> _checkPendingJobs() async {
    final prefs = await SharedPreferences.getInstance();
    final repo = prefs.getString('github_repo') ?? '';
    final token = prefs.getString('github_token') ?? '';

    if (repo.isEmpty || token.isEmpty) return;

    bool hasChanges = false;
    for (var job in _jobs) {
      if (job.status == 'rendering' || job.status == 'uploading') {
        try {
          final res = await GitHubService.checkJobStatus(
            repo: repo,
            token: token,
            tag: job.id,
          );

          if (res['status'] == 'completed') {
            job.status = 'completed';
            job.videoUrl = res['downloadUrl'];
            hasChanges = true;
          } else if (res['status'] == 'failed') {
            job.status = 'failed';
            job.error = res['error'];
            hasChanges = true;
          }
        } catch (_) {}
      }
    }

    if (hasChanges && mounted) {
      setState(() {});
      await _saveJobs();
    }
  }

  Future<void> _downloadAndPlay(JobModel job) async {
    if (job.localVideoPath != null && File(job.localVideoPath!).existsSync()) {
      _openPlayer(job, job.localVideoPath!);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('github_token') ?? '';

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.redAccent),
                  SizedBox(height: 16),
                  Text('Mengunduh video hasil render...'),
                ],
              ),
            ),
          ),
        ),
      );

      final dir = await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/${job.id}_shorts.mp4';

      await GitHubService.downloadFile(
        token: token,
        url: job.videoUrl!,
        savePath: savePath,
      );

      job.localVideoPath = savePath;
      await _saveJobs();

      if (mounted) {
        Navigator.pop(context); // close dialog
        _openPlayer(job, savePath);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal unduh video: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _openPlayer(JobModel job, String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          videoPath: path,
          title: job.videoTitle?.isNotEmpty == true ? job.videoTitle! : (job.topic.isNotEmpty ? job.topic : job.id),
          job: job,
        ),
      ),
    );
  }

  void _copyToClipboard(String text, String label) {
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label masih kosong.')),
      );
      return;
    }
    Clipboard.setData(ClipboardData(text: text.trim()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ $label berhasil disalin ke clipboard!'),
        backgroundColor: Colors.green[700],
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showCopySheet(JobModel job) {
    final title = (job.videoTitle != null && job.videoTitle!.trim().isNotEmpty)
        ? job.videoTitle!.trim()
        : job.topic.trim();
    final desc = job.videoDescription?.trim() ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[600],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(Icons.content_paste_go, color: Colors.indigoAccent),
                    SizedBox(width: 8),
                    Text(
                      'Salin Konten Video',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Salin langsung untuk posting ke YouTube Shorts atau Facebook Reels (FB Pro).',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
                const SizedBox(height: 16),

                // Card Judul
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '📌 Judul Video:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              _copyToClipboard(title, 'Judul');
                              Navigator.pop(ctx);
                            },
                            icon: const Icon(Icons.copy, size: 14),
                            label: const Text('Salin Judul', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        title.isNotEmpty ? title : '(Tidak ada judul)',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Card Deskripsi
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '📝 Deskripsi & Hashtag:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              _copyToClipboard(desc, 'Deskripsi');
                              Navigator.pop(ctx);
                            },
                            icon: const Icon(Icons.copy, size: 14),
                            label: const Text('Salin Deskripsi', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        desc.isNotEmpty ? desc : '(Tidak ada deskripsi)',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Tombol Salin Semua
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final combined = desc.isNotEmpty ? '$title\n\n$desc' : title;
                      _copyToClipboard(combined, 'Judul & Deskripsi');
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.copy_all),
                    label: const Text(
                      '🚀 Salin Semua (Judul + Deskripsi)',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteJob(int index) async {
    setState(() {
      _jobs.removeAt(index);
    });
    await _saveJobs();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Video Shorts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Sinkronisasi dari Cloud',
            onPressed: () async {
              await _syncFromCloud();
              await _checkPendingJobs();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Menyinkronkan riwayat dari cloud...'), duration: Duration(seconds: 1)),
                );
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _syncFromCloud();
          await _checkPendingJobs();
        },
        child: _jobs.isEmpty
            ? ListView(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.3),
                  Icon(Icons.video_library_outlined, size: 70, color: Colors.grey[700]),
                  const SizedBox(height: 16),
                  const Center(
                    child: Text(
                      'Belum ada video yang dibuat.',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Center(
                    child: Text(
                      'Buka tab "Buat Video" untuk memulai, atau tarik ke bawah untuk sinkronisasi.',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _jobs.length,
                itemBuilder: (ctx, index) {
                  final job = _jobs[index];
                  final displayTitle = job.videoTitle?.isNotEmpty == true
                      ? job.videoTitle!
                      : (job.topic.isNotEmpty ? job.topic : job.id);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: const Color(0xFF1E293B),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildThumbnail(job),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayTitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    const SizedBox(height: 6),
                                    _buildStatusBadge(job.status),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Dibuat: ${_formatDate(job.createdAt)}',
                                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (val) {
                                  if (val == 'copy') {
                                    _showCopySheet(job);
                                  } else if (val == 'delete') {
                                    _deleteJob(index);
                                  }
                                },
                                itemBuilder: (c) => [
                                  const PopupMenuItem(
                                    value: 'copy',
                                    child: Row(
                                      children: [
                                        Icon(Icons.content_paste_go, size: 16, color: Colors.indigoAccent),
                                        SizedBox(width: 8),
                                        Text('Salin Judul & Deskripsi'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                                        SizedBox(width: 8),
                                        Text('Hapus Riwayat'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (job.status == 'completed') ...[
                            const SizedBox(height: 10),
                            const Divider(color: Colors.white10, height: 1),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _downloadAndPlay(job),
                                    icon: const Icon(Icons.play_arrow, size: 18),
                                    label: const Text('Tonton Video', style: TextStyle(fontSize: 12)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.redAccent,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _showCopySheet(job),
                                  icon: const Icon(Icons.copy_all, size: 16, color: Colors.indigoAccent),
                                  label: const Text('Salin Teks', style: TextStyle(fontSize: 12, color: Colors.indigoAccent)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.indigoAccent),
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildThumbnail(JobModel job) {
    if (job.status == 'completed') {
      return InkWell(
        onTap: () => _downloadAndPlay(job),
        child: Container(
          width: 65,
          height: 95,
          decoration: BoxDecoration(
            color: Colors.redAccent.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.redAccent),
          ),
          child: const Center(
            child: Icon(Icons.play_circle_fill, size: 36, color: Colors.redAccent),
          ),
        ),
      );
    } else if (job.status == 'failed') {
      return Container(
        width: 65,
        height: 95,
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Icon(Icons.error_outline, size: 32, color: Colors.red),
        ),
      );
    } else {
      return Container(
        width: 65,
        height: 95,
        decoration: BoxDecoration(
          color: Colors.blueGrey.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
          ),
        ),
      );
    }
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case 'completed':
        bg = Colors.green.withOpacity(0.2);
        fg = Colors.greenAccent;
        label = 'Selesai (Siap Tonton)';
        break;
      case 'failed':
        bg = Colors.red.withOpacity(0.2);
        fg = Colors.redAccent;
        label = 'Gagal Render';
        break;
      case 'uploading':
        bg = Colors.orange.withOpacity(0.2);
        fg = Colors.orangeAccent;
        label = 'Mengunggah Bahan...';
        break;
      default:
        bg = Colors.blue.withOpacity(0.2);
        fg = Colors.blueAccent;
        label = 'Sedang Merender di Cloud...';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
