import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/theme/app_colors.dart';
import '../../services/router.dart';
import '../../services/subscription_service.dart';

class BillingInfoPage extends StatefulWidget {
  // FIX: Add paymentSuccess parameter
  const BillingInfoPage({super.key, this.paymentSuccess = false});

  final bool paymentSuccess;

  @override
  State<BillingInfoPage> createState() => _BillingInfoPageState();
}

class _BillingInfoPageState extends State<BillingInfoPage> {
  final SubscriptionService _service = SubscriptionService();
  Future<_BillingPayload>? _future;
  bool _openingPortal = false;

  @override
  void initState() {
    super.initState();
    _future = _load();

    // FIX: Show success message if redirected from payment
    if (widget.paymentSuccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSnack('Payment successful! Your plan has been updated.');
      });
    }
  }

  Future<_BillingPayload> _load() async {
    await _service.refreshAllCaches();
    final results = await Future.wait([
      _service.getMySubscription(),
      _service.getPlans(),
      _service.getFreePlan(),
    ]);

    final subscription = results[0] as UserSubscription?;
    final plans = results[1] as List<Plan>;
    final freePlan = results[2] as Plan;

    final plan = _resolvePlan(plans, subscription, freePlan);
    
    return _BillingPayload(plan: plan, subscription: subscription);
  }

  Plan? _resolvePlan(List<Plan> plans, UserSubscription? subscription, Plan freePlan) {
    if (subscription?.plan != null) return subscription!.plan;
    if (subscription == null) return freePlan;
    try {
      return plans.firstWhere((p) => p.id == subscription.planId);
    } catch (_) {
      return freePlan;
    }
  }

  Future<void> _refresh() async {
    final newFuture = _load();
    setState(() => _future = newFuture);
    await newFuture;
  }

  Future<void> _openPortal() async {
    setState(() => _openingPortal = true);
    try {
      final url = await _service.createBillingPortalSession();
      if (!mounted) return;
      await _launchUrl(url);
    } catch (e) {
      _showSnack('Unable to open billing portal: $e');
    } finally {
      if (mounted) setState(() => _openingPortal = false);
    }
  }

  Future<void> _launchUrl(String url) async {
    if (url.isEmpty) {
      _showSnack('Billing URL is empty');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showSnack('Invalid URL');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      _showSnack('Could not launch link');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Billing & Subscription'),
        centerTitle: true,
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_BillingPayload>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _ErrorCard(
                    error: snapshot.error.toString(),
                    onRetry: _refresh,
                  ),
                ],
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting ||
                !snapshot.hasData) {
              return const _LoadingCard();
            }

            final payload = snapshot.data!;
            final plan = payload.plan;
            final subscription = payload.subscription;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _BillingSummaryCard(
                  plan: plan,
                  subscription: subscription,
                  onManageBilling: subscription != null ? _openPortal : null,
                  openingPortal: _openingPortal,
                ),
                const SizedBox(height: 12),
                _QuotaCard(plan: plan, subscription: subscription),
                const SizedBox(height: 20),
                if (_isFreePlan(plan))
                  FilledButton(
                    onPressed: () => Navigator.pushNamed(
                      context,
                      Routes.subscription,
                    ),
                    child: const Text('Upgrade'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  bool _isFreePlan(Plan? plan) {
    if (plan == null) return true;
    final price = plan.priceMyr ?? 0;
    return price <= 0;
  }
}

class _BillingSummaryCard extends StatelessWidget {
  const _BillingSummaryCard({
    required this.plan,
    required this.subscription,
    this.onManageBilling,
    this.openingPortal = false,
  });

  final Plan? plan;
  final UserSubscription? subscription;
  final VoidCallback? onManageBilling;
  final bool openingPortal;

  String get _planName => plan?.name ?? 'Free plan';

  String get _statusText {
    final status = subscription?.status?.toLowerCase();
    if (status == null) return 'Not subscribed';
    return status;
  }

  String get _nextBilling {
    final end = subscription?.currentPeriodEnd ??
            subscription?.trialEndAt ??
            subscription?.billingCycleAnchor;
    if (end == null) return 'Not scheduled';
    return DateFormat('d MMM y').format(end.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shadowColor: AppColors.softShadow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.credit_card,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _planName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Status: ${_statusText.toUpperCase()}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                              letterSpacing: 0.4,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Next billing date',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _nextBilling,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                FilledButton.icon(
                  onPressed: onManageBilling,
                  icon: openingPortal
                      ? SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.open_in_new),
                  label: const Text('Manage Billing'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard({required this.plan, required this.subscription});

  final Plan? plan;
  final UserSubscription? subscription;

  bool get _isUnlimited {
    if (plan?.isTranscriptionUnlimited == true) return true;
    final limit = plan?.transcriptionLimit;
    if (limit != null && limit < 0) return true;
    return false;
  }

  int _limit() => plan?.transcriptionLimit ?? 0;

  int _usageCount() {
    final counters = subscription?.usageCounters ?? {};
    const keys = [
      'transcriptions',
      'transcription',
      'transcription_count',
      'transcriptionCount',
    ];
    for (final key in keys) {
      if (counters.containsKey(key)) return counters[key] ?? 0;
    }
    return counters.values.isEmpty
        ? 0
        : counters.values.reduce((a, b) => a + b);
  }

  String get _limitText {
    if (_isUnlimited) return 'Unlimited';
    return '${_limit()} transcriptions';
  }

  String get _remainingText {
    if (_isUnlimited) return 'Unlimited';
    final remaining = max(0, _limit() - _usageCount());
    return '$remaining remaining';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shadowColor: AppColors.softShadow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.auto_graph,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Transcription usage',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Limit: $_limitText',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Remaining',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _remainingText,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      shadowColor: AppColors.softShadow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Error',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: AppColors.surface,
          shadowColor: AppColors.softShadow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
    );
  }
}

class _BillingPayload {
  const _BillingPayload({required this.plan, required this.subscription});

  final Plan? plan;
  final UserSubscription? subscription;
}