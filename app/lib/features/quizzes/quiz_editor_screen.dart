import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../core/providers/quiz_providers.dart';
import '../../core/quizzes/quiz_library.dart';
import '../../shared/describe_error.dart';
import '../../shared/theme/fz_theme.dart';
import '../../shared/widgets/fz.dart';
import '../../shared/widgets/fz_choice.dart';
import '../../shared/widgets/question_photo.dart';
import 'photo_resize.dart';

const maxQuizTitleLength = 80;
const maxQuizDescriptionLength = 280;
const maxPromptLength = 280;
const maxAnswers = 10;
const maxQuestions = 100;
const defaultTimeChoicesSeconds = [10, 15, 20, 30, 45, 60, 90, 120];
const difficulties = ['easy', 'medium', 'hard'];

/// Opens the editor for a new quiz, or for [existing]. Returns the saved quiz,
/// or null if the editor was closed without a successful save.
Future<LocalQuiz?> showQuizEditor(BuildContext context, {LocalQuiz? existing}) {
  return Navigator.of(context).push<LocalQuiz>(
    MaterialPageRoute(builder: (_) => QuizEditorScreen(existing: existing)),
  );
}

/// Create or edit one of this device's quizzes (QUIZ_FORMAT.md §2, §4).
/// Saving always stores it on the device; public quizzes are also published.
class QuizEditorScreen extends ConsumerStatefulWidget {
  const QuizEditorScreen({super.key, this.existing});

  final LocalQuiz? existing;

  @override
  ConsumerState<QuizEditorScreen> createState() => _QuizEditorScreenState();
}

/// Mutable editing state for one question.
class _DraftQuestion {
  _DraftQuestion({
    this.type = QuizQuestion.typeText,
    String prompt = '',
    List<String>? answers,
    this.difficulty = 'easy',
    this.image,
  }) : prompt = TextEditingController(text: prompt),
       answers = answers ?? [],
       answerInput = TextEditingController(),
       photoBytes = image?.data == null ? null : base64Decode(image!.data!);

  factory _DraftQuestion.from(QuizQuestion question) => _DraftQuestion(
    type: question.type,
    prompt: question.prompt,
    answers: [...question.acceptedAnswers],
    difficulty: difficulties.contains(question.difficulty)
        ? question.difficulty
        : 'easy',
    image: question.image,
  );

  final Key key = UniqueKey();
  String type;
  final TextEditingController prompt;
  final List<String> answers;
  final TextEditingController answerInput;
  String difficulty;

  /// Keeps the uploaded key while the photo is unchanged, so republishing
  /// doesn't upload it again.
  QuizImage? image;
  Uint8List? photoBytes;

  bool get isPhoto => type == QuizQuestion.typePhoto;

  void setPhoto(Uint8List bytes) {
    photoBytes = bytes;
    image = QuizImage(data: base64Encode(bytes), alt: image?.alt);
  }

  /// Moves the pending answer text into [answers].
  void commitAnswerInput() {
    final text = answerInput.text.trim();
    if (text.isNotEmpty &&
        !answers.contains(text) &&
        answers.length < maxAnswers) {
      answers.add(text);
    }
    answerInput.clear();
  }

  QuizQuestion toQuestion() => QuizQuestion(
    type: type,
    prompt: prompt.text.trim(),
    acceptedAnswers: [...answers],
    difficulty: difficulty,
    image: isPhoto ? image : null,
  );

  void dispose() {
    prompt.dispose();
    answerInput.dispose();
  }
}

