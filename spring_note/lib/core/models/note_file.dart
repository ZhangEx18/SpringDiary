enum NoteKind {
  diary(label: '日记', directoryName: 'diary', suffix: '日记');

  const NoteKind({
    required this.label,
    required this.directoryName,
    required this.suffix,
  });

  final String label;
  final String directoryName;
  final String suffix;
}

class NoteFile {
  const NoteFile({
    required this.path,
    required this.name,
    required this.title,
    required this.modifiedAt,
    required this.kind,
    this.preview = '',
    this.searchText = '',
  });

  final String path;
  final String name;
  final String title;
  final DateTime modifiedAt;
  final NoteKind kind;
  final String preview;
  final String searchText;
}
