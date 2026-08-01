import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/retrieval.dart';
import '../../widgets/async_value_view.dart';
import '../../widgets/empty_state.dart';
import '../auth/auth_controller.dart';
import 'library_controller.dart';
import 'widgets/document_card.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchController = TextEditingController();
  String _searchTerm = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryControllerProvider);
    final authState = ref.watch(authControllerProvider);
    final isAuthenticated = authState.valueOrNull?.isAuthenticated ?? false;

    final user = authState.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Document library'),
        actions: [
          if (isAuthenticated) ...[
            IconButton(
              tooltip: 'New document',
              icon: const Icon(Icons.add),
              onPressed: () => context.push('/documents/new'),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.account_circle_outlined),
              onSelected: (value) {
                if (value == 'sign_out') {
                  unawaited(ref.read(authControllerProvider.notifier).logout());
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Text(
                    'Signed in as ${user?.fullName ?? ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem<String>(
                  value: 'sign_out',
                  child: Text('Sign out'),
                ),
              ],
            ),
          ] else
            TextButton(
              onPressed: () => context.push('/login'),
              child: const Text('Sign in'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search title, content, or tags',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchTerm.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchTerm = '');
                          },
                        ),
                ),
                onChanged: (value) => setState(() => _searchTerm = value),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () =>
                    ref.read(libraryControllerProvider.notifier).refresh(),
                child: AsyncValueView(
                  value: libraryState,
                  onRetry: () =>
                      ref.read(libraryControllerProvider.notifier).refresh(),
                  data: (context, documents) {
                    final filtered = documents
                        .where(
                          (document) =>
                              matchesSearchTerm(document, _searchTerm),
                        )
                        .toList(growable: false);

                    if (filtered.isEmpty) {
                      return ListView(
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.6,
                            child: EmptyState(
                              icon: documents.isEmpty
                                  ? Icons.menu_book_outlined
                                  : Icons.search_off,
                              message: documents.isEmpty
                                  ? 'No documents in the library yet.'
                                  : 'Nothing matched "$_searchTerm".',
                            ),
                          ),
                        ],
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final document = filtered[index];
                        return DocumentCard(
                          document: document,
                          onTap: () =>
                              context.push('/documents/${document.id}'),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
