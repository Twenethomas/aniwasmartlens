class GhanaTTSRequest {
  final String text;
  final String language;
  final String speakerId;

  GhanaTTSRequest({
    required this.text,
    this.language = 'en',
    this.speakerId = 'default',
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'language': language,
    'speaker_id': speakerId,
  };
}