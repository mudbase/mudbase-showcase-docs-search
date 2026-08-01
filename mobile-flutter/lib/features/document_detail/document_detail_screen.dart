import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../data/repository_providers.dart';
import '../../models/document_record.dart';
import '../../widgets/async_value_view.dart';
import '../auth/auth_controller.dart';
import '../library/library_controller.dart';

/// Looks the document up in the already-loaded library list first (the fast
/// path - the user almost always reached this screen by tapping a card from
/// a list that's already in memory); falls back to a direct
/// `GET .../data/:id` for the rare case it isn't there (e.g. Ask AI
/// citation for a document outside the loaded page size).
final documentDetailProvider = FutureProvider.family<DocumentRecord?, String>((
  ref,
  documentId,
) async {
  final library = await ref.watch(libraryControllerProvider.future);
  for (final document in library) {
    if (document.id == documentId) return document;
  }
  final authController = ref.read(authControllerProvider.notifier);
  final repo = ref.read(documentRepositoryProvider);
  return authController.callAuthorized(
    (token) => repo.getById(documentId, token: token),
  );
});

class DocumentDetailScreen extends ConsumerStatefulWidget {
  const DocumentDetailScreen({required this.documentId, super.key});

  final String documentId;

  @override
  ConsumerState<DocumentDetailScreen> createState() =>
      _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends ConsumerState<DocumentDetailScreen> {
  bool _deleting = false;

  Future<void> _confirmDelete(DocumentRecord document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this document?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await ref
          .read(libraryControllerProvider.notifier)
          .deleteDocument(document.id);
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailState = ref.watch(documentDetailProvider(widget.documentId));
    final user = ref.watch(authControllerProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Document')),
      body: SafeArea(
        child: AsyncValueView(
          value: detailState,
          onRetry: () =>
              ref.invalidate(documentDetailProvider(widget.documentId)),
          data: (context, document) {
            if (document == null) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text("This document isn't available."),
                ),
              );
            }

            final tags = parseTags(document.tags);
            final isOwner = user != null && user.id == document.authorId;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          document.title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (isOwner) ...[
                        IconButton(
                          tooltip: 'Edit',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () =>
                              context.push('/documents/${document.id}/edit'),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: _deleting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  Icons.delete_outline,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                          onPressed: _deleting
                              ? null
                              : () => _confirmDelete(document),
                        ),
                      ],
                    ],
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: tags
                          .map((tag) => Chip(label: Text(tag)))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    '${document.authorName} · ${formatDateTime(document.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    document.content,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
