/// Mirrors the backend's DisplayIdentity schema exactly. This is the ONLY
/// identity shape ever shown before a payment amount/confirm step —
/// never construct a UI that shows a name without verifiedNumberSuffix.
class DisplayIdentity {
  final String userId;
  final String name;
  final String verifiedNumberSuffix;
  final String? photoUrl;

  DisplayIdentity({
    required this.userId,
    required this.name,
    required this.verifiedNumberSuffix,
    this.photoUrl,
  });

  factory DisplayIdentity.fromJson(Map<String, dynamic> json) => DisplayIdentity(
        userId: json['user_id'],
        name: json['name'],
        verifiedNumberSuffix: json['verified_number_suffix'],
        photoUrl: json['photo_url'],
      );
}
