import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/model_config.dart';
import 'package:spring_note/core/models/provider_config.dart';
import 'package:spring_note/core/services/local_data_service.dart';

void main() {
  test('local data service creates first-run data layout', () async {
    final temp = await Directory.systemTemp.createTemp('spring_note_test_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final state = await LocalDataService(appDataPath: temp.path).initialize();

    expect(await File(state.configPath).exists(), isTrue);
    expect(await Directory(state.dailyNotesDirectory).exists(), isTrue);
    expect(await Directory(state.weeklyNotesDirectory).exists(), isTrue);
    expect(await Directory(state.monthlyNotesDirectory).exists(), isTrue);
    expect(
      state.config.defaultModels.keys,
      contains('intelligentGenerationModel'),
    );
    expect(state.config.defaultModels.keys, contains('editCompletionModel'));
    expect(state.config.defaultModels.keys, contains('memoryBookModel'));
    expect(state.config.apiLogEnabled, isFalse);
  });

  test('local data service saves and reads provider model config', () async {
    final temp = await Directory.systemTemp.createTemp('spring_note_config_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final service = LocalDataService(appDataPath: temp.path);
    final state = await service.initialize();
    final provider = ProviderConfig.template('OpenAI');
    final config = state.config.copyWith(
      dailyWorkHours: 9,
      apiLogEnabled: true,
      providers: [provider],
      defaultModels: {
        ...state.config.defaultModels,
        'intelligentGenerationModel': provider.models.first.modelId,
      },
    );

    await service.saveConfig(config);
    final reloaded = await service.readConfig();

    expect(reloaded.dailyWorkHours, 9);
    expect(reloaded.apiLogEnabled, isTrue);
    expect(reloaded.providers, hasLength(1));
    expect(reloaded.providers.first.name, 'OpenAI');
    expect(reloaded.providers.first.models.first.fimMode, 'none');
    expect(
      reloaded.providers.first.models.first.toJson().keys,
      isNot(contains('fimMode')),
    );
    expect(
      reloaded.defaultModels['intelligentGenerationModel'],
      'gpt-4.1-mini',
    );
  });

  test('local data service migrates data to custom directory', () async {
    final temp = await Directory.systemTemp.createTemp('spring_note_migrate_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final service = LocalDataService(appDataPath: temp.path);
    final state = await service.initialize();
    final dailyNote = File(
      '${state.dailyNotesDirectory}${Platform.pathSeparator}2026-06-24.md',
    );
    await dailyNote.writeAsString('# Today\n\nMoved note');

    final target = Directory(
      '${temp.path}${Platform.pathSeparator}custom_store',
    );
    final migrated = await service.migrateDataDirectory(
      currentState: state.copyWith(
        config: state.config.copyWith(dailyWorkHours: 7),
      ),
      targetDirectory: target.path,
    );

    expect(migrated.dataDirectory, target.absolute.path);
    expect(migrated.config.customDataDirectory, target.absolute.path);
    expect(await File(migrated.configPath).exists(), isTrue);
    expect(
      await File(
        '${migrated.dailyNotesDirectory}${Platform.pathSeparator}2026-06-24.md',
      ).readAsString(),
      '# Today\n\nMoved note',
    );

    final reinitialized = await service.initialize();
    expect(reinitialized.dataDirectory, target.absolute.path);
    expect(reinitialized.config.dailyWorkHours, 7);
  });

  test(
    'local data service restores default directory and clears pointer',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'spring_note_default_',
      );
      addTearDown(() async {
        if (await temp.exists()) {
          await temp.delete(recursive: true);
        }
      });

      final service = LocalDataService(appDataPath: temp.path);
      final state = await service.initialize();
      final target = Directory(
        '${temp.path}${Platform.pathSeparator}custom_store',
      );
      final migrated = await service.migrateDataDirectory(
        currentState: state,
        targetDirectory: target.path,
      );

      final restored = await service.migrateDataDirectory(
        currentState: migrated,
        targetDirectory: null,
      );

      final defaultRoot = '${temp.path}${Platform.pathSeparator}SpringNote';
      expect(restored.dataDirectory, defaultRoot);
      expect(restored.config.customDataDirectory, isNull);
      expect(
        await File(
          '$defaultRoot${Platform.pathSeparator}data-directory.json',
        ).exists(),
        isFalse,
      );

      final reinitialized = await service.initialize();
      expect(reinitialized.dataDirectory, defaultRoot);
    },
  );
  test('model config derives FIM mode from completion model type', () {
    const completionModel = ModelConfig(
      modelId: 'fim-model',
      displayName: 'FIM Model',
      modelTypes: ['chat', 'completion'],
    );
    expect(completionModel.fimMode, 'completions');
    expect(completionModel.toJson().keys, isNot(contains('fimMode')));

    final migrated = ModelConfig.fromJson({
      'modelId': 'legacy-fim-model',
      'displayName': 'Legacy FIM Model',
      'modelTypes': ['chat'],
      'fimMode': 'completions',
    });
    expect(migrated.modelTypes, contains('completion'));
    expect(migrated.fimMode, 'completions');
  });
}
