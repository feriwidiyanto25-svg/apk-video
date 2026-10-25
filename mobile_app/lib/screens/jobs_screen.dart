import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
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
          ));
          hasChanges = true;
        } else {
          final existing = _jobs.firstWhere((j) => j.id == id);
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
      _openPlayer(job.localVideoPath!, job.topic.isNotEmpty ? job.topic : job.id);
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
        _openPlayer(savePath, job.topic.isNotEmpty ? job.topic : job.id);
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

  void _openPlayer(String path, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(videoPath: path, title: title),
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
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: const Color(0xFF1E293B),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildThumbnail(job),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                job.topic.isNotEmpty ? job.topic : job.id,
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
                            if (val == 'delete') _deleteJob(index);
                          },
                          itemBuilder: (c) => [
                            const PopupMenuItem(value: 'delete', child: Text('Hapus Riwayat')),
                          ],
                        ),
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

