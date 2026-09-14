class LipilaUser {
  final String id;
  final String mobileNumber;
  final String legalName;
  final String? nickname;
  final String? photoUrl;
  final String provider;
  final bool isMerchant;
  final bool isAgent;
  final String staticQrToken;

  LipilaUser({
    required this.id,
    required this.mobileNumber,
    required this.legalName,
    this.nickname,
    this.photoUrl,
    required this.provider,
    required this.isMerchant,
    required this.isAgent,
    required this.staticQrToken,
  });

  String get displayName => nickname ?? legalName;

  /// Full-length-accurate mask — asterisks for every digit except the last
  /// three, matching the actual number's length rather than a fixed guess.
  String get maskedNumber {
    if (mobileNumber.length <= 3) return mobileNumber;
    final visible = mobileNumber.substring(mobileNumber.length - 3);
    final hidden = '*' * (mobileNumber.length - 3);
    return hidden + visible;
  }

  factory LipilaUser.fromJson(Map<String, dynamic> json) => LipilaUser(
        id: json['id'],
        mobileNumber: json['mobile_number'],
        legalName: json['legal_name'],
        nickname: json['nickname'],
        photoUrl: json['photo_url'],
        provider: json['provider'],
        isMerchant: json['is_merchant'] ?? false,
        isAgent: json['is_agent'] ?? false,
        staticQrToken: json['static_qr_token'],
      );
}
