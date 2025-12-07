import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../env.dart';

//
// ──────────────────────────────────────────────────────────────────────────
//   HELPERS FOR DECODING DYNAMIC FIRESTORE/JSON VALUES
// ──────────────────────────────────────────────────────────────────────────
//

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  return null;
}

int? _parseInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

double? _parseDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

bool? _parseBool(dynamic v) {
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == "true";
  return null;
}

Map<String, int> _parseUsageMap(dynamic raw) {
  if (raw is Map<String, dynamic>) {
    return raw.map((k, v) => MapEntry(k, _parseInt(v) ?? 0));
  }
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k.toString(), _parseInt(v) ?? 0));
  }
  return {};
}

Map<String, dynamic> _ensureMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), val));
  }
  return {};
}

//
// ──────────────────────────────────────────────────────────────────────────
//   FIRESTORE STRUCTURE DECODER (handles API Gateway Firestore format)
// ──────────────────────────────────────────────────────────────────────────
//

dynamic _decodeValue(dynamic v) {
  if (v is Map<String, dynamic>) {
    if (v.containsKey("stringValue")) return v["stringValue"];
    if (v.containsKey("booleanValue")) return v["booleanValue"];
    if (v.containsKey("integerValue")) {
      return int.tryParse(v["integerValue"].toString());
    }
    if (v.containsKey("doubleValue")) return v["doubleValue"]?.toDouble();
    if (v.containsKey("timestampValue")) return v["timestampValue"];
    if (v.containsKey("nullValue")) return null;
    if (v.containsKey("mapValue")) {
      final fields = v["mapValue"]["fields"];
      if (fields is Map<String, dynamic>) {
        return _decodeFirestoreFields(fields);
      }
    }
    if (v.containsKey("arrayValue")) {
      final arr = v["arrayValue"]["values"] as List?;
      return arr?.map(_decodeValue).toList() ?? [];
    }
  }
  return v;
}

Map<String, dynamic> _decodeFirestoreFields(Map<String, dynamic> fields) {
  final out = <String, dynamic>{};
  fields.forEach((k, v) {
    out[k] = _decodeValue(v);
  });
  return out;
}

Map<String, dynamic> _decodeFirestoreDocument(dynamic raw) {
  if (raw is! Map<String, dynamic>) return {};
  if (!raw.containsKey("fields")) return Map<String, dynamic>.from(raw);

  final decoded = _decodeFirestoreFields(raw["fields"] ?? {});

  // Extract document id
  String? id;
  if (raw["id"] != null) {
    id = raw["id"].toString();
  } else if (raw["name"] is String) {
    id = raw["name"].split("/").last;
  }

  return {
    ...decoded,
    if (id != null) "id": id,
  };
}

//
// ──────────────────────────────────────────────────────────────────────────
//   MODEL: Plan
// ──────────────────────────────────────────────────────────────────────────
//

class Plan {
  final String id;
  final String name;
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
    required this.name,
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
    final d = _decodeFirestoreDocument(json);

    return Plan(
      id: d["id"]?.toString() ?? "",
      name: d["name"]?.toString() ?? "",
      priceMyr: _parseDouble(d["price_myr"]) ?? _parseDouble(d["priceMyr"]),
      stripeProductId: d["stripe_product_id"]?.toString(),
      stripePriceId: d["stripe_price_id"]?.toString(),
      transcriptionLimit: _parseInt(d["transcription_limit"]) ??
          _parseInt(d["transcriptionLimit"]),
      isTranscriptionUnlimited:
          _parseBool(d["is_transcription_unlimited"]) ??
              _parseBool(d["isTranscriptionUnlimited"]) ??
              false,
      canAccessPremiumCourses:
          _parseBool(d["can_access_premium_courses"]) ??
              _parseBool(d["canAccessPremiumCourses"]) ??
              false,
      trialPeriodDays:
          _parseInt(d["trial_period_days"]) ??
              _parseInt(d["trialPeriodDays"]) ??
              0,
      isActive: _parseBool(d["is_active"]) ?? false,
      createdAt:
          _parseDate(d["createdAt"] ?? d["created_at"]),
      updatedAt:
          _parseDate(d["updatedAt"] ?? d["updated_at"]),
    );
  }
}

