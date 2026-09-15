import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/quiz_providers.dart';
import '../../core/quizzes/quiz_library.dart';
import '../../shared/describe_error.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';
import '../../shared/widgets/fz_choice.dart';
import '../../shared/widgets/stripe_header.dart';
import 'quiz_editor_screen.dart';

/// What the host picked in the browser.
sealed class QuizChoice {
  const QuizChoice();
}

/// A quiz stored on the server (built-in or published), hosted by id.
final class PublicQuizChoice extends QuizChoice {
  const PublicQuizChoice(this.quiz);

  final QuizDocument quiz;
}

/// One of this device's quizzes.
final class LocalQuizChoice extends QuizChoice {
  const LocalQuizChoice(this.quiz);

  final LocalQuiz quiz;
}

/// Opens the quiz browser; returns the quiz picked to host, or null.
Future<QuizChoice?> showQuizBrowser(BuildContext context) {
  return Navigator.of(context).push<QuizChoice>(
    MaterialPageRoute(
      builder: (_) => QuizBrowserScreen(
        onCreate: (context) => showQuizEditor(context),
        onEdit: (context, quiz) => showQuizEditor(context, existing: quiz),
      ),
    ),
  );
}

/// Browse public quizzes from the server (QUIZ_FORMAT.md §5.1) or the ones
/// made on this device, and pick one to host. This device's quizzes can be
/// edited, published, made private and deleted here.
class QuizBrowserScreen extends ConsumerStatefulWidget {
  const QuizBrowserScreen({
    super.key,
    this.searchDebounce = const Duration(milliseconds: 300),
    this.onCreate,
    this.onEdit,
  });

  final Duration searchDebounce;

  /// Opens the quiz editor; returns the saved quiz (or null if cancelled).
  final Future<LocalQuiz?> Function(BuildContext context)? onCreate;
  final Future<LocalQuiz?> Function(BuildContext context, LocalQuiz quiz)?
  onEdit;

  @override
  ConsumerState<QuizBrowserScreen> createState() => _QuizBrowserScreenState();
}

