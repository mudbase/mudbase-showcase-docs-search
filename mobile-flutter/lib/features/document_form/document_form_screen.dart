import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/mudbase_exception.dart';
import '../auth/auth_controller.dart';
import '../document_detail/document_detail_screen.dart';
import '../library/library_controller.dart';

/// Create (`documentId == null`) and edit (`documentId` set) share one form -
/// mirrors the reference web app's shared `DocumentForm` component used by
/// both `/documents/new` and `/documents/[id]/edit`.
class DocumentFormScreen extends ConsumerStatefulWidget {
  const DocumentFormScreen({this.documentId, super.key});

  final String? documentId;

  @override
  ConsumerState<DocumentFormScreen> createState() => _DocumentFormScreenState();
}

class _DocumentFormScreenState extends ConsumerState<DocumentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _tagsController = TextEditingController();
  bool _submitting = false;
  bool _prefilled = false;
  String? _errorMessage;

  bool get _isEditing => widget.documentId != null;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final title = _titleController.text.trim();
      final content = _contentController.text.trim();
      final tags = _tagsController.text.trim();
      final library = ref.read(libraryControllerProvider.notifier);

      if (_isEditing) {
        await library.updateDocument(
          documentId: widget.documentId!,
          title: title,
          content: content,
          tags: tags,
        );
        ref.invalidate(documentDetailProvider(widget.documentId!));
        if (mounted) context.pop();
      } else {
        final created = await library.createDocument(
          title: title,
          content: content,
          tags: tags,
        );
        if (mounted) context.pushReplacement('/documents/${created.id}');
      }
    } on MudbaseException catch (error) {
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).valueOrNull;

    if (user == null || !user.isAuthenticated) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'Edit document' : 'New document'),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Sign in to add a document to the library.'),
          ),
        ),
      );
    }

    if (_isEditing) {
      final detailState = ref.watch(documentDetailProvider(widget.documentId!));
      final document = detailState.valueOrNull;
      if (document == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Edit document')),
          body: detailState.isLoading
              ? const Center(child: CircularProgressIndicator())
              : const Center(child: Text("This document isn't available.")),
        );
      }
      if (document.authorId != user.id) {
        return const Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('You can only edit documents you authored.'),
            ),
          ),
        );
      }
      if (!_prefilled) {
        _titleController.text = document.title;
        _contentController.text = document.content;
        _tagsController.text = document.tags ?? '';
        _prefilled = true;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit document' : 'New document'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null) ...[
                  _ErrorBanner(message: _errorMessage!),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                  maxLength: 200,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Title is required';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: _contentController,
                  decoration: const InputDecoration(labelText: 'Content'),
                  maxLines: 14,
                  maxLength: 50000,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Content is required';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: _tagsController,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    hintText: 'billing, invoices, refunds',
                    helperText:
                        'Comma-separated. Used for search and Ask AI ranking.',
                  ),
                  maxLength: 500,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isEditing ? 'Save changes' : 'Publish document'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: colorScheme.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
