import 'package:json_annotation/json_annotation.dart';

/// Room phase (PROTOCOL.md §6).
@JsonEnum(fieldRename: FieldRename.snake)
enum Phase { lobby, question, scoring, leaderboard, finished }

/// Role of the recipient of a snapshot / join reply.
@JsonEnum(fieldRename: FieldRename.snake)
enum Role { host, player }

/// Hosting mode of the room.
@JsonEnum(fieldRename: FieldRename.snake)
enum Mode { cloud, lan }

/// Question type. Phase 1 only renders [QuestionType.text].
@JsonEnum(fieldRename: FieldRename.snake)
enum QuestionType { text, textPhoto }
