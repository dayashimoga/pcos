import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/transfer_manager.dart';
import 'transfer_center_dialog.dart';

class TransferStatusIndicator extends StatefulWidget {
  final bool compact;
  const TransferStatusIndicator({super.key, this.compact = false});

  @override
  State<TransferStatusIndicator> createState() =>
      _TransferStatusIndicatorState();
}

class _TransferStatusIndicatorState extends State<TransferStatusIndicator>
    with SingleTickerProviderStateMixin {
  final _manager = TransferManager();
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _manager.addListener(_onChanged);
  }

  @override
  void dispose() {
    _animController.dispose();
    _manager.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _manager.activeCount;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textMuted = AppTheme.textMutedColor(context);

    if (widget.compact) {
      return IconButton(
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              Icons.swap_vert_rounded,
              size: 20,
              color: activeCount > 0 ? AppTheme.primary : textMuted,
            ),
            if (activeCount > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$activeCount',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
        tooltip: activeCount > 0
            ? 'Transfers ($activeCount active, ${_manager.formattedAggregatedSpeed})'
            : 'Transfer Center',
        onPressed: () => TransferCenterDialog.show(context),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => TransferCenterDialog.show(context),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: activeCount > 0
                ? AppTheme.primary.withOpacity(0.12)
                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: activeCount > 0
                  ? AppTheme.primary.withOpacity(0.3)
                  : AppTheme.borderColor(context),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _animController,
                builder: (_, child) {
                  return Transform.scale(
                    scale: activeCount > 0
                        ? 1.0 + (_animController.value * 0.15)
                        : 1.0,
                    child: child,
                  );
                },
                child: Icon(
                  Icons.swap_vert_rounded,
                  size: 16,
                  color: activeCount > 0 ? AppTheme.primary : textMuted,
                ),
              ),
              const SizedBox(width: 6),
              if (activeCount > 0) ...[
                Text(
                  '$activeCount active',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(${_manager.formattedAggregatedSpeed})',
                  style: TextStyle(
                    fontSize: 11,
                    color: textMuted,
                  ),
                ),
              ] else ...[
                Text(
                  'Transfers',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