//
// ──────────────────────────────────────────────────────────────────────────
//   MODEL: UserSubscription
// ──────────────────────────────────────────────────────────────────────────
//

class UserSubscription {
  final String id;
  final String planId;
  final String? stripeCustomerId;
  final String? stripeSubscriptionId;
  final String? stripePriceId;
  final String? stripeProductId;
  final String? status;

  final bool isTrialing;
  final DateTime? trialEndAt;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final DateTime? billingCycleAnchor;

  final Map<String, int> usageCounters;
  final Plan? plan;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  UserSubscription({
    required this.id,
    required this.planId,
    this.stripeCustomerId,
    this.stripeSubscriptionId,
    this.stripePriceId,
    this.stripeProductId,
    this.status,
    this.isTrialing = false,
    this.trialEndAt,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.billingCycleAnchor,
    this.usageCounters = const {},
    this.plan,
    this.createdAt,
    this.updatedAt,
  });

  factory UserSubscription.fromJson(
    Map<String, dynamic> json, {
    Plan? plan,
  }) {
    final d = _decodeFirestoreDocument(json);

    return UserSubscription(
      id: d["id"]?.toString() ?? "",
      planId: d["plan_id"]?.toString() ??
          d["planId"]?.toString() ??
          "",
      stripeCustomerId: d["stripe_customer_id"]?.toString(),
      stripeSubscriptionId: d["stripe_subscription_id"]?.toString(),
      stripePriceId: d["stripe_price_id"]?.toString(),
      stripeProductId: d["stripe_product_id"]?.toString(),
      status: d["status"]?.toString(),

      isTrialing:
          _parseBool(d["is_trialing"]) ??
              _parseBool(d["trialing"]) ??
              false,

      trialEndAt: _parseDate(d["trial_end_at"] ?? d["trialEndAt"]),
      currentPeriodStart:
          _parseDate(d["current_period_start"] ?? d["currentPeriodStart"]),
      currentPeriodEnd:
          _parseDate(d["current_period_end"] ?? d["currentPeriodEnd"]),
      billingCycleAnchor:
          _parseDate(d["billing_cycle_anchor"] ?? d["billingCycleAnchor"]),

      usageCounters: _parseUsageMap(
        d["usage_counters"] ?? d["usageCounters"],
      ),

      plan: plan,
      createdAt:
          _parseDate(d["createdAt"] ?? d["created_at"]),
      updatedAt:
          _parseDate(d["updatedAt"] ?? d["updated_at"]),
    );
  }
}

//
// ──────────────────────────────────────────────────────────────────────────
//   MODEL: SubscriptionMetadata
// ──────────────────────────────────────────────────────────────────────────
//

class SubscriptionMetadata {
  final int? transcriptionLimit;
  final bool isUnlimited;
  final bool canAccessPremiumCourses;
  final int freeTrialDays;

  SubscriptionMetadata({
    this.transcriptionLimit,
    this.isUnlimited = false,
    this.canAccessPremiumCourses = false,
    this.freeTrialDays = 0,
  });

  factory SubscriptionMetadata.fromJson(Map<String, dynamic> json) {
    final limitRaw = json["transcription_limit"] ??
        json["transcriptionLimit"];

    bool isUnlimited = false;
    int? limit;

    if (limitRaw is String) {
      if (limitRaw.toLowerCase() == "unlimited") {
        isUnlimited = true;
      } else {
        limit = int.tryParse(limitRaw);
      }
    } else if (limitRaw is int) {
      if (limitRaw < 0) {
        isUnlimited = true;
        limit = null;
      } else {
        limit = limitRaw;
      }
    }

    return SubscriptionMetadata(
      transcriptionLimit: isUnlimited ? null : limit,
      isUnlimited: isUnlimited,
      canAccessPremiumCourses:
          _parseBool(json["can_access_premium_courses"]) ??
              _parseBool(json["canAccessPremiumCourses"]) ??
              false,
      freeTrialDays:
          _parseInt(json["trial_period_days"]) ??
              _parseInt(json["freeTrialDays"]) ??
              0,
    );
  }
}

