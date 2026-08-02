import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/di/service_locator.dart';
import '../../../core/theme/app_theme.dart';
import '../../files/bloc/file_bloc.dart';

class TrashPage extends StatelessWidget {
  const TrashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<FileBloc>()..add(const TrashLoadRequested()),
      child: const _TrashContent(),
    );
  }
}

class _TrashContent extends StatelessWidget {
  const _TrashContent();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FileBloc, FileState>(
      listener: (context, state) {
        if (state is FileActionSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message), backgroundColor: AppTheme.success));
        }
      },
      builder: (context, state) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Trash', style: Theme.of(context).textTheme.displayMedium),
                const SizedBox(height: 4),
                Text('Items in trash are automatically deleted after 30 days', style: Theme.of(context).textTheme.bodyLarge),
              ]),
              if (state is TrashLoaded && state.entries.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () => _confirmEmptyTrash(context),
                  icon: const Icon(Icons.delete_forever_rounded, size: 18),
                  label: const Text('Empty Trash'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
                ),
            ]),
            const SizedBox(height: 32),
            if (state is FileLoading) const Center(child: CircularProgressIndicator()),
            if (state is TrashLoaded && state.entries.isEmpty)
              Container(width: double.infinity, padding: const EdgeInsets.all(48),
                decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
                child: Column(children: [
                  Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppTheme.success.withOpacity(0.1), borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.check_circle_outline_rounded, size: 48, color: AppTheme.success)),
                  const SizedBox(height: 20),
                  const Text('Trash is empty', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                ])),
            if (state is TrashLoaded && state.entries.isNotEmpty)
              Container(
                decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.border)),
                child: Column(children: state.entries.map((e) => ListTile(
                  leading: Icon(e['entry_type'] == 'folder' ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                    color: AppTheme.textMuted),
                  title: Text(e['name'] ?? '', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                  subtitle: Text(e['entry_type'] ?? '', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.restore_rounded, color: AppTheme.primary), tooltip: 'Restore',
                      onPressed: () => context.read<FileBloc>().add(TrashRestoreRequested(e['id']))),
                  ]),
                )).toList()),
              ),
          ]),
        );
      },
    );
  }

  void _confirmEmptyTrash(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Empty Trash?'),
      content: const Text('This will permanently delete all items in trash. This action cannot be undone.'),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
          onPressed: () { context.read<FileBloc>().add(const TrashEmptyRequested()); Navigator.pop(ctx); },
          child: const Text('Empty Trash'),
        ),
      ],
    ));
  }
}