class _QuizEditorScreenState extends ConsumerState<QuizEditorScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _category = 'general';
  String _visibility = 'private';
  int _timeLimitMs = 30000;
  bool _difficultyBonus = false;
  final List<_DraftQuestion> _questions = [];
  String? _localId;
  String? _publishedId;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) {
      _questions.add(_DraftQuestion());
      return;
    }
    final quiz = existing.quiz;
    _localId = existing.localId;
    _publishedId = existing.publishedId;
    _title.text = quiz.title;
    _description.text = quiz.description ?? '';
    _category = quizCategories.containsKey(quiz.category)
        ? quiz.category
        : 'other';
    _visibility = quiz.isPublic ? 'public' : 'private';
    _timeLimitMs = quiz.defaultSettings.timeLimitMs;
    _difficultyBonus = quiz.defaultSettings.difficultyMultiplier;
    _questions.addAll((quiz.questions ?? const []).map(_DraftQuestion.from));
    if (_questions.isEmpty) _questions.add(_DraftQuestion());
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    for (final question in _questions) {
      question.dispose();
    }
    super.dispose();
  }

  /// First problem that would make the server reject the quiz, if any.
  String? _validate() {
    final title = _title.text.trim();
    if (title.isEmpty) return 'Give your quiz a title.';
    if (title.characters.length > maxQuizTitleLength) {
      return 'Titles can be at most $maxQuizTitleLength characters.';
    }
    if (_questions.isEmpty) return 'Add at least one question.';
    for (final (index, question) in _questions.indexed) {
      final n = index + 1;
      final prompt = question.prompt.text.trim();
      if (prompt.isEmpty) return 'Question $n needs a question.';
      if (prompt.characters.length > maxPromptLength) {
        return 'Question $n is longer than $maxPromptLength characters.';
      }
      if (question.answers.isEmpty) {
        return 'Question $n needs at least one accepted answer.';
      }
      if (question.isPhoto && question.image?.data == null) {
        return 'Question $n needs a photo.';
      }
    }
    return null;
  }

  Future<void> _save() async {
    setState(() {
      for (final question in _questions) {
        question.commitAnswerInput();
      }
      _error = _validate();
    });
    if (_error != null) return;

    final description = _description.text.trim();
    final library = ref.read(quizLibraryProvider);
    final draft = LocalQuiz(
      localId: _localId ??= library.newLocalId(),
      publishedId: _publishedId,
      quiz: QuizDocument(
        title: _title.text.trim(),
        description: description.isEmpty ? null : description,
        category: _category,
        visibility: _visibility,
        defaultSettings: QuizDefaultSettings(
          timeLimitMs: _timeLimitMs,
          difficultyMultiplier: _difficultyBonus,
        ),
        questions: [for (final question in _questions) question.toQuestion()],
      ),
    );

    setState(() => _saving = true);
    try {
      final saved = await library.save(draft);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on PublishError catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _publishedId = error.saved.publishedId;
        final reason = describeError(error.cause);
        _error = _visibility == 'public'
            ? 'Saved on this device, but publishing failed: $reason'
            : "Saved on this device, but it's still public on the server: "
                  '$reason';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = describeError(error);
      });
    }
  }

  Future<void> _pickPhoto(_DraftQuestion question) async {
    try {
      final bytes = await ref.read(photoPickerProvider)();
      if (bytes == null || !mounted) return;
      setState(() {
        question.setPhoto(preparePhoto(bytes));
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = describeError(error));
    }
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _questions.length) return;
    setState(() {
      final question = _questions.removeAt(index);
      _questions.insert(target, question);
    });
  }

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    return Scaffold(
      body: FzPage(
        header: Row(
          children: [
            FzCircleButton(
              icon: Icons.close,
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 12),
            Expanded(child: FzEyebrow(_editing ? 'Edit quiz' : 'New quiz')),
          ],
        ),
        footer: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  _error!,
                  key: const Key('quizEditorError'),
                  style: fz.m(12, color: FzColors.ac2, height: 1.4),
                ),
              ),
            FzButton(
              key: const Key('saveQuizButton'),
              label: _saving
                  ? 'Saving…'
                  : _visibility == 'public'
                  ? 'Save & publish'
                  : 'Save quiz',
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
        child: _form(fz),
      ),
    );
  }

  Widget _form(FzTheme fz) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        TextField(
          key: const Key('quizTitleField'),
          controller: _title,
          maxLength: maxQuizTitleLength,
          style: fz.h(22),
          decoration: const InputDecoration(
            hintText: 'Quiz title',
            counterText: '',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const Key('quizDescriptionField'),
          controller: _description,
          minLines: 1,
          maxLines: 3,
          maxLength: maxQuizDescriptionLength,
          style: fz.m(13),
          decoration: const InputDecoration(
            hintText: 'Short description (optional)',
            counterText: '',
          ),
        ),
        const SizedBox(height: 20),
        const FzEyebrow('Category'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final entry in quizCategories.entries)
              FzChoice(
                key: ValueKey('category-${entry.key}'),
                label: entry.value,
                selected: _category == entry.key,
                onTap: () => setState(() => _category = entry.key),
              ),
          ],
        ),
        const SizedBox(height: 20),
        const FzEyebrow('Who can see it'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            FzChoice(
              key: const Key('visibilityPrivate'),
              label: 'Private · stays on this device',
              icon: Icons.lock_outline,
              selected: _visibility == 'private',
              onTap: () => setState(() => _visibility = 'private'),
            ),
            FzChoice(
              key: const Key('visibilityPublic'),
              label: 'Public · anyone can host it',
              icon: Icons.public,
              selected: _visibility == 'public',
              onTap: () => setState(() => _visibility = 'public'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _visibility == 'public'
              ? 'Published to the server so everyone can find it. You can '
                    'make it private again later.'
              : 'Only on this device. It is sent to the server just for the '
                    'games you host, then forgotten.',
          style: fz.m(11, color: FzColors.dim, height: 1.5),
        ),
        const SizedBox(height: 20),
        const FzEyebrow('Default seconds per question'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final seconds in defaultTimeChoicesSeconds)
              FzChoice(
                key: ValueKey('defaultTime-$seconds'),
                label: '${seconds}s',
                selected: _timeLimitMs == seconds * 1000,
                onTap: () => setState(() => _timeLimitMs = seconds * 1000),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Difficulty bonus', style: fz.h(15)),
                  const SizedBox(height: 4),
                  Text(
                    'On by default when this quiz is hosted',
                    style: fz.m(11, color: FzColors.dim),
                  ),
                ],
              ),
            ),
            Switch(
              key: const Key('defaultBonusSwitch'),
              value: _difficultyBonus,
              onChanged: (value) => setState(() => _difficultyBonus = value),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            Expanded(child: Text('Questions', style: fz.h(19))),
            Text(
              '${_questions.length} / $maxQuestions',
              style: fz.m(12, color: FzColors.dim),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final (index, question) in _questions.indexed)
          Padding(
            key: question.key,
            padding: const EdgeInsets.only(bottom: 12),
            child: _QuestionEditor(
              index: index,
              total: _questions.length,
              question: question,
              onChanged: () => setState(() {}),
              onMoveUp: () => _move(index, -1),
              onMoveDown: () => _move(index, 1),
              onDelete: () => setState(() {
                _questions.removeAt(index).dispose();
              }),
              onPickPhoto: () => _pickPhoto(question),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: FzPill(
            key: const Key('addQuestionButton'),
            label: 'Add question',
            icon: Icons.add,
            color: FzColors.ac,
            onPressed: _questions.length >= maxQuestions
                ? null
                : () => setState(() => _questions.add(_DraftQuestion())),
          ),
        ),
      ],
    );
  }
}

