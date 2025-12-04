class Plan {
  final String id;
  final String? name;
  final double? priceMyr;
  final String? stripeProductId;
  final String? stripePriceId;
  final int? transcriptionLimit;
  final bool isTranscriptionUnlimited;
  final bool canAccessPremiumCourses;
  final int trialPeriodDays;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Plan({
    required this.id,
    this.name,
    this.priceMyr,
    this.stripeProductId,
    this.stripePriceId,
    this.transcriptionLimit,
    this.isTranscriptionUnlimited = false,
    this.canAccessPremiumCourses = false,
    this.trialPeriodDays = 0,
    this.isActive = false,
    this.createdAt,
    this.updatedAt,
  });

  factory Plan.fromJson(Map<String, dynamic> json) {
    return Plan(
      id: json['id'] as String? ?? json['docId'] as String? ?? '',
      name: json['name'] as String?,
      priceMyr: (json['price_myr'] as num?)?.toDouble(),
      stripeProductId: json['stripe_product_id'] as String?,
      stripePriceId: json['stripe_price_id'] as String?,
      transcriptionLimit: (json['transcription_limit'] as num?)?.toInt(),
      isTranscriptionUnlimited: json['is_transcription_unlimited'] == true,
      canAccessPremiumCourses: json['can_access_premium_courses'] == true,
      trialPeriodDays: (json['trial_period_days'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] == true,
      createdAt: _parseTimestamp(json['createdAt']),
      updatedAt: _parseTimestamp(json['updatedAt']),
    );
  }
}

class UserSubscription {
  final String id;
  final String? planId;
  final String? stripeCustomerId;
  final String? stripeSubscriptionId;
  final String? status;
  final bool isTrialing;
  final DateTime? trialEndAt;
  final DateTime? currentPeriodEnd;
  final Map<String, dynamic> usageCounters;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Plan? plan;

  UserSubscription({
    required this.id,
    this.planId,
    this.stripeCustomerId,
    this.stripeSubscriptionId,
    this.status,
    this.isTrialing = false,
    this.trialEndAt,
    this.currentPeriodEnd,
    this.usageCounters = const {},
    this.createdAt,
    this.updatedAt,
    this.plan,
  });

  factory UserSubscription.fromJson(
    Map<String, dynamic> json, {
    Plan? plan,
  }) {
    return UserSubscription(
      id: json['id'] as String? ?? json['docId'] as String? ?? '',
      planId: json['plan_id'] as String?,
      stripeCustomerId: json['stripe_customer_id'] as String?,
      stripeSubscriptionId: json['stripe_subscription_id'] as String?,
      status: json['status'] as String?,
      isTrialing: json['is_trialing'] == true,
      trialEndAt: _parseTimestamp(json['trial_end_at']),
      currentPeriodEnd: _parseTimestamp(json['current_period_end']),
      usageCounters: json['usage_counters'] is Map
          ? Map<String, dynamic>.from(json['usage_counters'] as Map)
          : const {},
      createdAt: _parseTimestamp(json['createdAt']),
      updatedAt: _parseTimestamp(json['updatedAt']),
      plan: plan,
    );
  }
}

DateTime? _parseTimestamp(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) {
    return DateTime.tryParse(value);
  }
  if (value is Map) {
    final seconds = value['_seconds'] ?? value['seconds'];
    final nanos = value['_nanoseconds'] ?? value['nanoseconds'] ?? 0;
    if (seconds is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        (seconds * 1000).toInt() + (nanos is num ? nanos ~/ 1000000 : 0),
        isUtc: true,
      );
    }
  }
  return null;
}
