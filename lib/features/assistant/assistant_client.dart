import 'package:dio/dio.dart';
import 'package:nocknock/features/assistant/assistant_actions.dart';
import 'package:nocknock/features/notes/domain/note.dart';
import 'package:nocknock/features/finance/list_configuration.dart';
import 'package:nocknock/core/config/app_config.dart';

class AssistantFailure implements Exception {
  const AssistantFailure(this.message);
  final String message;
}

class AssistantDraft {
  const AssistantDraft(this.title, this.content, this.checklist);
  final String title;
  final String content;
  final List<String> checklist;
}

enum AssistantMode { chat, draft, list }

class AssistantListDraft {
  const AssistantListDraft(this.name, this.configuration);
  final String name;
  final ListConfiguration configuration;
}

class AssistantReply {
  const AssistantReply(
    this.answer,
    this.draft, [
    this.listDraft,
    this.edit,
    this.expenses = const [],
    this.receipt,
  ]);
  final AssistantEdit? edit;
  final List<AssistantExpense> expenses;
  final NoteAttachment? receipt;
  final AssistantListDraft? listDraft;
  final String answer;
  final AssistantDraft? draft;

  String get plainText => [
    answer,
    if (edit case final change?) ...change.descriptions,
    for (final expense in expenses) expense.summary,
    if (listDraft case final proposal?)
      "${proposal.name} · ${proposal.configuration.label} · ${proposal.configuration.currency}",
    if (draft case final note?) ...[
      note.title,
      note.content,
      ...note.checklist.map((i) => '• $i'),
    ],
  ].where((s) => s.isNotEmpty).join('\n');
}

class AssistantClient {
  AssistantClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: AppConfig.apiBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 40),
              sendTimeout: const Duration(seconds: 10),
            ),
          );
  final Dio _dio;
  void close() => _dio.close(force: true);

  Future<AssistantReply> ask({
    required String token,
    required String question,
    required AssistantMode mode,
    String? screen,
    String? excerpt,
    String? previousExchange,
    NoteAttachment? receipt,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/assistant',
        data: {
          'question': question,
          'mode': mode.name,
          if (mode == AssistantMode.chat) 'actionVersion': 1,
          if (receipt != null)
            'receipt': {
              'mimeType': receipt.mimeType,
              'data': receipt.dataBase64,
            },
          'screen': ?screen,
          'excerpt': ?excerpt,
          'previousExchange': ?previousExchange,
          'localDate': DateTime.now().toIso8601String().split('T').first,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          receiveTimeout: receipt == null ? null : const Duration(seconds: 65),
          sendTimeout: receipt == null ? null : const Duration(seconds: 30),
        ),
      );
      final data = response.data;
      if (data case {'answer': final String answer}
          when answer.trim().isNotEmpty) {
        if (mode == AssistantMode.chat && data['noteEdit'] != null) {
          final edit = AssistantEdit.parse(data['noteEdit']);
          if (edit == null) {
            throw const AssistantFailure(
              'Los cambios de la nota llegaron incompletos.',
            );
          }
          return AssistantReply(answer, null, null, edit);
        }
        if (mode == AssistantMode.chat && data['expenses'] != null) {
          final rows = data['expenses'];
          if (rows is! List || rows.isEmpty || rows.length > 8) {
            throw const AssistantFailure(
              'La propuesta de gastos no es válida.',
            );
          }
          final expenses = rows
              .map(AssistantExpense.parse)
              .whereType<AssistantExpense>()
              .toList();
          if (expenses.length != rows.length) {
            throw const AssistantFailure(
              'Revisa los datos del gasto y vuelve a intentarlo.',
            );
          }
          return AssistantReply(answer, null, null, null, expenses, receipt);
        }
        if (mode == AssistantMode.chat &&
            data['draft'] == null &&
            data['listDraft'] == null) {
          return AssistantReply(answer, null);
        }
        if (mode == AssistantMode.list ||
            (mode == AssistantMode.chat && data['listDraft'] != null)) {
          if (data['listDraft']
              case {
                'name': final String name,
                'listType': final String type,
                'currency': final String currency,
                'customTypeName': final String custom,
              }
              when name.trim().isNotEmpty &&
                  NoteListType.values.any((t) => t.name == type) &&
                  ListConfiguration.currencies.contains(currency) &&
                  (type != 'custom' || custom.trim().isNotEmpty)) {
            return AssistantReply(
              answer,
              null,
              AssistantListDraft(
                name,
                ListConfiguration(
                  type: NoteListType.values.byName(type),
                  currency: currency,
                  customTypeName: type == 'custom' ? custom : null,
                ),
              ),
            );
          }
          throw const AssistantFailure(
            'La propuesta de lista llegó incompleta. Vuelve a intentarlo.',
          );
        }
        if (data['draft']
            case {
              'title': final String title,
              'content': final String content,
              'checklist': final List items,
            }
            when title.trim().isNotEmpty && items.every((i) => i is String)) {
          return AssistantReply(
            answer,
            AssistantDraft(title, content, items.cast<String>()),
          );
        }
      }
      throw const AssistantFailure(
        'La respuesta llegó incompleta. Vuelve a intentarlo.',
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      final data = error.response?.data;
      final message = switch (status) {
        401 || 403 => 'Tu sesión venció. Vuelve a iniciar sesión.',
        404 => 'Esta versión del servidor aún no incluye el asistente.',
        422 || 429 || 502 || 503 || 504
            when data is Map && data['message'] is String =>
          data['message'] as String,
        null => 'No pudimos conectar con el asistente. Revisa tu conexión e inténtalo otra vez.',
        _ => 'No pudimos completar la consulta. Inténtalo nuevamente.',
      };
      throw AssistantFailure(message);
    }
  }
}
