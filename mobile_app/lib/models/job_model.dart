class JobModel {
  final String id;
  final String topic;
  final String script;
  final String voice;
  String status; // 'uploading', 'rendering', 'completed', 'failed'
  final String? localMediaPath;
  String? videoUrl;
  String? localVideoPath;
  final DateTime createdAt;
  String? error;
  String? videoTitle;
  String? videoDescription;

  JobModel({
    required this.id,
    required this.topic,
    required this.script,
    required this.voice,
    required this.status,
    this.localMediaPath,
    this.videoUrl,
    this.localVideoPath,
    required this.createdAt,
    this.error,
    this.videoTitle,
    this.videoDescription,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'topic': topic,
      'script': script,
      'voice': voice,
      'status': status,
      'localMediaPath': localMediaPath,
      'videoUrl': videoUrl,
      'localVideoPath': localVideoPath,
      'createdAt': createdAt.toIso8601String(),
      'error': error,
      'videoTitle': videoTitle,
      'videoDescription': videoDescription,
    };
  }

  factory JobModel.fromJson(Map<String, dynamic> json) {
    return JobModel(
      id: json['id'],
      topic: json['topic'] ?? '',
      script: json['script'] ?? '',
      voice: json['voice'] ?? 'id-ID-GadisNeural',
      status: json['status'] ?? 'pending',
      localMediaPath: json['localMediaPath'],
      videoUrl: json['videoUrl'],
      localVideoPath: json['localVideoPath'],
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      error: json['error'],
      videoTitle: json['videoTitle'] ?? json['topic'] ?? '',
      videoDescription: json['videoDescription'] ?? '',
    );
  }
}
