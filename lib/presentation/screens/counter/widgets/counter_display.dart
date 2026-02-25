import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Виджет отображения счётчика
class CounterDisplay extends StatelessWidget {
  final int totalCount;
  final int sessionCount;

  const CounterDisplay({
    super.key,
    required this.totalCount,
    required this.sessionCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Общий счётчик
        Expanded(
          child: _CounterCard(
            label: 'Total',
            value: totalCount.toString(),
          ),
        ),
        const SizedBox(width: 12),
        // Счётчик сессии
        Expanded(
          child: _CounterCard(
            label: 'Session',
            value: sessionCount.toString(),
          ),
        ),
      ],
    );
  }
}

class _CounterCard extends StatelessWidget {
  final String label;
  final String value;

  const _CounterCard({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white70,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.displayLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 40,
            ),
          ),
        ],
      ),
    );
  }
}
