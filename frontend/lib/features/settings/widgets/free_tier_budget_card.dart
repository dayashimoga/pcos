import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';

class FreeTierBudgetCard extends StatefulWidget {
  final ApiClient apiClient;

  const FreeTierBudgetCard({super.key, required this.apiClient});

  @override
  State<FreeTierBudgetCard> createState() => _FreeTierBudgetCardState();
}

class _FreeTierBudgetCardState extends State<FreeTierBudgetCard> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _budgetData;
  bool _hardBudgetEnabled = true;

  @override
  void initState() {
    super.initState();
    _fetchUsage();
  }

  Future<void> _fetchUsage() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await widget.apiClient.getFreeTierUsage();
      if (mounted) {
        setState(() {
          _budgetData = data;
          _hardBudgetEnabled = data['hard_budget_enabled'] ?? true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              'Could not load cloud budget: ${e.toString().replaceAll("Exception: ", "")}';
          _isLoading = false;
        });
      }
    }
  }

  Color _getPctColor(int pct, ColorScheme colorScheme) {
    if (pct >= 90) return Colors.red.shade600;
    if (pct >= 75) return Colors.orange.shade700;
    if (pct >= 50) return Colors.amber.shade700;
    return Colors.green.shade600;
  }

  Widget _buildMetricRow({
    required BuildContext context,
    required String label,
    required int pct,
    required String detail,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = _getPctColor(pct, colorScheme);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              Row(
                children: [
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$pct%',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pct / 100.0).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.speed_outlined, color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PCOS Cloud Usage',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Cloudflare Free-Tier Guard',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh Usage',
                  onPressed: _isLoading ? null : _fetchUsage,
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colorScheme.error),
                ),
              )
            else if (_budgetData != null) ...[
              // Metrics
              _buildMetricRow(
                context: context,
                label: 'Workers Requests',
                pct: (_budgetData!['worker_requests']?['pct'] as num?)
                        ?.toInt() ??
                    0,
                detail:
                    '${_budgetData!['worker_requests']?['used'] ?? 0} / ${_budgetData!['worker_requests']?['limit'] ?? 100000}',
              ),
              _buildMetricRow(
                context: context,
                label: 'D1 Reads',
                pct: (_budgetData!['d1_reads']?['pct'] as num?)?.toInt() ?? 0,
                detail:
                    '${_budgetData!['d1_reads']?['used'] ?? 0} / ${_budgetData!['d1_reads']?['limit'] ?? 5000000}',
              ),
              _buildMetricRow(
                context: context,
                label: 'D1 Writes',
                pct: (_budgetData!['d1_writes']?['pct'] as num?)?.toInt() ?? 0,
                detail:
                    '${_budgetData!['d1_writes']?['used'] ?? 0} / ${_budgetData!['d1_writes']?['limit'] ?? 100000}',
              ),
              _buildMetricRow(
                context: context,
                label: 'Durable Objects',
                pct:
                    (_budgetData!['do_requests']?['pct'] as num?)?.toInt() ?? 0,
                detail:
                    '${_budgetData!['do_requests']?['used'] ?? 0} / ${_budgetData!['do_requests']?['limit'] ?? 100000}',
              ),
              _buildMetricRow(
                context: context,
                label: 'R2 Cloud Cache',
                pct: (_budgetData!['r2_storage_gb']?['pct'] as num?)?.toInt() ??
                    0,
                detail:
                    '${_budgetData!['r2_storage_gb']?['used'] ?? 0.0} GB / ${_budgetData!['r2_storage_gb']?['limit'] ?? 10} GB',
              ),

              const Divider(height: 24),

              // Estimated Cost & Budget Mode
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Estimated Cost',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '\$${(_budgetData!['estimated_cost'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _hardBudgetEnabled
                          ? Colors.green.shade50
                          : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _hardBudgetEnabled
                            ? Colors.green.shade300
                            : Colors.amber.shade300,
                      ),
                    ),
                    child: Text(
                      _hardBudgetEnabled
                          ? 'Hard Budget = \$0 (Active)'
                          : 'Flexible',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _hardBudgetEnabled
                            ? Colors.green.shade800
                            : Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Guaranteed free-first architecture: PCOS keeps bulk files and compute on your local storage nodes and never automatically opts into paid cloud services.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