//
// ──────────────────────────────────────────────────────────────────────────
//   SERVICE: SubscriptionService
// ──────────────────────────────────────────────────────────────────────────
//

class SubscriptionService {
  final Dio _dio;
  final FirebaseAuth _auth;
  final String _apiBase;
  final String _publishableKey;
  final String _successUrl;
  final String _cancelUrl;
  final String _portalReturnUrl;

  SubscriptionMetadata? _metadataCache;
  Plan? _freePlanCache;

  SubscriptionService({
    Dio? dio,
    FirebaseAuth? auth,
    String? apiBase,
    String? successUrl,
    String? cancelUrl,
    String? portalReturnUrl,
    String? stripePublishableKey,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _apiBase = _normalizeBase(apiBase ?? kApiBase),
        _publishableKey =
            stripePublishableKey ??
                const String.fromEnvironment("STRIPE_PUBLISHABLE_KEY"),
        _successUrl = successUrl ?? "lipread://stripe/success",
        _cancelUrl = cancelUrl ?? "lipread://stripe/cancel",
        _portalReturnUrl = portalReturnUrl ?? "lipread://account",
        _dio = dio ?? Dio() {
    _dio.options.baseUrl = "$_apiBase/api/billing";
    _dio.options = _dio.options.copyWith(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      headers: {
        "Accept": "application/json",
      },
    );

    debugPrint(
        "[SubscriptionService] base=$_apiBase publishableKey=$_publishableKey");
  }

  Future<Map<String, String>> _authHeaders() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("User not signed in");

    final token = await user.getIdToken();

    return {
      HttpHeaders.authorizationHeader: "Bearer $token",
      "Stripe-Publishable-Key": _publishableKey,
      "Accept": "application/json",
      "Content-Type": "application/json",
    };
  }

  Future<void> refreshAllCaches() async {
    _metadataCache = null;
    _freePlanCache = null;
  }

  //
  // ────────────────────────────────────────────────
  //   PLANS
  // ────────────────────────────────────────────────
  //

  Future<List<Plan>> getPlans() async {
    try {
      final res = await _dio.get(
        "/plans",
        options: Options(headers: await _authHeaders()),
      );

      final root = _ensureMap(res.data);
      final list = (root["items"] as List?) ?? [];

      return list
          .map((e) => Plan.fromJson(_ensureMap(e)))
          .toList();
    } catch (e) {
      debugPrint("[SubscriptionService] getPlans error: $e");
      return [];
    }
  }

  //
  // ────────────────────────────────────────────────
  //   MY SUBSCRIPTION
  // ────────────────────────────────────────────────
  //

  Future<UserSubscription?> getMySubscription() async {
    try {
      final res = await _dio.get(
        "/me",
        options: Options(headers: await _authHeaders()),
      );

      final root = _ensureMap(res.data);
      debugPrint("[SubscriptionService] /me payload: $root");

      final rawSub = root["subscription"];
      if (rawSub == null) {
        return null;
      }

      final rawPlan = root["plan"];
      final plan =
          rawPlan != null ? Plan.fromJson(_ensureMap(rawPlan)) : null;

      return UserSubscription.fromJson(
        _ensureMap(rawSub),
        plan: plan,
      );
    } catch (e) {
      debugPrint("[SubscriptionService] getMySubscription error: $e");
      return null;
    }
  }

  //
  // ────────────────────────────────────────────────
  //   CHECKOUT SESSION
  // ────────────────────────────────────────────────
  //

  Future<String> createCheckoutSession(String priceId) async {
    final body = jsonEncode({
      "price_id": priceId,
      "success_url": _successUrl,
      "cancel_url": _cancelUrl,
    });

    try {
      final res = await _dio.post(
        "/checkout-session",
        data: body,
        options: Options(
          headers: await _authHeaders(),
          contentType: Headers.jsonContentType,
        ),
      );

      final data = _ensureMap(res.data);
      final url = data["url"]?.toString();
      if (url == null || url.isEmpty) {
        throw Exception("Billing URL is empty");
      }
      return url;
    } catch (e) {
      debugPrint("[SubscriptionService] createCheckoutSession error: $e");
      rethrow;
    }
  }

  //
  // ────────────────────────────────────────────────
  //   BILLING PORTAL
  // ────────────────────────────────────────────────
  //

  Future<String> createBillingPortalSession() async {
    final body = jsonEncode({"return_url": _portalReturnUrl});

    try {
      final res = await _dio.post(
        "/customer-portal",
        data: body,
        options: Options(
          headers: await _authHeaders(),
          contentType: Headers.jsonContentType,
        ),
      );

      final data = _ensureMap(res.data);
      final url = data["url"]?.toString();
      if (url == null || url.isEmpty) {
        throw Exception("Billing URL is empty");
      }

      await refreshAllCaches();
      return url;
    } catch (e) {
      debugPrint("[SubscriptionService] customer portal error: $e");
      rethrow;
    }
  }

  //
  // ────────────────────────────────────────────────
  //   METADATA + FREE PLAN
  // ────────────────────────────────────────────────
  //

  Future<SubscriptionMetadata> getSubscriptionMetadata() async {
    if (_metadataCache != null) return _metadataCache!;

    try {
      final res = await _dio.get(
        "/metadata",
        options: Options(headers: await _authHeaders()),
      );

      final data = _ensureMap(res.data);
      debugPrint("[SubscriptionService] /metadata payload: $data");

      _metadataCache = SubscriptionMetadata.fromJson(data);
      _freePlanCache = _buildFreePlanFromMetadata(_metadataCache!);
      return _metadataCache!;
    } catch (_) {}

    // Fallback
    try {
      final snap = await FirebaseFirestore.instance
          .collection("config")
          .doc("subscription_metadata")
          .get();

      final data = snap.data() ?? {};
      debugPrint("[SubscriptionService] Firestore metadata fallback: $data");

      _metadataCache = SubscriptionMetadata.fromJson(data);
      _freePlanCache = _buildFreePlanFromMetadata(_metadataCache!);
      return _metadataCache!;
    } catch (_) {}

    return SubscriptionMetadata(
      transcriptionLimit: 0,
      isUnlimited: false,
      canAccessPremiumCourses: false,
      freeTrialDays: 0,
    );
  }

  Future<Plan> getFreePlan() async {
    if (_freePlanCache != null) return _freePlanCache!;
    final meta = await getSubscriptionMetadata();
    _freePlanCache = _buildFreePlanFromMetadata(meta);
    return _freePlanCache!;
  }

  Plan _buildFreePlanFromMetadata(SubscriptionMetadata meta) {
    return Plan(
      id: "free",
      name: "Free Plan",
      priceMyr: 0,
      transcriptionLimit: meta.transcriptionLimit,
      isTranscriptionUnlimited: meta.isUnlimited,
      canAccessPremiumCourses: meta.canAccessPremiumCourses,
      trialPeriodDays: meta.freeTrialDays,
      isActive: true,
    );
  }
}

//
// ──────────────────────────────────────────────────────────────────────────
//   URL NORMALIZER
// ──────────────────────────────────────────────────────────────────────────
//

String _normalizeBase(String v) {
  return v.replaceFirst(RegExp(r"/+$"), "");
}