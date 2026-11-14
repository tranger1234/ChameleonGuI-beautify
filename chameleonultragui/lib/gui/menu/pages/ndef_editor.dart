import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/ndef.dart';
import 'package:flutter/material.dart';
import 'package:chameleonultragui/gui/component/glass.dart';
import 'package:flutter/services.dart';

class NdefEditorPage extends StatefulWidget {
  final List<NdefRecord> records;
  final int capacity;
  final String mappingName;
  final String? parseWarning;
  final ValueChanged<Uint8List> onSave;

  const NdefEditorPage({
    super.key,
    required this.records,
    required this.capacity,
    required this.mappingName,
    required this.onSave,
    this.parseWarning,
  });

  @override
  State<NdefEditorPage> createState() => _NdefEditorPageState();
}

class _NdefEditorPageState extends State<NdefEditorPage> {
  late final List<NdefRecord> records = List<NdefRecord>.from(widget.records);
  late final Uint8List initialMessage;
  String? error;
  bool allowPop = false;
  bool discardDialogOpen = false;

  @override
  void initState() {
    super.initState();
    initialMessage = NdefCodec.encodeMessage(widget.records);
  }

  int get encodedSize => NdefCodec.encodeMessage(records).length;

  bool get hasUnsavedChanges {
    final current = NdefCodec.encodeMessage(records);
    if (current.length != initialMessage.length) return true;
    for (int index = 0; index < current.length; index++) {
      if (current[index] != initialMessage[index]) return true;
    }
    return false;
  }

  String _kindLabel(AppLocalizations localizations, NdefRecordKind kind) =>
      switch (kind) {
        NdefRecordKind.text => localizations.ndef_kind_text,
        NdefRecordKind.uri => localizations.ndef_kind_uri,
        NdefRecordKind.mime => localizations.ndef_kind_mime,
        NdefRecordKind.external => localizations.ndef_kind_external,
        NdefRecordKind.raw => localizations.ndef_kind_raw,
      };

  Future<void> _editRecord({int? index}) async {
    final localizations = AppLocalizations.of(context)!;
    final existing = index == null ? null : records[index];
    NdefRecordKind kind = existing?.kind ?? NdefRecordKind.text;
    final languageController = TextEditingController(
        text: existing?.kind == NdefRecordKind.text
            ? existing!.textLanguage
            : 'en');
    final valueController = TextEditingController(
        text: existing == null ? '' : existing.displayValue);
    final typeController = TextEditingController(
      text: switch (existing?.kind) {
        NdefRecordKind.mime => existing!.typeName,
        NdefRecordKind.external => existing!.typeName,
        NdefRecordKind.raw => NdefCodec.bytesToHex(existing!.type),
        _ => '',
      },
    );
    int rawTnf = existing?.tnf ?? 1;
    String? dialogError;

    final result = await showFrostedDialog<NdefRecord>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget valueField({
            required String label,
            int minLines = 1,
            int maxLines = 4,
            List<TextInputFormatter>? inputFormatters,
          }) =>
              TextField(
                controller: valueController,
                minLines: minLines,
                maxLines: maxLines,
                inputFormatters: inputFormatters,
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                ),
              );

