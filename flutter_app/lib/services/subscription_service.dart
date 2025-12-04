import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../env.dart';

class Plan {
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
    final normalized = _decodeFirestoreDocument(json);
    return Plan(
      id: normalized['id']?.toString() ?? '',
      name: normalized['name']?.toString() ?? '',
      priceMyr: _asDouble(normalized['price_myr'] ?? normalized['priceMyr']),
      stripeProductId: normalized['stripe_product_id']?.toString(),
      stripePriceId: normalized['stripe_price_id']?.toString(),
      transcriptionLimit:
          _asInt(normalized['transcription_limit'] ?? normalized['transcriptionLimit']),
      isTranscriptionUnlimited:
          _asBool(normalized['is_transcription_unlimited'] ?? normalized['isTranscriptionUnlimited']) ??
              false,
      canAccessPremiumCourses:
          _asBool(normalized['can_access_premium_courses'] ?? normalized['canAccessPremiumCourses']) ??
              false,
      trialPeriodDays: _asInt(normalized['trial_period_days'] ?? normalized['trialPeriodDays']) ?? 0,
      isActive: _asBool(normalized['is_active'] ?? normalized['isActive']) ?? false,
      createdAt: _asDate(normalized['createdAt'] ?? normalized['created_at']),
      updatedAt: _asDate(normalized['updatedAt'] ?? normalized['updated_at']),
    );
  }

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
}

class UserSubscription {
  UserSubscription({
    required this.id,
    required this.planId,
    this.stripeCustomerId,
    this.stripeSubscriptionId,
    this.status,
    this.isTrialing = false,
    this.trialEndAt,
    this.currentPeriodEnd,
    this.usageCounters = const {},
    this.plan,
    this.createdAt,
    this.updatedAt,
  });

  factory UserSubscription.fromJson(
    Map<String, dynamic> json, {
    Plan? plan,
  }) {
    final normalized = _decodeFirestoreDocument(json);
    return UserSubscription(
      id: normalized['id']?.toString() ?? '',
      planId: normalized['plan_id']?.toString() ?? normalized['planId']?.toString() ?? '',
      stripeCustomerId: normalized['stripe_customer_id']?.toString(),
      stripeSubscriptionId: normalized['stripe_subscription_id']?.toString(),
      status: normalized['status']?.toString(),
      isTrialing: _asBool(normalized['is_trialing'] ?? normalized['trialing']) ?? false,
      trialEndAt: _asDate(normalized['trial_end_at'] ?? normalized['trialEndAt']),
      currentPeriodEnd:
          _asDate(normalized['current_period_end'] ?? normalized['currentPeriodEnd']),
      usageCounters: _asStringIntMap(normalized['usage_counters'] ?? normalized['usageCounters']),
      plan: plan,
      createdAt: _asDate(normalized['createdAt'] ?? normalized['created_at']),
      updatedAt: _asDate(normalized['updatedAt'] ?? normalized['updated_at']),
    );
  }

