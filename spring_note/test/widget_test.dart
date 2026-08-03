import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spring_note/core/models/app_config.dart';
import 'package:spring_note/core/models/cloud_sync_config.dart';
import 'package:spring_note/core/models/local_data_state.dart';
import 'package:spring_note/core/models/wallpaper_settings.dart';
import 'package:spring_note/app.dart';
import 'package:spring_note/core/router/app_shell.dart';
import 'package:spring_note/core/services/cloud_sync_service.dart';
import 'package:spring_note/core/services/local_data_service.dart';
import 'package:spring_note/core/services/stats_service.dart';
import 'package:spring_note/core/services/update_check_service.dart';
import 'package:spring_note/core/theme/app_theme.dart';
import 'package:spring_note/features/home/home_page.dart';

void main() {
  testWidgets(
    'SpringNote app disables theme transition to avoid input flicker',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        SpringNoteApp(
          localDataService: _ImmediateLocalDataService(_testLocalDataState()),
          statsService: const _NoopStartupStatsService(),
        ),
      );

      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeAnimationDuration, Duration.zero);
      expect(app.themeAnimationCurve, Curves.linear);
    },
  );

  testWidgets('SpringNote app shows home shell', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final temp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('spring_note_widget_test_'),
    );
    expect(temp, isNotNull);

    addTearDown(() async {
      final directory = temp;
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final state = await tester.runAsync(
      () => LocalDataService(appDataPath: temp!.path).initialize(),
    );
    expect(state, isNotNull);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          localDataState: state!,
          updateCheckService: _IdleUpdateCheckService(),
        ),
      ),
    );

    expect(find.text('首页'), findsOneWidget);
    expect(find.text('今日日记'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    expect(find.text('偏好设置'), findsOneWidget);
  });

  testWidgets('wallpaper theme keeps state surfaces readable', (
    WidgetTester tester,
  ) async {
    final localDataState = _testLocalDataState(
      config: AppConfig.defaults().copyWith(
        wallpaperSettings: WallpaperSettings.defaults.copyWith(
          transparentControls: true,
          controlAlpha: 0.2,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          localDataState: localDataState,
          updateCheckService: _IdleUpdateCheckService(),
        ),
      ),
    );

    final colors = AppTheme.colors(tester.element(find.byType(HomePage)));
    expect(colors.surface.a, 0.2);
    expect(colors.surfaceMuted.a, 0.2);
    expect(colors.surfaceHover.a, 0.30);
    expect(colors.surfacePressed.a, 0.30);
    expect(colors.inputFocusedFill.a, 0.30);
  });

  testWidgets('startup cloud sync confirmation shows home warning', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cloudSyncService = _StartupPendingCloudSyncService();
    final localDataState = _testLocalDataState(
      config: AppConfig.defaults().copyWith(
        cloudSync: CloudSyncConfig.defaults().copyWith(
          enabled: true,
          serverUrl: 'https://example.com/dav',
          username: 'me',
          password: 'token',
          syncOnStartup: true,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          localDataState: localDataState,
          cloudSyncService: cloudSyncService,
          updateCheckService: _IdleUpdateCheckService(),
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => find.text('自动同步遇到问题，请手动同步').evaluate().isNotEmpty,
      'startup cloud sync warning to be shown',
    );

    expect(cloudSyncService.syncCalls, 1);
    expect(find.text('自动同步遇到问题，请手动同步'), findsOneWidget);
  });

  testWidgets('startup cloud sync retries transient failures silently', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cloudSyncService = _RetryingStartupCloudSyncService([
      const CloudSyncResult(
        ok: false,
        message: '无法连接 WebDAV 服务: DNS lookup failed',
        errorCode: 'network',
      ),
      const CloudSyncResult(
        ok: false,
        message: '列出远端文件：HTTP 502',
        errorCode: 'webdav',
      ),
      const CloudSyncResult(ok: true, message: '笔记自动同步完成'),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          localDataState: _startupSyncLocalDataState(),
          cloudSyncService: cloudSyncService,
          updateCheckService: _IdleUpdateCheckService(),
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => cloudSyncService.syncCalls == 1,
      'initial startup cloud sync to finish',
    );
    expect(find.text('自动同步遇到问题，请手动同步'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await _pumpUntil(
      tester,
      () => cloudSyncService.syncCalls == 2,
      'startup cloud sync retry to finish',
    );
    expect(find.text('自动同步遇到问题，请手动同步'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await _pumpUntil(
      tester,
      () => cloudSyncService.syncCalls == 3,
      'second startup cloud sync retry to finish',
    );

    expect(find.text('自动同步遇到问题，请手动同步'), findsNothing);
  });

  testWidgets('startup cloud sync shows warning after retry exhaustion', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cloudSyncService = _RetryingStartupCloudSyncService(
      List.filled(
        4,
        const CloudSyncResult(
          ok: false,
          message: '读取远端同步清单超时',
          errorCode: 'network',
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          localDataState: _startupSyncLocalDataState(),
          cloudSyncService: cloudSyncService,
          updateCheckService: _IdleUpdateCheckService(),
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => cloudSyncService.syncCalls == 1,
      'initial startup cloud sync to finish',
    );
    expect(find.text('自动同步遇到问题，请手动同步'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await _pumpUntil(
      tester,
      () => cloudSyncService.syncCalls == 2,
      'first startup cloud sync retry to finish',
    );
    expect(find.text('自动同步遇到问题，请手动同步'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await _pumpUntil(
      tester,
      () => cloudSyncService.syncCalls == 3,
      'second startup cloud sync retry to finish',
    );
    expect(find.text('自动同步遇到问题，请手动同步'), findsNothing);

    await tester.pump(const Duration(seconds: 15));
    await _pumpUntil(
      tester,
      () =>
          cloudSyncService.syncCalls == 4 &&
          find.text('自动同步遇到问题，请手动同步').evaluate().isNotEmpty,
      'startup cloud sync warning to be shown after retries',
    );

    expect(find.text('自动同步遇到问题，请手动同步'), findsOneWidget);
  });

  testWidgets('startup update check retries offline failure silently', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final updateCheckService = _RetryingUpdateCheckService([
      UpdateCheckResult.failedWithKind(
        currentVersion: '1.0.0',
        failureKind: UpdateCheckFailureKind.offline,
      ),
      UpdateCheckResult.updateAvailable(
        currentVersion: '1.0.0',
        latest: const AppUpdateInfo(
          version: '1.0.1',
          changeTime: '2026-06-30',
          downloadUrl: 'https://example.com/SpringNote.exe',
          changelog: '更新内容',
        ),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppShell(
          localDataState: _testLocalDataState(),
          updateCheckService: updateCheckService,
        ),
      ),
    );

    await _pumpUntil(
      tester,
      () => updateCheckService.calls == 1,
      'initial update check to finish',
    );
    expect(find.text('更新检测失败'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await _pumpUntil(
      tester,
      () => updateCheckService.calls == 2,
      'retry update check to finish',
    );

    expect(find.textContaining('发现新版本 1.0.1'), findsOneWidget);
  });
}

LocalDataState _testLocalDataState({AppConfig? config}) {
  final tempDir = Directory.systemTemp.createTempSync(
    'spring_note_widget_test_',
  );
  addTearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });
  final notes = _joinPath(tempDir.path, 'notes');
  return LocalDataState(
    dataDirectory: tempDir.path,
    configPath: _joinPath(tempDir.path, 'config.json'),
    dailyNotesDirectory: _joinPath(notes, 'daily'),
    weeklyNotesDirectory: _joinPath(notes, 'weekly'),
    monthlyNotesDirectory: _joinPath(notes, 'monthly'),
    diaryNotesDirectory: _joinPath(notes, 'diary'),
    config: config ?? AppConfig.defaults(),
  );
}

LocalDataState _startupSyncLocalDataState() {
  return _testLocalDataState(
    config: AppConfig.defaults().copyWith(
      cloudSync: CloudSyncConfig.defaults().copyWith(
        enabled: true,
        serverUrl: 'https://example.com/dav',
        username: 'me',
        password: 'token',
        syncOnStartup: true,
      ),
    ),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
  String description,
) async {
  for (var index = 0; index < 20; index++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) {
      return;
    }
  }
  fail('Timed out waiting for $description.');
}

String _joinPath(String left, String right) {
  if (left.endsWith(Platform.pathSeparator)) {
    return '$left$right';
  }
  return '$left${Platform.pathSeparator}$right';
}

class _ImmediateLocalDataService extends LocalDataService {
  const _ImmediateLocalDataService(this.state);

  final LocalDataState state;

  @override
  Future<LocalDataState> initialize() async => state;
}

class _NoopStartupStatsService extends StatsService {
  const _NoopStartupStatsService();

  @override
  Future<void> recordAppStartup({required String appDataDir}) async {}
}

class _StartupPendingCloudSyncService extends CloudSyncService {
  int syncCalls = 0;

  @override
  Future<CloudSyncResult> sync({
    required LocalDataState localDataState,
    required CloudSyncTrigger trigger,
    List<String> confirmedDeleteLocal = const [],
    List<String> confirmedDeleteRemote = const [],
    List<String> confirmedOverwriteLocal = const [],
    List<String> confirmedOverwriteRemote = const [],
    List<String> skippedDeleteModifyConflicts = const [],
  }) async {
    syncCalls++;
    return const CloudSyncResult(
      ok: true,
      message: '检测到删除项，请确认后继续同步',
      needsDeleteConfirmation: true,
      pendingDeleteRemote: ['notes/daily/old.md'],
    );
  }
}

class _RetryingStartupCloudSyncService extends CloudSyncService {
  _RetryingStartupCloudSyncService(this.results);

  final List<CloudSyncResult> results;
  int syncCalls = 0;

  @override
  Future<CloudSyncResult> sync({
    required LocalDataState localDataState,
    required CloudSyncTrigger trigger,
    List<String> confirmedDeleteLocal = const [],
    List<String> confirmedDeleteRemote = const [],
    List<String> confirmedOverwriteLocal = const [],
    List<String> confirmedOverwriteRemote = const [],
    List<String> skippedDeleteModifyConflicts = const [],
  }) async {
    final index = syncCalls < results.length ? syncCalls : results.length - 1;
    syncCalls++;
    return results[index];
  }
}

class _IdleUpdateCheckService extends UpdateCheckService {
  @override
  Future<UpdateCheckResult> check({
    UpdateCheckMode mode = UpdateCheckMode.background,
  }) async {
    return UpdateCheckResult.idle;
  }
}

class _RetryingUpdateCheckService extends UpdateCheckService {
  _RetryingUpdateCheckService(this.results);

  final List<UpdateCheckResult> results;
  int calls = 0;

  @override
  Future<UpdateCheckResult> check({
    UpdateCheckMode mode = UpdateCheckMode.background,
  }) async {
    final index = calls < results.length ? calls : results.length - 1;
    calls++;
    return results[index];
  }
}

