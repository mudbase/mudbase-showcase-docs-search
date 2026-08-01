import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Renders the three states every `AsyncValue`-backed screen in this app
/// needs to handle explicitly (loading / error+retry / data) instead of
/// re-writing the same `when(...)` boilerplate on every screen. Ported
/// verbatim from the sibling kanban/social/ecommerce Flutter apps'
/// `widgets/async_value_view.dart`.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    required this.value,
    required this.data,
    this.onRetry,
    this.loadingBuilder,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) data;
  final VoidCallback? onRetry;
  final WidgetBuilder? loadingBuilder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: (value) => data(context, value),
      loading: () =>
          loadingBuilder?.call(context) ??
          const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 40,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                _messageFor(error),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _messageFor(Object error) => error.toString();
}