  final String id;
  final String planId;
  final String? stripeCustomerId;
  final String? stripeSubscriptionId;
  final String? status;
  final bool isTrialing;
  final DateTime? trialEndAt;
  final DateTime? currentPeriodEnd;
  final Map<String, int> usageCounters;
  final Plan? plan;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

class SubscriptionService {
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
        _publishableKey = stripePublishableKey ?? const String.fromEnvironment('STRIPE_PUBLISHABLE_KEY'),
        _successUrl = successUrl ?? 'https://lipread.app/stripe/success',
        _cancelUrl = cancelUrl ?? 'https://lipread.app/stripe/cancel',
        _portalReturnUrl = portalReturnUrl ?? 'https://lipread.app/account',
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: '$_apiBase/api/billing',
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
                sendTimeout: const Duration(seconds: 20),
                headers: const {'Accept': 'application/json'},
              ),
            ) {
    debugPrint('[SubscriptionService] base=$_apiBase publishableKey=$_publishableKey');
  }

  final Dio _dio;
  final FirebaseAuth _auth;
  final String _apiBase;
  final String _publishableKey;
  final String _successUrl;
  final String _cancelUrl;
  final String _portalReturnUrl;

  Future<List<Plan>> getPlans() async {
    final res = await _dio.get(
      '/plans',
      options: Options(headers: await _authHeaders()),
    );
    final data = res.data;
    final rawList = (data is Map<String, dynamic>)
        ? (data['items'] as List?) ?? (data['documents'] as List?) ?? []
        : [];
    return rawList
        .whereType<dynamic>()
        .map((item) => Plan.fromJson(_decodeFirestoreDocument(_asMap(item))))
        .toList();
  }

  Future<UserSubscription?> getMySubscription() async {
    final res = await _dio.get(
      '/me',
      options: Options(headers: await _authHeaders()),
    );
    final data = _asMap(res.data);
    final rawSubscription = data['subscription'];
    if (rawSubscription == null) return null;

    final planData = data['plan'];
    final plan = planData != null
        ? Plan.fromJson(_decodeFirestoreDocument(_asMap(planData)))
        : null;
    return UserSubscription.fromJson(
      _decodeFirestoreDocument(_asMap(rawSubscription)),
      plan: plan,
    );
  }

  Future<String> createCheckoutSession(String priceId) async {
    final payload = {
      'price_id': priceId,
      'success_url': _successUrl,
      'cancel_url': _cancelUrl,
    };
    final res = await _dio.post(
      '/checkout-session',
      data: jsonEncode(payload),
      options: Options(
        headers: await _authHeaders(),
        contentType: Headers.jsonContentType,
      ),
    );
    final data = _asMap(res.data);
    final url = data['url']?.toString();
    if (url == null || url.isEmpty) {
      throw Exception('Checkout session did not return a URL');
    }
    return url;
  }

  Future<String> createBillingPortalSession() async {
    final payload = {'return_url': _portalReturnUrl};
    final res = await _dio.post(
      '/customer-portal',
      data: jsonEncode(payload),
      options: Options(
        headers: await _authHeaders(),
        contentType: Headers.jsonContentType,
      ),
    );
    final data = _asMap(res.data);
    final url = data['url']?.toString();
    if (url == null || url.isEmpty) {
      throw Exception('Billing portal session did not return a URL');
    }
    return url;
  }

  Future<Map<String, String>> _authHeaders() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not signed in');
    final token = await user.getIdToken();
    return {
      HttpHeaders.authorizationHeader: 'Bearer $token',
      'Stripe-Publishable-Key': _publishableKey,
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }
}

Map<String, dynamic> _decodeFirestoreDocument(dynamic raw) {
  if (raw is! Map<String, dynamic>) return {};
  if (!raw.containsKey('fields')) return Map<String, dynamic>.from(raw);

  final fields = raw['fields'];
  final decodedFields = fields is Map<String, dynamic>
      ? _decodeFirestoreFields(fields)
      : <String, dynamic>{};

  String? id;
  if (raw['id'] != null) {
    id = raw['id'].toString();
  } else if (raw['name'] is String) {
    final name = raw['name'] as String;
    if (name.contains('/')) {
      id = name.split('/').last;
    }
  }

  return {
    ...decodedFields,
    if (id != null) 'id': id,
  };
}

Map<String, dynamic> _decodeFirestoreFields(Map<String, dynamic> fields) {
  final map = <String, dynamic>{};
  fields.forEach((key, value) {
    map[key] = _decodeFirestoreValue(value);
  });
  return map;
}

dynamic _decodeFirestoreValue(dynamic value) {
  if (value is Map<String, dynamic>) {
    if (value.containsKey('stringValue')) return value['stringValue'];
    if (value.containsKey('integerValue')) return int.tryParse(value['integerValue'].toString());
    if (value.containsKey('doubleValue')) return (value['doubleValue'] as num?)?.toDouble();
    if (value.containsKey('booleanValue')) return value['booleanValue'] as bool?;
    if (value.containsKey('timestampValue')) return value['timestampValue'];
    if (value.containsKey('nullValue')) return null;
    if (value.containsKey('mapValue')) {
      final mapFields = value['mapValue']['fields'];
      if (mapFields is Map<String, dynamic>) {
        return _decodeFirestoreFields(mapFields);
      }
    }
    if (value.containsKey('arrayValue')) {
      final arr = value['arrayValue']['values'] as List?;
      return arr?.map(_decodeFirestoreValue).toList();
    }
    if (value.containsKey('fields')) {
      return _decodeFirestoreFields(value['fields'] as Map<String, dynamic>);
    }
  }
  return value;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, val) => MapEntry(key.toString(), val));
  return {};
}

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

bool? _asBool(dynamic value) {
  if (value is bool) return value;
  if (value is String) return value.toLowerCase() == 'true';
  return null;
}

DateTime? _asDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

Map<String, int> _asStringIntMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value.map((key, val) => MapEntry(key, _asInt(val) ?? 0));
  }
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), _asInt(val) ?? 0));
  }
  return {};
}

String _normalizeBase(String value) {
  final trimmed = value.replaceFirst(RegExp(r'/+$'), '');
  return trimmed.isEmpty ? value : trimmed;
}
