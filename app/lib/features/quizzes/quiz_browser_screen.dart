import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/navigation.dart';

import '../../core/models/models.dart';
import '../../core/providers/quiz_providers.dart';
import '../../core/quizzes/quiz_library.dart';
import '../../shared/describe_error.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';
import '../../shared/widgets/fz_direction.dart';
import '../../shared/widgets/fz_choice.dart';
import '../../shared/widgets/stripe_header.dart';
import 'quiz_choice.dart';
// Not deferred: the same dialog is reached from inside a game, which every
// guest loads. Reporting is the one thing that has to be there wherever the
// content is.
import '../../shared/report_dialog.dart';
// The editor carries the photo pipeline and `package:image`; browsing does
// not need either until someone opens it.
import 'quiz_editor_screen.dart' deferred as editor;

export 'quiz_choice.dart';

/// Most quizzes one round may draw from (PROTOCOL.md §6.4).
const maxSelectedQuizzes = 10;

/// Opens the quiz browser; returns the quizzes picked to host in the order
/// they were picked, or null if the host backed out. Never empty.
///
/// [libraryOnly] is for a room on the public list, which plays published
/// quizzes only (PROTOCOL.md §3.5): the quizzes on this device are not offered.
Future<List<QuizChoice>?> showQuizBrowser(
  BuildContext context, {
  bool libraryOnly = false,
}) {
  return Navigator.of(context).push<List<QuizChoice>>(
    FzPageRoute(
      builder: (_) => QuizBrowserScreen(
        libraryOnly: libraryOnly,
        onEdit: (context, quiz) async {
          await editor.loadLibrary();
          if (!context.mounted) return null;
          return editor.showQuizEditor(context, existing: quiz);
        },
      ),
    ),
  );
}

/// Browse public quizzes from the server (QUIZ_FORMAT.md §5.1) or the ones
/// made on this device, and pick one or more to host: a round draws its
/// questions from every quiz picked, so several small quizzes make one bigger
/// pool (PROTOCOL.md §6.4). This device's quizzes can be
/// edited, published, made private and deleted here.
class QuizBrowserScreen extends ConsumerStatefulWidget {
  const QuizBrowserScreen({
    super.key,
    this.searchDebounce = const Duration(milliseconds: 300),
    this.onCreate,
    this.onEdit,
    this.libraryOnly = false,
  });

  final Duration searchDebounce;

  /// Public quizzes only, for a room on the public list (PROTOCOL.md §3.5).
  final bool libraryOnly;

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

  /// Quizzes reported from this screen. Not stored: it only keeps the button
  /// honest while the browser is open.
  final _reportedIds = <String>{};
  int? _nextOffset;
  bool _loading = false;
  String? _error;
  int _request = 0;
  int _localRequest = 0;

  /// What the host has picked so far, in the order they picked it — the first
  /// is the one whose defaults the lobby starts from (PROTOCOL.md §6.4). Keyed
  /// so a quiz can be unpicked and so re-rendered cards keep their state.
  final Map<String, QuizChoice> _selected = {};

  final Set<String> _savedPublicIds = {};
  final Map<String, int> _savedPublicVersions = {};
  final Set<String> _savingPublicIds = {};

  @override
  void initState() {
    super.initState();
    _loadPublic(reset: true);
    _loadLocal();
    _loadTags();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  bool _isSelected(String id) => _selected.containsKey(id);

  void _toggle(String id, QuizChoice choice) {
    setState(() {
      if (_selected.remove(id) != null) return;
      if (_selected.length >= maxSelectedQuizzes) {
        _error =
            'That is the most quizzes one game can draw from '
            '($maxSelectedQuizzes).';
        return;
      }
      _selected[id] = choice;
      _error = null;
    });
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
    final request = ++_localRequest;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final quizzes = await ref.read(quizLibraryProvider).list();
      if (!mounted || request != _localRequest) return;
      setState(() {
        _applyLocal(quizzes);
        _loading = false;
      });
      // The device's own copy is on screen either way; asking the server what
      // became of anything in the review queue can take its time.
      unawaited(_settleSubmissions(request));
    } catch (error) {
      if (!mounted || request != _localRequest) return;
      setState(() {
        _loading = false;
        _error = describeError(error);
      });
    }
  }

