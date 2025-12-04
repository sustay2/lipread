import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../env.dart';
import '../models/subscription_models.dart';

class SubscriptionService {
  final String publishableKey = kStripePublishableKey;

  SubscriptionService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: kApiBase,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
                headers: const {
                  'Accept': 'application/json',
                },
              ),
            );

  final Dio _dio;

  /// Fetch all active subscription plans.
  Future<List<Plan>> getPlans() async {
    final res = await _dio.get('/api/billing/plans');
    final data = res.data as Map<String, dynamic>? ?? {};
    final items = data['items'] as List? ?? [];
    return items
        .whereType<Map>()
        .map((item) => Plan.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  /// Fetch the current user's subscription (and attached plan if present).
  Future<UserSubscription?> getMySubscription() async {
    final res = await _dio.get('/api/billing/me');
    final data = res.data as Map<String, dynamic>? ?? {};
    final subJson = data['subscription'];
    if (subJson is! Map) return null;

    Plan? plan;
    final planJson = data['plan'];
    if (planJson is Map) {
      plan = Plan.fromJson(Map<String, dynamic>.from(planJson));
    }

    return UserSubscription.fromJson(
      Map<String, dynamic>.from(subJson),
      plan: plan,
    );
  }

  /// Create a Stripe Checkout session for subscriptions and return the redirect URL.
  ///
  /// Success/cancel URLs are derived from API_BASE so the backend can redirect
  /// users back into the app or a hosted confirmation page.
  Future<String> createCheckoutSession(String priceId) async {
    final successUrl = '$kApiBase/billing/success';
    final cancelUrl = '$kApiBase/billing/cancel';

    final res = await _dio.post(
      '/api/billing/checkout-session',
      data: {
        'price_id': priceId,
        'success_url': successUrl,
        'cancel_url': cancelUrl,
      },
    );

    final body = res.data as Map<String, dynamic>? ?? {};
    final url = body['url'] as String?;
    if (url == null || url.isEmpty) {
      debugPrint('[SubscriptionService] Missing checkout session URL: ${res.data}');
      throw Exception('Checkout session could not be created.');
    }
    return url;
  }

  /// Create a Stripe Billing Portal session and return the redirect URL.
  ///
  /// When a customer ID is absent locally, this method attempts to fetch the
  /// current subscription first to reuse the stored Stripe customer reference.
  Future<String> createBillingPortalSession() async {
    String? stripeCustomerId;

    try {
      final sub = await getMySubscription();
      stripeCustomerId = sub?.stripeCustomerId;
    } catch (e) {
      debugPrint('[SubscriptionService] Failed to load subscription before portal: $e');
    }

    final returnUrl = '$kApiBase/billing/portal-return';

    final res = await _dio.post(
      '/api/billing/customer-portal',
      data: {
        'return_url': returnUrl,
        if (stripeCustomerId != null) 'stripe_customer_id': stripeCustomerId,
      },
    );

    final body = res.data as Map<String, dynamic>? ?? {};
    final url = body['url'] as String?;
    if (url == null || url.isEmpty) {
      debugPrint('[SubscriptionService] Missing billing portal URL: ${res.data}');
      throw Exception('Billing portal session could not be created.');
    }
    return url;
  }
}
