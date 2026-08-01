import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import 'ask_controller.dart';
import 'widgets/recent_searches.dart';

/// Ask AI: fully-live, on-device keyword retrieval + ranking (real data,
/// real scoring, no mock) - and an honestly-labeled gap where a natural-
/// language answer would be. See `plan/build-plan.md` "Ask AI architecture"
/// for the full reasoning: neither the real deployed Mudbase Function nor
/// an LLM provider can be invoked from this app without embedding a secret
/// in the mobile binary, which this project's own security rules (and this
/// app's task brief) forbid outright. Rather than fake a synthesized
/// answer, this screen shows exactly what it can prove: the ranked source
/// documents an answer would be grounded in.
class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key});

  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends ConsumerState<AskScreen> {
  final _questionController = TextEditingController();

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final askState = ref.watch(askControllerProvider);
    final isAsking = askState.isLoading;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Ask AI')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Ask a question in plain language. This app finds the most '
              'relevant documents in the library and ranks them the same '
              'way the reference platform Function does — see below for '
              'what happens (and doesn\'t) after that.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _questionController,
                      minLines: 2,
                      maxLines: 4,
                      enabled: !isAsking,
                      decoration: const InputDecoration(
                        hintText: 'e.g. How do I reset my password?',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isAsking
                                ? null
                                : () => ref
                                      .read(askControllerProvider.notifier)
                                      .ask(_questionController.text),
                            child: isAsking
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Ask AI'),
                          ),
                        ),
                        if (askState.valueOrNull != null && !isAsking) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              _questionController.clear();
                              ref.read(askControllerProvider.notifier).clear();
                            },
                            child: const Text('Clear'),
                          ),
                        ],
                      ],
                    ),
                    if (askState.hasError) ...[
                      const SizedBox(height: 8),
                      Text(
                        askState.error.toString(),
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (askState.valueOrNull != null)
              _AskResultView(result: askState.valueOrNull!),
            const SizedBox(height: 24),
            const RecentSearches(),
          ],
        ),
      ),
    );
  }
}

class _AskResultView extends StatelessWidget {
  const _AskResultView({required this.result});

  final AskResult result;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (result.noMatch) {
      return Text(
        "No documents in the library matched that question closely enough. "
        "Try rephrasing, or add a document that covers it.",
        style: TextStyle(color: colorScheme.onSurfaceVariant),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.travel_explore,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Ranked sources (live, on-device)',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Scored by keyword overlap across title, tags, and content — '
                  'the same weighting the deployed Mudbase Function uses.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                for (final entry in result.ranked)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: InkWell(
                      onTap: () =>
                          context.push('/documents/${entry.document.id}'),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.document.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    snippet(
                                      entry.document.content,
                                      maxLength: 120,
                                    ),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Chip(
                              label: Text('score ${entry.score}'),
                              visualDensity: VisualDensity.compact,
                              labelStyle: Theme.of(
                                context,
                              ).textTheme.labelSmall,
                            ),
                            const Icon(Icons.chevron_right, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Answer generation: not available in this app',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Turning these ranked sources into a written answer needs an '
                  'LLM completion call. That call can\'t happen on-device — an '
                  'LLM API key must never be embedded in a mobile binary — and '
                  'it can\'t happen inside a Mudbase Function either, since '
                  'Function code runs in a sandbox with no network access. The '
                  'reference web app solves this with one small server-side '
                  'route holding both secrets; this mobile app ships no server '
                  'of its own, so that step is an honest, documented gap rather '
                  'than a faked response. See plan/build-plan.md "Ask AI '
                  'architecture" for the full reasoning.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