class _QuestionEditor extends StatelessWidget {
  const _QuestionEditor({
    required this.index,
    required this.total,
    required this.question,
    required this.onChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    required this.onPickPhoto,
  });

  final int index;
  final int total;
  final _DraftQuestion question;
  final VoidCallback onChanged;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;
  final VoidCallback onPickPhoto;

  void _addAnswer() {
    question.commitAnswerInput();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final fz = FzTheme.of(context);
    IconButton action(
      IconData icon,
      String tooltip,
      String key,
      VoidCallback? onPressed,
    ) => IconButton(
      key: Key('$key-$index'),
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      color: FzColors.dim,
      visualDensity: VisualDensity.compact,
    );

    return FzPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: FzEyebrow('Question ${index + 1}')),
              action(
                Icons.arrow_upward,
                'Move up',
                'moveUp',
                index == 0 ? null : onMoveUp,
              ),
              action(
                Icons.arrow_downward,
                'Move down',
                'moveDown',
                index == total - 1 ? null : onMoveDown,
              ),
              action(
                Icons.delete_outline,
                'Delete question',
                'deleteQuestion',
                total == 1 ? null : onDelete,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 7,
            children: [
              FzChoice(
                key: Key('questionType-$index-text'),
                label: 'Text',
                icon: Icons.short_text,
                selected: !question.isPhoto,
                onTap: () {
                  question.type = QuizQuestion.typeText;
                  onChanged();
                },
              ),
              FzChoice(
                key: Key('questionType-$index-photo'),
                label: 'Text + photo',
                icon: Icons.photo_outlined,
                selected: question.isPhoto,
                onTap: () {
                  question.type = QuizQuestion.typePhoto;
                  onChanged();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: Key('questionPrompt-$index'),
            controller: question.prompt,
            minLines: 1,
            maxLines: 4,
            maxLength: maxPromptLength,
            style: fz.h(17, weight: FontWeight.w700),
            decoration: const InputDecoration(
              hintText: 'Type the question',
              counterText: '',
            ),
          ),
          if (question.isPhoto) ...[
            const SizedBox(height: 12),
            if (question.photoBytes != null) ...[
              QuestionPhoto(
                key: Key('photoPreview-$index'),
                bytes: question.photoBytes,
                maxHeight: 180,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FzPill(
                  key: Key('pickPhoto-$index'),
                  label: 'Replace photo',
                  icon: Icons.photo_library_outlined,
                  onPressed: onPickPhoto,
                ),
              ),
            ] else
              OutlinedButton.icon(
                key: Key('pickPhoto-$index'),
                onPressed: onPickPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text('Add a photo', style: fz.m(12.5)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: FzColors.ink,
                  minimumSize: const Size.fromHeight(96),
                  side: const BorderSide(color: FzColors.line, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 14),
          const FzEyebrow('Accepted answers'),
          const SizedBox(height: 8),
          if (question.answers.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (answerIndex, answer) in question.answers.indexed)
                  InputChip(
                    key: Key('answer-$index-$answerIndex'),
                    label: Text(answer, style: fz.m(12.5, color: FzColors.ok)),
                    backgroundColor: FzColors.ok.withValues(alpha: .12),
                    side: const BorderSide(color: FzColors.ok),
                    deleteIconColor: FzColors.ok,
                    onDeleted: () {
                      question.answers.removeAt(answerIndex);
                      onChanged();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: Key('answerInput-$index'),
                  controller: question.answerInput,
                  style: fz.m(14),
                  decoration: const InputDecoration(
                    hintText: 'Add an accepted answer',
                  ),
                  onSubmitted: (_) => _addAnswer(),
                ),
              ),
              const SizedBox(width: 8),
              FzPill(
                key: Key('addAnswer-$index'),
                label: 'Add',
                onPressed: question.answers.length >= maxAnswers
                    ? null
                    : _addAnswer,
              ),
            ],
          ),
          const SizedBox(height: 14),
          const FzEyebrow('Difficulty'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            children: [
              for (final difficulty in difficulties)
                FzChoice(
                  key: Key('difficulty-$index-$difficulty'),
                  label: difficulty[0].toUpperCase() + difficulty.substring(1),
                  selected: question.difficulty == difficulty,
                  onTap: () {
                    question.difficulty = difficulty;
                    onChanged();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}
