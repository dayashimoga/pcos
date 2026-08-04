import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pcos_frontend/features/files/bloc/file_bloc.dart';
import 'package:pcos_frontend/features/files/repository/file_repository.dart';

class MockFileRepository extends Mock implements FileRepository {}

void main() {
  late FileBloc fileBloc;
  late MockFileRepository mockRepo;

  setUp(() {
    mockRepo = MockFileRepository();
    fileBloc = FileBloc(fileRepository: mockRepo);
  });

  tearDown(() => fileBloc.close());

  group('FileBloc', () {
    test('initial state is FileInitial', () {
      expect(fileBloc.state, isA<FileInitial>());
    });

    blocTest<FileBloc, FileState>(
      'emits [FileLoading, FileLoaded] on successful root load',
      build: () {
        when(() => mockRepo.listRoot())
            .thenAnswer((_) async => <String, dynamic>{
                  'entries': <Map<String, dynamic>>[
                    {
                      'id': '1',
                      'name': 'Documents',
                      'entry_type': 'folder',
                    },
                    {
                      'id': '2',
                      'name': 'photo.jpg',
                      'entry_type': 'file',
                      'size_bytes': 1024,
                    },
                  ],
                  'path': <Map<String, dynamic>>[],
                  'total': 2,
                });
        return FileBloc(fileRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const FilesLoadRequested()),
      expect: () => [isA<FileLoading>(), isA<FileLoaded>()],
      verify: (_) {
        verify(() => mockRepo.listRoot()).called(1);
      },
    );

    blocTest<FileBloc, FileState>(
      'emits [FileLoading, FileLoaded] on folder navigation',
      build: () {
        when(() => mockRepo.listFolder('folder-1'))
            .thenAnswer((_) async => <String, dynamic>{
                  'entries': <Map<String, dynamic>>[],
                  'path': <Map<String, dynamic>>[
                    {'id': 'folder-1', 'name': 'Documents'},
                  ],
                  'total': 0,
                });
        return FileBloc(fileRepository: mockRepo);
      },
      act: (bloc) =>
          bloc.add(const FilesLoadRequested(folderId: 'folder-1')),
      expect: () => [isA<FileLoading>(), isA<FileLoaded>()],
    );

    blocTest<FileBloc, FileState>(
      'emits [FileActionSuccess] then reloads on folder create',
      build: () {
        when(() => mockRepo.createFolder('New Folder', null))
            .thenAnswer((_) async => <String, dynamic>{
                  'id': '3',
                  'name': 'New Folder',
                });
        when(() => mockRepo.listRoot())
            .thenAnswer((_) async => <String, dynamic>{
                  'entries': <Map<String, dynamic>>[],
                  'path': <Map<String, dynamic>>[],
                  'total': 0,
                });
        return FileBloc(fileRepository: mockRepo);
      },
      act: (bloc) =>
          bloc.add(const FolderCreateRequested(name: 'New Folder')),
      expect: () =>
          [isA<FileActionSuccess>(), isA<FileLoading>(), isA<FileLoaded>()],
    );

    blocTest<FileBloc, FileState>(
      'emits [FileError] on load failure',
      build: () {
        when(() => mockRepo.listRoot())
            .thenThrow(Exception('Network error'));
        return FileBloc(fileRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const FilesLoadRequested()),
      expect: () => [isA<FileLoading>(), isA<FileError>()],
    );

    blocTest<FileBloc, FileState>(
      'emits [FileActionSuccess] on delete',
      build: () {
        when(() => mockRepo.deleteItem('item-1'))
            .thenAnswer((_) async {});
        return FileBloc(fileRepository: mockRepo);
      },
      act: (bloc) => bloc.add(const FileDeleteRequested('item-1')),
      expect: () => [isA<FileActionSuccess>()],
    );
  });
}
