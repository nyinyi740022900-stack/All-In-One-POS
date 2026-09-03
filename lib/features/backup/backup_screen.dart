import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_widgets.dart';
import '../../l10n/app_localizations.dart';
import 'backup_providers.dart';
import 'backup_service.dart';

/// Classifies a raw export/import exception into a translated summary for
/// `l.backupFailed`'s `{error}` placeholder — previously that placeholder
/// was filled with the raw Dart exception (`'$e'`), so a Myanmar-locale
/// user saw mixed-language text (e.g. `BackupService.importReplaceAll`'s
/// `FormatException('Not an MM POS backup file.')` is always English,
/// regardless of app locale). Only known exception shapes get a specific
/// summary; anything else falls back to the shared generic-error string.
String _backupErrorReason(AppLocalizations l, Object e) {
  if (e is FormatException) return l.backupInvalidFile;
  // Both of these are refusals, not failures — the restore was stopped on
  // purpose because going ahead would have destroyed data. Say which.
  if (e is ShopMismatchException) return l.backupWrongShop;
  if (e is UnsyncedDataException) return l.backupUnsyncedBlocked;
  return l.commonUnexpectedError;
}

/// Export the shop's data to a JSON file (shared via the OS sheet — e.g. to
/// Viber → My Notes) and restore it back.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _exporting = false;
  bool _importing = false;
  bool get _busy => _exporting || _importing;

  Future<void> _export() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final file = await ref.read(backupServiceProvider).writeBackupFile();
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json')],
          subject: l.backupShareSubject,
          text: l.backupShareText,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.backupFailed(_backupErrorReason(l, e)))));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _import() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null || picked.files.single.path == null) return;
    if (!mounted) return;

    // Replace-all is destructive — confirm first.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.backupImportConfirmTitle),
        content: Text(l.backupImportConfirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.commonCancel)),
          FilledButton(
              style: AppTheme.dangerFilledButtonStyle(ctx),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.backupImportConfirmAction)),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _importing = true);
    try {
      final jsonStr =
          await File(picked.files.single.path!).readAsString();
      final count =
          await ref.read(backupServiceProvider).importReplaceAll(jsonStr);
      messenger
          .showSnackBar(SnackBar(content: Text(l.backupImportDone(count))));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.backupFailed(_backupErrorReason(l, e)))));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.backupTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppTheme.space4),
        children: [
          Text(l.backupHint, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppTheme.space4),
          Card(
            child: ListTile(
              leading: const IconAvatar(icon: Icons.upload_file),
              title: Text(l.backupExport),
              subtitle: Text(l.backupExportHint),
              // Inline on the tapped row instead of a spinner appended below
              // both cards, which grew the page height and shifted the
              // Import card down mid-tap.
              trailing: _exporting ? const ButtonSpinner() : null,
              onTap: _busy ? null : _export,
            ),
          ),
          Card(
            child: ListTile(
              // Attention, not neutral: import is a replace-all that erases
              // whatever is currently on the device (see the confirm dialog
              // below) — worth a visual nudge before the tap, not just at
              // the confirm step.
              leading: const IconAvatar(
                icon: Icons.download,
                tone: StatusTone.attention,
              ),
              title: Text(l.backupImport),
              subtitle: Text(l.backupImportHint),
              trailing: _importing ? const ButtonSpinner() : null,
              onTap: _busy ? null : _import,
            ),
          ),
        ],
      ),
    );
  }
}
