import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../repository/file_repository.dart';

// ─── Events ─────────────────────────────────────────────
abstract class FileEvent extends Equatable {
  const FileEvent();
  @override
  List<Object?> get props => [];
}

class FilesLoadRequested extends FileEvent {
  final String? folderId;
  const FilesLoadRequested({this.folderId});
  @override
  List<Object?> get props => [folderId];
}

class FileUploadRequested extends FileEvent {
  final String filename;
  final List<int> bytes;
  final String? parentId;
  const FileUploadRequested(
      {required this.filename, required this.bytes, this.parentId});
  @override
  List<Object?> get props => [filename, parentId];
}

class FolderCreateRequested extends FileEvent {
  final String name;
  final String? parentId;
  const FolderCreateRequested({required this.name, this.parentId});
  @override
  List<Object?> get props => [name, parentId];
}

class FileDeleteRequested extends FileEvent {
  final String itemId;
  const FileDeleteRequested(this.itemId);
  @override
  List<Object?> get props => [itemId];
}

class FileRenameRequested extends FileEvent {
  final String itemId;
  final String newName;
  const FileRenameRequested({required this.itemId, required this.newName});
  @override
  List<Object?> get props => [itemId, newName];
}

class FileMoveRequested extends FileEvent {
  final String itemId;
  final String? targetFolderId;
  const FileMoveRequested({required this.itemId, this.targetFolderId});
  @override
  List<Object?> get props => [itemId, targetFolderId];
}

class TrashLoadRequested extends FileEvent {
  const TrashLoadRequested();
}

class TrashRestoreRequested extends FileEvent {
  final String itemId;
  const TrashRestoreRequested(this.itemId);
  @override
  List<Object?> get props => [itemId];
}

class TrashEmptyRequested extends FileEvent {
  const TrashEmptyRequested();
}

// ─── States ─────────────────────────────────────────────
abstract class FileState extends Equatable {
  const FileState();
  @override
  List<Object?> get props => [];
}

class FileInitial extends FileState {
  const FileInitial();
}

class FileLoading extends FileState {
  const FileLoading();
}

class FileLoaded extends FileState {
  final List<Map<String, dynamic>> entries;
  final List<Map<String, dynamic>> breadcrumb;
  final String? currentFolderId;
  final int total;
  const FileLoaded(
      {required this.entries,
      required this.breadcrumb,
      this.currentFolderId,
      required this.total});
  @override
  List<Object?> get props => [entries, currentFolderId, total];
}

class FileActionSuccess extends FileState {
  final String message;
  const FileActionSuccess(this.message);
  @override
  List<Object?> get props => [message];
}

class FileError extends FileState {
  final String message;
  const FileError(this.message);
  @override
  List<Object?> get props => [message];
}

class TrashLoaded extends FileState {
  final List<Map<String, dynamic>> entries;
  const TrashLoaded({required this.entries});
  @override
  List<Object?> get props => [entries];
}

// ─── BLoC ───────────────────────────────────────────────
class FileBloc extends Bloc<FileEvent, FileState> {
  final FileRepository fileRepository;

  FileBloc({required this.fileRepository}) : super(const FileInitial()) {
    on<FilesLoadRequested>(_onLoad);
    on<FileUploadRequested>(_onUpload);
    on<FolderCreateRequested>(_onCreateFolder);
    on<FileDeleteRequested>(_onDelete);
    on<FileRenameRequested>(_onRename);
    on<FileMoveRequested>(_onMove);
    on<TrashLoadRequested>(_onLoadTrash);
    on<TrashRestoreRequested>(_onRestore);
    on<TrashEmptyRequested>(_onEmptyTrash);
  }

  Future<void> _onLoad(
      FilesLoadRequested event, Emitter<FileState> emit) async {
    emit(const FileLoading());
    try {
      final result = event.folderId != null
          ? await fileRepository.listFolder(event.folderId!)
          : await fileRepository.listRoot();
      emit(FileLoaded(
        entries: List<Map<String, dynamic>>.from(result['entries'] ?? []),
        breadcrumb: List<Map<String, dynamic>>.from(result['path'] ?? []),
        currentFolderId: event.folderId,
        total: result['total'] ?? 0,
      ));
    } catch (e) {
      emit(FileError(e.toString()));
    }
  }

  Future<void> _onUpload(
      FileUploadRequested event, Emitter<FileState> emit) async {
    try {
      await fileRepository.uploadFile(
          event.filename, event.bytes, event.parentId);
      emit(const FileActionSuccess('File uploaded successfully'));
      add(FilesLoadRequested(folderId: event.parentId));
    } catch (e) {
      emit(FileError(e.toString()));
    }
  }

  Future<void> _onCreateFolder(
      FolderCreateRequested event, Emitter<FileState> emit) async {
    try {
      await fileRepository.createFolder(event.name, event.parentId);
      emit(const FileActionSuccess('Folder created'));
      add(FilesLoadRequested(folderId: event.parentId));
    } catch (e) {
      emit(FileError(e.toString()));
    }
  }

  Future<void> _onDelete(
      FileDeleteRequested event, Emitter<FileState> emit) async {
    try {
      await fileRepository.deleteItem(event.itemId);
      emit(const FileActionSuccess('Moved to trash'));
    } catch (e) {
      emit(FileError(e.toString()));
    }
  }

  Future<void> _onRename(
      FileRenameRequested event, Emitter<FileState> emit) async {
    try {
      await fileRepository.renameItem(event.itemId, event.newName);
      emit(const FileActionSuccess('Renamed'));
    } catch (e) {
      emit(FileError(e.toString()));
    }
  }

  Future<void> _onMove(FileMoveRequested event, Emitter<FileState> emit) async {
    try {
      await fileRepository.moveItem(event.itemId, event.targetFolderId);
      emit(const FileActionSuccess('Moved'));
    } catch (e) {
      emit(FileError(e.toString()));
    }
  }

  Future<void> _onLoadTrash(
      TrashLoadRequested event, Emitter<FileState> emit) async {
    emit(const FileLoading());
    try {
      final result = await fileRepository.listTrash();
      emit(TrashLoaded(entries: List<Map<String, dynamic>>.from(result)));
    } catch (e) {
      emit(FileError(e.toString()));
    }
  }

  Future<void> _onRestore(
      TrashRestoreRequested event, Emitter<FileState> emit) async {
    try {
      await fileRepository.restoreFromTrash(event.itemId);
      emit(const FileActionSuccess('Restored'));
      add(const TrashLoadRequested());
    } catch (e) {
      emit(FileError(e.toString()));
    }
  }

  Future<void> _onEmptyTrash(
      TrashEmptyRequested event, Emitter<FileState> emit) async {
    try {
      await fileRepository.emptyTrash();
      emit(const FileActionSuccess('Trash emptied'));
      add(const TrashLoadRequested());
    } catch (e) {
      emit(FileError(e.toString()));
    }
  }
}