class _QuizBrowserScreenState extends ConsumerState<QuizBrowserScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _mine = false;
  String? _tag;
  List<TagCount> _popularTags = const [];
  List<String> _suggested = defaultQuizTags;
  List<QuizDocument> _public = const [];
  List<LocalQuiz> _local = const [];
  int? _nextOffset;
  bool _loading = false;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _loadPublic(reset: true);
    _loadTags();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadPublic({required bool reset}) async {
    final request = ++_request;
    final offset = reset ? 0 : (_nextOffset ?? 0);
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _public = const [];
        _nextOffset = null;
      }
    });
    try {
      final page = await ref
          .read(quizApiProvider)
          .list(query: _search.text, tag: _tag, offset: offset);
      if (!mounted || request != _request) return;
      setState(() {
        _public = reset ? page.quizzes : [..._public, ...page.quizzes];
        _nextOffset = page.nextOffset;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = describeError(error);
      });
    }
  }

  Future<void> _loadLocal() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final quizzes = await ref.read(quizLibraryProvider).list();
      if (!mounted || request != _request) return;
      setState(() {
        _local = quizzes;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request) return;
      setState(() {
        _loading = false;
        _error = describeError(error);
      });
    }
  }

  /// Tag chips for the public tab; the suggested list stands in until the
  /// server says which tags are actually used.
  Future<void> _loadTags() async {
    try {
      final tags = await ref.read(quizApiProvider).tags();
      if (!mounted) return;
      setState(() {
        _popularTags = tags.popular;
        if (tags.suggested.isNotEmpty) _suggested = tags.suggested;
      });
    } catch (_) {
      // Not worth an error banner: the suggested tags are shown instead.
    }
  }

  List<String> get _tagChoices {
    if (_mine) {
      final tags = <String>{for (final quiz in _local) ...quiz.quiz.tags};
      return tags.toList()..sort();
    }
    if (_popularTags.isEmpty) return _suggested;
    return [for (final entry in _popularTags) entry.tag];
  }

  void _setTag(String? tag) {
    if (tag == _tag) return;
    setState(() => _tag = tag);
    _reload();
  }

  void _reload() => _mine ? _loadLocal() : _loadPublic(reset: true);

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    if (_mine) {
      // Local quizzes are filtered in place.
      setState(() {});
      return;
    }
    _debounce = Timer(widget.searchDebounce, () => _loadPublic(reset: true));
  }

  void _setMine(bool mine) {
    if (mine == _mine) return;
    _debounce?.cancel();
    // The two tabs offer different tags, so a filter doesn't carry over —
    // otherwise it silently hides everything in the tab you land on.
    setState(() {
      _mine = mine;
      _tag = null;
    });
    _reload();
  }

  List<LocalQuiz> get _filteredLocal {
    final term = _search.text.trim().toLowerCase();
    bool matches(LocalQuiz quiz) =>
        term.isEmpty ||
        quiz.quiz.title.toLowerCase().contains(term) ||
        quiz.quiz.tags.any((tag) => tag.contains(term));

    return [
      for (final quiz in _local)
        if ((_tag == null || quiz.quiz.tags.contains(_tag)) && matches(quiz))
          quiz,
    ];
  }

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on PublishError catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            "Couldn't update the server: ${describeError(error.cause)}",
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
    if (mounted) await _loadLocal();
  }

  Future<void> _togglePublished(LocalQuiz quiz) => _run(
    () => ref.read(quizLibraryProvider).setPublic(quiz, !quiz.isPublished),
  );

  Future<void> _delete(LocalQuiz quiz) async {
    final title = quiz.quiz.title;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this quiz?'),
        content: Text(
          quiz.isPublished
              ? '"$title" will be unpublished and deleted from this device.'
              : '"$title" will be deleted from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            key: const Key('confirmDeleteQuiz'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => ref.read(quizLibraryProvider).delete(quiz));
  }

  Future<void> _create() async {
    final saved = await widget.onCreate?.call(context);
    if (!mounted) return;
    if (saved != null && !_mine) {
      _setMine(true);
    } else if (_mine) {
      await _loadLocal();
    }
  }

  Future<void> _edit(LocalQuiz quiz) async {
    await widget.onEdit?.call(context, quiz);
    if (mounted) await _loadLocal();
  }

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final local = _filteredLocal;
    final empty = _mine ? local.isEmpty : _public.isEmpty;

    return Scaffold(
      body: FzPage(
        header: Row(
          children: [
            FzCircleButton(
              icon: Icons.arrow_back,
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const Spacer(),
            if (widget.onCreate != null)
              FzPill(
                key: const Key('createQuizButton'),
                label: 'New quiz',
                icon: Icons.add,
                color: FzColors.ac,
                onPressed: _create,
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Text(
              "Pick tonight's\nquiz",
              style: fz.h(
                32,
                weight: FontWeight.w900,
                height: 1.05,
                tracking: -.03,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                FzChoice(
                  key: const Key('quizScopePublic'),
                  label: 'Public',
                  selected: !_mine,
                  onTap: () => _setMine(false),
                ),
                const SizedBox(width: 8),
                FzChoice(
                  key: const Key('quizScopeMine'),
                  label: 'My quizzes',
                  selected: _mine,
                  onTap: () => _setMine(true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('quizSearchField'),
              controller: _search,
              onChanged: _onSearchChanged,
              style: fz.h(16, weight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: 'Search by title or tag',
                prefixIcon: Icon(Icons.search, color: FzColors.dim),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  FzChoice(
                    key: const Key('tagFilterAll'),
                    label: 'All tags',
                    selected: _tag == null,
                    onTap: () => _setTag(null),
                  ),
                  for (final tag in _tagChoices)
                    Padding(
                      padding: const EdgeInsets.only(left: 7),
                      child: FzChoice(
                        key: ValueKey('tagFilter-$tag'),
                        label: tag,
                        selected: _tag == tag,
                        onTap: () => _setTag(_tag == tag ? null : tag),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_error != null)
              FzPanel(
                key: const Key('quizBrowserError'),
                borderColor: FzColors.ac2,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error!,
                        style: fz.m(12, color: FzColors.ac2),
                      ),
                    ),
                    FzPill(label: 'Retry', onPressed: _reload),
                  ],
                ),
              ),
            if (!_loading && _error == null && empty)
              _EmptyState(
                mine: _mine,
                filtered: _search.text.trim().isNotEmpty || _tag != null,
                onCreate: widget.onCreate == null ? null : _create,
              ),
            if (!_mine)
              for (final quiz in _public)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _QuizCard(
                    summary: quiz,
                    cardId: quiz.hostId,
                    onTap: () =>
                        Navigator.of(context).pop(PublicQuizChoice(quiz)),
                    tags: [
                      if (quiz.isBuiltin)
                        const FzTag('Built-in', color: FzColors.ok),
                      if (quiz.isOwner)
                        const FzTag('Yours', color: FzColors.ac),
                    ],
                  ),
                )
            else
              for (final quiz in local)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _localCard(quiz),
                ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (!_mine && !_loading && _nextOffset != null)
              Center(
                child: FzPill(
                  key: const Key('loadMoreQuizzes'),
                  label: 'Load more',
                  onPressed: () => _loadPublic(reset: false),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _localCard(LocalQuiz quiz) {
    final id = quiz.localId;
    return _QuizCard(
      summary: quiz.summary,
      cardId: id,
      onTap: () => Navigator.of(context).pop(LocalQuizChoice(quiz)),
      tags: [
        FzTag(
          quiz.isPublished ? 'Public' : 'Private',
          key: ValueKey('quizVisibility-$id'),
          color: quiz.isPublished ? FzColors.ok : FzColors.ac,
        ),
      ],
      warning: quiz.inSync
          ? null
          : quiz.wantsPublic
          ? 'Not published yet. Tap Publish to try again.'
          : 'Still public on the server. Tap Make private to try again.',
      warningKey: ValueKey('quizSyncWarning-$id'),
      actions: [
        if (widget.onEdit != null)
          FzPill(
            key: ValueKey('editQuiz-$id'),
            label: 'Edit',
            icon: Icons.edit_outlined,
            onPressed: () => _edit(quiz),
          ),
        FzPill(
          key: ValueKey('togglePublished-$id'),
          label: quiz.isPublished ? 'Make private' : 'Publish',
          icon: quiz.isPublished ? Icons.lock_outline : Icons.public,
          onPressed: () => _togglePublished(quiz),
        ),
        FzPill(
          key: ValueKey('deleteQuiz-$id'),
          label: 'Delete',
          icon: Icons.delete_outline,
          color: FzColors.ac2,
          onPressed: () => _delete(quiz),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.mine,
    required this.filtered,
    required this.onCreate,
  });

  final bool mine;

  /// A search term or tag filter is narrowing the list.
  final bool filtered;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final offerCreate = mine && !filtered && onCreate != null;
    return FzPanel(
      key: const Key('quizBrowserEmpty'),
      color: Colors.transparent,
      borderColor: FzColors.line,
      child: Column(
        children: [
          Text(
            mine && !filtered
                ? "You haven't made a quiz yet. Private quizzes stay on this "
                      'device; publish one to share it with everyone.'
                : 'Nothing matches that search or tag.',
            textAlign: TextAlign.center,
            style: fz.m(12, color: FzColors.dim, height: 1.5),
          ),
          if (offerCreate) ...[
            const SizedBox(height: 12),
            FzPill(
              label: 'Create a quiz',
              icon: Icons.add,
              color: FzColors.ac,
              onPressed: onCreate,
            ),
          ],
        ],
      ),
    );
  }
}

class _QuizCard extends StatelessWidget {
  const _QuizCard({
    required this.summary,
    required this.cardId,
    required this.onTap,
    this.tags = const [],
    this.warning,
    this.warningKey,
    this.actions = const [],
  });

  final QuizDocument summary;
  final String cardId;
  final VoidCallback onTap;
  final List<Widget> tags;
  final String? warning;
  final Key? warningKey;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    final quiz = summary;
    final count = quiz.questionCount;
    final meta = [
      ...quiz.tags.take(3),
      if (quiz.hasPhotos) 'Photos',
      if (quiz.defaultSettings.difficultyMultiplier) 'Difficulty bonus',
    ].join(' · ');

    return Material(
      color: FzColors.panel,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        key: ValueKey('quizCard-$cardId'),
        onTap: count > 0 ? onTap : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StripeHeader(
              hue: tagHue(quiz.tags.isEmpty ? null : quiz.tags.first),
              tag: '$count ${count == 1 ? 'question' : 'questions'}',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(quiz.title, style: fz.h(19))),
                      for (final tag in tags) ...[
                        const SizedBox(width: 6),
                        tag,
                      ],
                    ],
                  ),
                  if (quiz.description != null &&
                      quiz.description!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      quiz.description!,
                      style: fz.m(11.5, color: FzColors.dim, height: 1.5),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    meta.toUpperCase(),
                    style: fz.m(9.5, color: FzColors.faint, tracking: .12),
                  ),
                  if (warning != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      warning!,
                      key: warningKey,
                      style: fz.m(11, color: FzColors.ac2, height: 1.4),
                    ),
                  ],
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: actions),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