  void _applyLocal(List<LocalQuiz> quizzes) {
    _local = quizzes;
    _savedPublicIds
      ..clear()
      ..addAll(
        quizzes
            .where((quiz) => !quiz.isPublished)
            .map((quiz) => quiz.quiz.id)
            .whereType<String>(),
      );
    _savedPublicVersions
      ..clear()
      ..addEntries(
        quizzes
            .where((quiz) => !quiz.isPublished)
            .where((quiz) => quiz.quiz.id != null)
            .map((quiz) => MapEntry(quiz.quiz.id!, quiz.quiz.versionRank)),
      );
  }

  /// Catches the library up on what an admin decided about this device's
  /// submissions. A quiz only becomes public when somebody reads the queue,
  /// which will not be while the app is open — so opening the list is when the
  /// device finds out. Nothing to ask about is the common case, and costs no
  /// request at all.
  Future<void> _settleSubmissions(int request) async {
    if (!_local.any((quiz) => quiz.submission != null)) return;
    final quizzes = await ref.read(quizLibraryProvider).refreshSubmissions();
    if (!mounted || request != _localRequest) return;
    setState(() => _applyLocal(quizzes));
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

  /// Public, or waiting to be, both go back to private. Anything else asks for
  /// review: a rejected quiz is private again, so its button offers another go.
  Future<void> _togglePublished(LocalQuiz quiz) => _run(
    () => ref
        .read(quizLibraryProvider)
        .setPublic(quiz, !(quiz.isPublished || quiz.inReview)),
  );

  /// The line under a local card, when there is something to say about where
  /// the quiz stands with the server.
  static String? _localWarning(LocalQuiz quiz) {
    if (quiz.wasRejected) {
      final note = quiz.submission?.reviewNote?.trim();
      final what = quiz.isPublished
          ? 'Your changes were turned down, so the public copy is unchanged.'
          : 'Turned down, so it stayed private.';
      return note == null || note.isEmpty ? what : '$what $note';
    }
    if (quiz.inReview) {
      return quiz.isPublished
          ? 'Your changes are waiting to be read. The public version is '
                'unchanged until then.'
          : 'Waiting to be read. You can host it yourself in the meantime.';
    }
    if (quiz.inSync) return null;
    return quiz.wantsPublic
        ? 'Not sent for review yet. Tap Submit for review to try again.'
        : 'Still public on the server. Tap Make private to try again.';
  }

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

  /// Reports a public quiz, then remembers that this device did — so the
  /// button can say so. The server counts one report per device however many
  /// times it is tapped, so this is only about not leaving somebody wondering
  /// whether it went through.
  Future<void> _report(QuizDocument quiz) async {
    final messenger = ScaffoldMessenger.of(context);
    final sent = await showReportQuiz(context, quiz);
    if (!sent || !mounted) return;
    setState(() => _reportedIds.add(quiz.hostId));
    messenger.showSnackBar(
      const SnackBar(content: Text('Reported. Somebody will read it.')),
    );
  }

  Future<void> _saveOffline(QuizDocument quiz) async {
    final id = quiz.hostId;
    final savedVersion = _savedPublicVersions[id];
    if (_savingPublicIds.contains(id) ||
        (savedVersion != null && savedVersion >= quiz.versionRank)) {
      return;
    }
    setState(() => _savingPublicIds.add(id));
    try {
      await ref.read(quizLibraryProvider).saveCommunityQuiz(quiz);
      if (!mounted) return;
      setState(() {
        _savingPublicIds.remove(id);
        _savedPublicIds.add(id);
        _savedPublicVersions[id] = quiz.versionRank;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            savedVersion == null
                ? 'Saved for offline play.'
                : 'Updated the offline quiz.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingPublicIds.remove(id));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(error))));
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
        // Pinned, because the host builds a selection while scrolling and
        // should never have to hunt for the way out of the browser.
        footer: _selected.isEmpty
            ? null
            : FzButton(
                key: const Key('hostSelectedQuizzes'),
                label: _selected.length == 1
                    ? 'Host this quiz'
                    : 'Host these ${_selected.length} quizzes',
                onPressed: () =>
                    Navigator.of(context).pop(_selected.values.toList()),
              ),
        header: Row(
          children: [
            FzCircleButton(
              icon: Icons.arrow_back,
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const Spacer(),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            // One line: narrow phones shrink it rather than wrapping.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                "Pick tonight's quizzes",
                maxLines: 1,
                style: fz.t(31, height: 1.16, tracking: -.03),
              ),
            ),
            const SizedBox(height: 18),
            if (widget.libraryOnly)
              Text(
                'A public room plays quizzes from the library only.',
                key: const Key('libraryOnlyNote'),
                style: fz.m(12, color: FzColors.dim),
              )
            else
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
                    selected: _isSelected(quiz.hostId),
                    onTap: () => _toggle(quiz.hostId, PublicQuizChoice(quiz)),
                    actions: [
                      FzPill(
                        key: ValueKey('saveOffline-${quiz.hostId}'),
                        label:
                            _savedPublicIds.contains(quiz.hostId) &&
                                (_savedPublicVersions[quiz.hostId] ?? 0) <
                                    quiz.versionRank
                            ? 'Update offline'
                            : _savedPublicIds.contains(quiz.hostId)
                            ? 'Saved offline'
                            : 'Save offline',
                        icon:
                            _savedPublicIds.contains(quiz.hostId) &&
                                (_savedPublicVersions[quiz.hostId] ?? 0) <
                                    quiz.versionRank
                            ? Icons.sync
                            : _savedPublicIds.contains(quiz.hostId)
                            ? Icons.offline_pin
                            : Icons.download_outlined,
                        color:
                            _savedPublicIds.contains(quiz.hostId) &&
                                (_savedPublicVersions[quiz.hostId] ?? 0) <
                                    quiz.versionRank
                            ? FzColors.ac
                            : _savedPublicIds.contains(quiz.hostId)
                            ? FzColors.ok
                            : FzColors.ac,
                        onPressed:
                            (_savedPublicIds.contains(quiz.hostId) &&
                                    (_savedPublicVersions[quiz.hostId] ?? 0) >=
                                        quiz.versionRank) ||
                                _savingPublicIds.contains(quiz.hostId)
                            ? null
                            : () => _saveOffline(quiz),
                      ),
                      // Anything anyone can find is something anyone can
                      // object to (QUIZ_FORMAT.md §5.9).
                      FzPill(
                        key: ValueKey('reportQuiz-${quiz.hostId}'),
                        label: _reportedIds.contains(quiz.hostId)
                            ? 'Reported'
                            : 'Report',
                        icon: _reportedIds.contains(quiz.hostId)
                            ? Icons.flag
                            : Icons.outlined_flag,
                        color: FzColors.dim,
                        onPressed: () => _report(quiz),
                      ),
                    ],
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
      selected: _isSelected(id),
      onTap: () => _toggle(id, LocalQuizChoice(quiz)),
      tags: [
        FzTag(
          quiz.isPublished ? 'Public' : 'Private',
          key: ValueKey('quizVisibility-$id'),
          color: quiz.isPublished ? FzColors.ok : FzColors.ac,
        ),
        // Beside PUBLIC this reads as "public, and something of it is waiting"
        // — which is what an edit in the queue is. The line below says which.
        if (quiz.inReview)
          FzTag(
            'In review',
            key: ValueKey('quizReview-$id'),
            color: FzColors.ac,
          ),
      ],
      warning: _localWarning(quiz),
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
          label: quiz.isPublished || quiz.inReview
              ? 'Make private'
              : 'Submit for review',
          icon: quiz.isPublished || quiz.inReview
              ? Icons.lock_outline
              : Icons.public,
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
    this.selected = false,
    this.tags = const [],
    this.warning,
    this.warningKey,
    this.actions = const [],
  });

  final QuizDocument summary;
  final String cardId;
  final VoidCallback onTap;

  /// Picked for this round. The card shows it, because the browser stays open
  /// while the host builds up a selection.
  final bool selected;
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
      'Version ${quiz.version}',
      if (quiz.hasPhotos) 'Photos',
      if (quiz.defaultSettings.difficultyMultiplier) 'Difficulty scoring',
    ].join(' · ');

    return Material(
      color: FzColors.panel,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: selected
            ? const BorderSide(color: FzColors.ac, width: 2)
            : BorderSide.none,
      ),
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
                      if (selected) ...[
                        const Icon(
                          Icons.check_circle,
                          size: 18,
                          color: FzColors.ac,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: FzDirection(
                          text: quiz.title,
                          child: Text(quiz.title, style: fz.h(19)),
                        ),
                      ),
                      for (final tag in tags) ...[
                        const SizedBox(width: 6),
                        tag,
                      ],
                    ],
                  ),
                  if (quiz.description != null &&
                      quiz.description!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    FzDirection(
                      text: quiz.description!,
                      child: Text(
                        quiz.description!,
                        style: fz.m(11.5, color: FzColors.dim, height: 1.5),
                      ),
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
