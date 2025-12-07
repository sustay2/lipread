import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common/theme/app_colors.dart';
import '../../services/subscription_service.dart';

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  final SubscriptionService _service = SubscriptionService();
  Future<_SubscriptionPayload>? _loadFuture;
  String? _processingPriceId;
  bool _launchingPortal = false;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadData();
  }

  Future<_SubscriptionPayload> _loadData() async {
    final results = await Future.wait([
      _service.getPlans(),
      _service.getMySubscription(),
      _service.getFreePlan(),
      _service.getSubscriptionMetadata(),
    ]);

    return _SubscriptionPayload(
      plans: results[0] as List<Plan>,
      subscription: results[1] as UserSubscription?,
      freePlan: results[2] as Plan,
      metadata: results[3] as SubscriptionMetadata,
    );
  }

  Future<void> _refresh() async {
    final future = _loadData();
    setState(() => _loadFuture = future);
    await future;
  }

  Future<void> _startCheckout(Plan plan) async {
    if (plan.stripePriceId == null || plan.stripePriceId!.isEmpty) {
      _showSnack('Price unavailable for this plan');
      return;
    }
    setState(() => _processingPriceId = plan.id);
    try {
      final url = await _service.createCheckoutSession(plan.stripePriceId!);
      await _launchUrl(url);
    } catch (e) {
      _showSnack('Unable to start checkout: $e');
    } finally {
      if (mounted) setState(() => _processingPriceId = null);
    }
  }

  Future<void> _openBillingPortal() async {
    setState(() => _launchingPortal = true);
    try {
      final url = await _service.createBillingPortalSession();
      await _launchUrl(url);
    } catch (e) {
      _showSnack('Unable to open billing portal: $e');
    } finally {
      if (mounted) setState(() => _launchingPortal = false);
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _showSnack('Invalid URL');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      _showSnack('Could not open link');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Subscription'),
        centerTitle: true,
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_SubscriptionPayload>(
          future: _loadFuture,
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

            if (!snapshot.hasData) {
              return const _LoadingList();
            }

            final payload = snapshot.data!;
            final subscription = payload.subscription;
            final currentPlan =
                _resolveCurrentPlan(payload.plans, subscription, payload.freePlan);

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _SubscriptionOverviewCard(
                  subscription: subscription,
                  plan: currentPlan,
                  freePlan: payload.freePlan,
                  metadata: payload.metadata,
                  colorScheme: colorScheme,
                  onManageBilling: subscription != null ? _openBillingPortal : null,
                  launchingPortal: _launchingPortal,
                ),
                const SizedBox(height: 16),
                Text(
                  'Available plans',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                ...payload.plans.map(
                  (plan) => _PlanCard(
                    plan: plan,
                    isCurrent: currentPlan?.id == plan.id,
                    onSelect: () => _startCheckout(plan),
                    isProcessing: _processingPriceId == plan.id,
                    colorScheme: colorScheme,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Plan? _resolveCurrentPlan(List<Plan> plans, UserSubscription? subscription, Plan freePlan) {
    if (subscription == null) return freePlan;

    if (subscription.plan != null) return subscription.plan!;

    try {
      return plans.firstWhere((p) => p.id == subscription.planId);
    } catch (_) {
      return freePlan;
    }
  }
}

class _SubscriptionPayload {
  const _SubscriptionPayload({
    required this.plans,
    required this.subscription,
    required this.freePlan,
    required this.metadata,
  });

  final List<Plan> plans;
  final UserSubscription? subscription;
  final Plan freePlan;
  final SubscriptionMetadata metadata;
}

/* -------------------------------------------------------------------------- */
/*                            FIXED OVERVIEW CARD                             */
/* -------------------------------------------------------------------------- */

class _SubscriptionOverviewCard extends StatelessWidget {
  const _SubscriptionOverviewCard({
    required this.subscription,
    required this.plan,
    required this.freePlan,
    required this.colorScheme,
    required this.metadata,
    this.onManageBilling,
    this.launchingPortal = false,
  });

  final UserSubscription? subscription;
  final Plan? plan;
  final Plan freePlan;
  final ColorScheme colorScheme;
  final SubscriptionMetadata metadata;
  final VoidCallback? onManageBilling;
  final bool launchingPortal;

  bool get _isActive {
    final status = subscription?.status?.toLowerCase();
    if (status == null) return plan?.id == freePlan.id;
    return ['active', 'trialing', 'past_due'].contains(status);
  }

  /// FIXED: Correct unlimited calculation
  bool get _isUnlimited {
    if (plan?.isTranscriptionUnlimited == true) return true;
    if (metadata.isUnlimited == true) return true;

    return false;
  }

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
    return 0;
  }

  /// FIXED: Uses metadata AND plan correctly
  String _remainingText() {
    if (_isUnlimited) return 'Unlimited';

    final limit = plan?.transcriptionLimit ?? metadata.transcriptionLimit;
    if (limit == null) return 'Unlimited';

    final used = _usageCount();
    final remaining = max(0, limit - used);

    return '$remaining of $limit remaining';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.surface,
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
                    color: colorScheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.workspace_premium, color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan?.name ?? 'Free Plan',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isActive ? 'Status: ${subscription?.status ?? 'active'}' : 'Not subscribed',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.notes_outlined,
                  label: 'Transcriptions: ${_remainingText()}',
                ),
                _InfoChip(
                  icon: plan?.canAccessPremiumCourses == true
                      ? Icons.lock_open
                      : Icons.lock_outline,
                  label: plan?.canAccessPremiumCourses == true
                      ? 'Premium courses enabled'
                      : 'Premium courses locked',
                ),
              ],
            ),
            if (_isActive && onManageBilling != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: launchingPortal ? null : onManageBilling,
                icon: launchingPortal
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Icon(Icons.receipt_long_outlined),
                label: Text(launchingPortal ? 'Opening Billing Portal…' : 'Manage Billing'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.onSelect,
    required this.isProcessing,
    required this.colorScheme,
  });

  final Plan plan;
  final bool isCurrent;
  final VoidCallback onSelect;
  final bool isProcessing;
  final ColorScheme colorScheme;

  String _priceText() {
    final price = plan.priceMyr;
    if (price == null) return 'MYR —';
    final format = NumberFormat.currency(symbol: 'MYR ', decimalDigits: 2);
    return format.format(price);
  }

  String _transcriptionText() {
    if (plan.isTranscriptionUnlimited || plan.transcriptionLimit == null) {
      return 'Transcriptions: Unlimited';
    }
    return 'Transcriptions: ${plan.transcriptionLimit} / month';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _priceText(),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
                if (isCurrent)
                  Chip(
                    label: const Text('Current'),
                    backgroundColor: colorScheme.primary.withOpacity(0.12),
                    labelStyle: TextStyle(color: colorScheme.primary),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: plan.canAccessPremiumCourses
                      ? Icons.lock_open
                      : Icons.lock_outline,
                  label: plan.canAccessPremiumCourses
                      ? 'Premium courses allowed'
                      : 'Premium courses locked',
                ),
                _InfoChip(
                  icon: Icons.mic_none_outlined,
                  label: _transcriptionText(),
                ),
                if (plan.trialPeriodDays > 0)
                  _InfoChip(
                    icon: Icons.timer_outlined,
                    label: '${plan.trialPeriodDays}-day free trial',
                  ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                backgroundColor:
                    isCurrent ? colorScheme.primaryContainer : colorScheme.primary,
                foregroundColor:
                    isCurrent ? colorScheme.onPrimaryContainer : colorScheme.onPrimary,
              ),
              onPressed: isProcessing ? null : onSelect,
              icon: isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : const Icon(Icons.arrow_forward_rounded),
              label: Text(isCurrent ? 'Change Plan' : 'Upgrade / Downgrade'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onRetry});

  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Could not load subscription data.',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      itemCount: 3,
      itemBuilder: (context, index) {
        return ShimmerPlaceholder(
          height: 120,
          margin: EdgeInsets.only(bottom: index == 2 ? 0 : 12),
        );
      },
    );
  }
}

class ShimmerPlaceholder extends StatelessWidget {
  const ShimmerPlaceholder({super.key, this.height = 80, this.margin});

  final double height;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}