          return AlertDialog(
            title: Text(index == null
                ? localizations.ndef_add_record_title
                : localizations.ndef_edit_record_title),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<NdefRecordKind>(
                      initialValue: kind,
                      decoration: InputDecoration(
                        labelText: localizations.ndef_record_type,
                        border: const OutlineInputBorder(),
                      ),
                      items: NdefRecordKind.values
                          .map((value) => DropdownMenuItem(
                                value: value,
                                child: Text(_kindLabel(localizations, value)),
                              ))
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          kind = value;
                          dialogError = null;
                          if (kind == NdefRecordKind.mime &&
                              typeController.text.isEmpty) {
                            typeController.text = 'text/plain';
                          } else if (kind == NdefRecordKind.external &&
                              typeController.text.isEmpty) {
                            typeController.text = 'example.com:type';
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    if (kind == NdefRecordKind.text) ...[
                      TextField(
                        controller: languageController,
                        maxLength: 63,
                        decoration: InputDecoration(
                          labelText: localizations.ndef_language_code,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      valueField(
                          label: localizations.ndef_kind_text,
                          minLines: 3,
                          maxLines: 8),
                    ] else if (kind == NdefRecordKind.uri) ...[
                      valueField(label: localizations.ndef_kind_uri, maxLines: 2),
                    ] else if (kind == NdefRecordKind.mime ||
                        kind == NdefRecordKind.external) ...[
                      TextField(
                        controller: typeController,
                        decoration: InputDecoration(
                          labelText: kind == NdefRecordKind.mime
                              ? localizations.ndef_mime_type
                              : localizations.ndef_external_type,
                          hintText: kind == NdefRecordKind.mime
                              ? 'text/plain'
                              : 'example.com:type',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      valueField(
                          label: localizations.ndef_payload,
                          minLines: 3,
                          maxLines: 8),
                    ] else ...[
                      DropdownButtonFormField<int>(
                        initialValue: rawTnf,
                        decoration: const InputDecoration(
                          labelText: 'TNF',
                          border: OutlineInputBorder(),
                        ),
                        items: List.generate(
                          8,
                          (value) => DropdownMenuItem(
                              value: value, child: Text(value.toString())),
                        ),
                        onChanged: (value) {
                          if (value != null) rawTnf = value;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: typeController,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9A-Fa-f\s]')),
                        ],
                        decoration: InputDecoration(
                          labelText: localizations.ndef_type_hex,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      valueField(
                        label: localizations.ndef_payload_hex,
                        minLines: 3,
                        maxLines: 8,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9A-Fa-f\s]')),
                        ],
                      ),
                    ],
                    if (dialogError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        dialogError!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(AppLocalizations.of(context)!.cancel),
              ),
              TextButton(
                onPressed: () {
                  try {
                    final created = switch (kind) {
                      NdefRecordKind.text => NdefRecord.text(
                          valueController.text,
                          language: languageController.text.trim().isEmpty
                              ? 'en'
                              : languageController.text.trim(),
                        ),
                      NdefRecordKind.uri =>
                        NdefRecord.uri(valueController.text.trim()),
                      NdefRecordKind.mime => NdefRecord.mime(
                          typeController.text.trim(), valueController.text),
                      NdefRecordKind.external => NdefRecord.external(
                          typeController.text.trim(), valueController.text),
                      NdefRecordKind.raw => NdefRecord(
                          tnf: rawTnf,
                          type: NdefCodec.hexToBytes(typeController.text),
                          id: existing?.id ?? const [],
                          payload: NdefCodec.hexToBytes(valueController.text),
                        ),
                    };
                    final record = existing == null || created.id.isNotEmpty
                        ? created
                        : NdefRecord(
                            tnf: created.tnf,
                            type: created.type,
                            id: existing.id,
                            payload: created.payload,
                          );
                    Navigator.pop(dialogContext, record);
                  } catch (exception) {
                    setDialogState(() => dialogError = exception.toString());
                  }
                },
                child: Text(AppLocalizations.of(context)!.save),
              ),
            ],
          );
        },
      ),
    );

    // The dialog's text fields remain mounted during the route's reverse
    // transition, even though showDialog's future has already completed.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    languageController.dispose();
    valueController.dispose();
    typeController.dispose();
    if (result == null) return;
    setState(() {
      if (index == null) {
        records.add(result);
      } else {
        records[index] = result;
      }
      error = null;
    });
  }

  void _save() {
    final message = NdefCodec.encodeMessage(records);
    if (message.length > widget.capacity) {
      setState(() => error = AppLocalizations.of(context)!
          .ndef_over_capacity(widget.capacity, message.length));
      return;
    }
    widget.onSave(message);
    setState(() => allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _confirmDiscard() async {
    if (discardDialogOpen) return;
    discardDialogOpen = true;
    final localizations = AppLocalizations.of(context)!;
    final discard = await showFrostedDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(localizations.unsaved_changes),
        content: Text(localizations.unsaved_changes_message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(localizations.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(localizations.discard),
          ),
        ],
      ),
    );
    discardDialogOpen = false;
    if (discard == true && mounted) {
      setState(() => allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final size = encodedSize;
    final overCapacity = size > widget.capacity;
    return PopScope(
      canPop: allowPop || !hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && hasUnsavedChanges) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(localizations.ndef_editor),
          actions: [
            IconButton(
              onPressed: _save,
              icon: const Icon(Icons.save),
              tooltip: localizations.save,
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _editRecord(),
          icon: const Icon(Icons.add),
          label: Text(localizations.ndef_add_record),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            Card(
              child: ListTile(
                title: Text(widget.mappingName),
                subtitle:
                    Text(localizations.ndef_capacity(widget.capacity, size)),
                trailing: overCapacity
                    ? Icon(Icons.error,
                        color: Theme.of(context).colorScheme.error)
                    : null,
              ),
            ),
            if (widget.parseWarning != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: Text(localizations.ndef_parse_error),
                  subtitle: Text(widget.parseWarning!),
                ),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            if (records.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(child: Text(localizations.ndef_empty)),
              ),
            ...List.generate(records.length, (index) {
              final record = records[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(_kindLabel(localizations, record.kind)),
                  subtitle: Text(
                    record.displayValue.isEmpty
                        ? record.typeName
                        : record.displayValue,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _editRecord(index: index),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: index == 0
                            ? null
                            : () => setState(() {
                                  final record = records.removeAt(index);
                                  records.insert(index - 1, record);
                                }),
                        icon: const Icon(Icons.arrow_upward),
                        tooltip: localizations.move_up,
                      ),
                      IconButton(
                        onPressed: index == records.length - 1
                            ? null
                            : () => setState(() {
                                  final record = records.removeAt(index);
                                  records.insert(index + 1, record);
                                }),
                        icon: const Icon(Icons.arrow_downward),
                        tooltip: localizations.move_down,
                      ),
                      IconButton(
                        onPressed: () =>
                            setState(() => records.removeAt(index)),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: localizations.delete,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
