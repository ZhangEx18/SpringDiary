# SpringNote → SpringDiary Fork 工作计划 (P0)

> 目标: 将 SpringNote (v1.0.6, AGPL-3.0) fork 为 AI 日记本。
> 约束: 独立 fork, 不保持 upstream 可合并性。保留 LICENSE 与版权声明。
> 分支: `feat/diary-mode` | 基准: 6c05a4f

## 决策记录 (已由用户确认)

| # | 决策 | 值 |
|---|---|---|
| D1 | P0 范围 | 7 项全做 |
| D2 | 独立 fork | 是, 可重命名/移除工作向功能 |
| D3 | P1 优先 | C 那年今日回溯 + F 导出 + B Ollama 本地 LLM (本次只记录, 不实现) |

## P0 范围 (7 项)

1. **Diary 领域模型**: `notes/diary/YYYY-MM-DD.md` + `DiaryEntry` model + SQLite mood/diary_count
2. **首页"今日日记"快速入口**: 心情 tag + 高光/感想输入, 调用反思模型生成结构化日记
3. **日记页** (新 feature): 月历视图 + 当日详情 + 历史回看, 复用 heatmap 组件
4. **侧边导航加"日记"项**
5. **Diary 反思 prompt 模板** (Rust ai.rs): mood / highlight / reflection / growth_prompt
6. **SQLite stats 扩展** + 统计页"日记面板"
7. **回忆书 RAG 纳入 diary 文件**

---

## Phase 1: 领域模型 + 数据层 (D1 依赖全部后续)

**入口条件**: 无。从当前分支开始。
**出口条件**: `cargo test` 全绿, 新 Rust 测试覆盖 diary 读写/统计/索引; Flutter 侧新模型编译通过。

| # | WHERE | HOW | WHY | ACCEPTANCE | VERIFICATION | DEPENDS |
|---|---|---|---|---|---|---|
| 1.1 | `spring_note/lib/core/models/note_file.dart` | `NoteKind` enum 加 `diary` 值; 确认 noteFile 构造/解析逻辑按 kind 分发 | 全 app 识别日记类型 | `NoteKind.diary` 存在, 编译通过 | `flutter analyze` | — |
| 1.2 | `spring_note/rust/src/note_index.rs` + `api/note_index_api.rs` | `search_all_indexed_notes` 增加 `diary_directory_path` 参数; 内部索引逻辑按 kind 遍历 | RAG 与便签列表可索引日记 | Rust 编译 + 单测覆盖 diary 目录索引 | `cargo test` | 1.1 |
| 1.3 | `spring_note/rust/src/stats.rs` | 新增 `diary_count`, `mood_distribution` 统计; 用已有 `ensure_column` 模式加列; 新增 `count_diary_markdown_files`; 新增 `record_diary_entry` (写 mood + 计数) | 统计面板可展示日记量 | `get_stats_snapshot` 返回 diary 字段; 单测 `counts_diary_files_in_range` | `cargo test stats` | 1.1 |
| 1.4 | `spring_note/lib/core/models/diary_entry.dart` (新) | `DiaryEntry` model: date, mood, highlights, reflection, growthPrompt, rawMarkdown; 与 `NoteFile` 平级; JSON 序列化 | Dart 侧日记领域对象 | 单测: 构造/解析 roundtrip | `flutter test test/diary_entry_test.dart` (新) | 1.1 |
| 1.5 | `spring_note/lib/core/services/diary_note_service.dart` (新) | 借鉴 `daily_note_service.dart` 模式: 读写 `notes/diary/YYYY-MM-DD.md`, 列目录, 查日期 | 日记文件 CRUD | 单测: 创建/读取/列表/按日期查 | `flutter test test/diary_note_service_test.dart` (新) | 1.4 |
| 1.6 | `spring_note/lib/src/rust/note_index.dart` + `api/note_index_api.dart` | 同步 FRB 生成的 Dart 绑定 (跑 codegen) | Dart 调 Rust 索引 diary | 绑定含 diary 参数, `flutter analyze` 通过 | `flutter_rust_bridge_codegen generate` + `flutter analyze` | 1.2 |
| 1.7 | `spring_note/lib/core/models/app_config.dart` | 新增 `diaryReflectionModel` (ModelReference), 默认指向智能生成模型; 序列化兼容旧 config (缺失时用默认) | 日记专用模型可配置 | 旧 config.json 无此字段也能加载; 单测覆盖 | `flutter test` app_config 相关用例 | 1.4 |

**Phase 1 测试清单**:
- Rust: `stats.rs` 加 `counts_diary_files_inside_range`, `records_diary_entry_with_mood`; `note_index` 加 diary 目录遍历用例
- Dart: `diary_entry_test.dart`, `diary_note_service_test.dart`, app_config 兼容性用例
- 覆盖率目标: 新增 Rust 代码 ≥80%, 新增 Dart service ≥80%

---

## Phase 2: 日记页 + 导航 + 首页入口 (UI 核心)

**入口条件**: Phase 1 全绿。
**出口条件**: `flutter test` 全绿; 手动启动后侧边栏出现"日记", 能新建/回看日记; 首页能提交日记。

| # | WHERE | HOW | WHY | ACCEPTANCE | VERIFICATION | DEPENDS |
|---|---|---|---|---|---|---|
| 2.1 | `spring_note/lib/core/router/app_shell.dart` | `AppSection` enum 加 `diary`; `GlobalSidebar` 在"便签"与"回忆书"之间加图标项; `_SidebarLucidePainter` 加日记 icon (书/笔) | 日记入口 | 侧边栏显示日记 icon, 点击切换; 现有 4 项不受影响 | `flutter test` widget test | 1.1 |
| 2.2 | `spring_note/lib/features/diary/diary_page.dart` (新) | 月历视图 (复用/借鉴 `_ActivityHeatmap` 绘制逻辑) + 选中日详情区 + 列表历史回看 | 日记浏览核心 UI | widget test: 月历渲染, 点击日期显示当日摘要 | `flutter test test/diary_page_test.dart` (新) | 2.1, 1.5 |
| 2.3 | `spring_note/lib/features/diary/diary_editor.dart` (新) | 当日编辑: 心情 tag 选择器 (固定集) + 高光/感想输入 + 保存到 diary md; 可复用 `notes_page.dart` 的 Markdown 编辑/预览部件 | 写日记 | widget test: 选 mood → 输入 → 保存 → 文件存在且含 mood 标记 | `flutter test test/diary_editor_test.dart` (新) | 2.2, 1.5 |
| 2.4 | `spring_note/lib/features/home/home_page.dart` | `_QuickCaptureCard` 区域加"今日日记"切换/入口 (tab 或按钮): 心情 tag + 文本, 提交后调 AI 生成结构化日记并写入 diary md; 保留原工作流为可选 | 首页快速写日记 | 首页提交日记 → `notes/diary/当天.md` 生成/更新; 原"完成/问题/明日"流程不受影响 | `flutter test test/home_page_test.dart` (现有) + 新增日记提交用例 | 2.3, 3.2 (先接 mock) |
| 2.5 | `spring_note/lib/features/settings/settings_page.dart` | 侧栏加"日记"分组或统计页入口 (占位, 数据来自 Phase 3/4) | 设置可配置日记偏好 | 设置页出现日记相关项, 可切换 | `flutter analyze` + 手动 | 2.1 |

**Phase 2 测试清单**:
- widget tests: `diary_page_test.dart` (月历+详情), `diary_editor_test.dart` (mood+保存)
- home_page_test 扩展: 日记提交路径
- 覆盖率目标: diary feature 目录 ≥70% (widget 层)

---

## Phase 3: AI 集成 + RAG 纳入 (价值核心)

**入口条件**: Phase 2 全绿 (UI 可交互, mock 数据流通)。
**出口条件**: `cargo test` + `flutter test` 全绿; 配 API key 后日记可 AI 生成; 回忆书可检索日记。

| # | WHERE | HOW | WHY | ACCEPTANCE | VERIFICATION | DEPENDS |
|---|---|---|---|---|---|---|
| 3.1 | `spring_note/rust/src/ai.rs` | 新增 diary prompt 模板: 输入碎片 → 输出 `mood/highlight/reflection/growth_prompt` 结构化 JSON; 借鉴现有 daily note 结构化 prompt 写法 | AI 反思能力 | Rust 单测: 模板生成正确 JSON schema (可加 mock 输出解析测试) | `cargo test` | 1.1 |
| 3.2 | `spring_note/rust/src/api/ai_api.rs` | 暴露 `generate_diary_entry(request)` 方法, 内部走统一 AI service; 复用 token 统计/错误归一化 | Flutter 调 Rust 生成日记 | FRB 绑定生成; 单测: mock AI 返回被解析为 DiaryEntry | `cargo test` + codegen + `flutter analyze` | 3.1, 1.6 |
| 3.3 | `spring_note/lib/core/services/ai_client_service.dart` | 加 `generateDiaryEntry` 方法 (调 Rust); 未配置模型时降级 mock (仿 `mock_ai_service.dart`) | Dart 侧 AI 日记入口 | 单测: mock 路径返回结构化结果 | `flutter test test/ai_client_service_test.dart` (现有扩展) | 3.2 |
| 3.4 | `spring_note/lib/core/services/home_overview_service.dart` 或首页逻辑 | 日记提交流: 输入 → AI → 写 diary md (调用 1.5 的 service) → 刷新日记页 | 端到端日记生成 | 集成测试或手动: 输入 → 文件生成含 mood/highlight/reflection 结构 | `flutter test` + 手动 | 3.3, 2.4 |
| 3.5 | `spring_note/lib/core/services/memory_search_service.dart` + `rust/src/api/note_index_api.rs` | `search_all_indexed_notes` 传入 diary 目录; memory 检索结果带 diary kind 标签 | 回忆书可聊日记 | 集成测试: 建 diary 文件 → memory 检索命中 | `flutter test test/memory_services_test.dart` (扩展) | 1.2, 1.6 |
| 3.6 | `spring_note/lib/core/services/startup_report_generation_service.dart` | 周报可选包含日记的开关, 默认关; 不做新报告类型 | 周期反思 (轻量) | 开关存在且默认关; 不破坏现有日报/周报流程 | `flutter analyze` + 现有测试 | 3.1 |

**Phase 3 测试清单**:
- Rust: ai.rs prompt/schema 单测; ai_api mock 单测
- Dart: ai_client_service mock 路径; memory_services_test 加 diary 检索用例
- 覆盖率: 新增 AI 路径 ≥80%

---

## Phase 4: 统计面板 + 验收打磨 (P0 收尾)

**入口条件**: Phase 3 全绿。
**出口条件**: 全部 P0 验收项通过; `flutter analyze` 0 error; `flutter test` + `cargo test` 全绿。

| # | WHERE | HOW | WHY | ACCEPTANCE | VERIFICATION | DEPENDS |
|---|---|---|---|---|---|---|
| 4.1 | `spring_note/lib/features/settings/settings_stats_panel.dart` | 加"日记面板": 日记总数, 月度 mood 分布 (emoji 计数条), 连续写日记天数 | 用户看到日记成长 | widget test: 面板渲染 mock 数据 | `flutter test test/settings_stats_panel_test.dart` (新/扩) | 1.3, 2.5 |
| 4.2 | `spring_note/lib/src/rust/stats.dart` + `api/stats_api.dart` | 同步 FRB 绑定 (diary 统计字段) | Dart 读日记统计 | 绑定编译通过 | codegen + `flutter analyze` | 1.3 |
| 4.3 | 全仓回归 | 跑全部检查 + 修复 | 交付质量 | 见"P0 停止条件" | 见下 | 全部 |
| 4.4 | `README.md` + `docs/guide/` | 更新为日记本定位 (独立 fork) | 新用户可上手 | 文档描述日记流程 | 手动 review | 4.3 |

**Phase 4 测试清单**: settings_stats_panel widget test; 全量回归。

---

## P0 停止条件 (全部满足才算完成)

1. `cd spring_note && flutter analyze` → 0 error
2. `flutter test` → 全绿 (含新增 diary 测试, 无 skip)
3. `cargo test` (在 `spring_note/rust`) → 全绿
4. 手动验证链: 启动 → 首页选"日记" → 选心情/输入 → AI 生成 → `notes/diary/YYYY-MM-DD.md` 存在且含 mood/highlight/reflection → 日记页月历显示当日 → 回忆书提问命中日记内容 → 统计页显示日记数 + mood 分布
5. 无 API key 时 mock 路径可完整走通 (1-4 步)
6. 旧数据兼容: 已有 config.json / SQLite / daily 笔记不报错, 可正常打开

---

## 风险登记

| 风险 | 等级 | 缓解 |
|---|---|---|
| **FRB codegen**: Rust API 变更后 Dart 绑定未同步 | 高 | 每 Phase 结尾跑 `flutter_rust_bridge_codegen generate` (见 rust_builder/README.md 确认命令), 然后 `flutter analyze` 验证 |
| **SQLite 迁移**: 加列破坏存量用户数据 | 中 | 已确认 `stats.rs::ensure_column` (L411) 幂等迁移模式, 直接复用; 迁移后跑现有 stats 测试 |
| **RAG 索引**: 加 diary 目录增大启动索引量 | 低 | diary 目录按需刷新 (仿现有 lazy refresh); 不阻塞启动 |
| **LICENSE**: 独立 fork 仍须保留 AGPL-3.0 版权声明 | 高 | 保留根 LICENSE; README 注明 fork 来源; 代码头注释不动 |
| **移除工作向功能**: 牛马等级/日薪/牛马时钟 | 中 | P0 **不删除** (减少回归面), 仅 UI 上弱化 (日记 tab 默认); 重命名决策见开放问题 Q2, P1 再定 |
| **HomePage 3225 行巨型文件**: 改动风险集中 | 中 | 日记入口以独立 widget 追加, 不重构现有结构; 改动面控制在 `_QuickCaptureCard` 附近 |

## P1 预留 (本次不实现, 记录)

- **C 那年今日**: 日记页选中日 → 查往年同日 diary 文件 → 显示"去年的今天" (纯读取, 复用 1.5)
- **F 导出**: 选择月份 → 打包 Markdown 或 PDF (需新增 Rust 导出方法 + Dart 导出页)
- **B Ollama 本地 LLM**: Rust `ai_openai.rs` 加本地 OpenAI-compatible 配置模板 (localhost:11434), 供应商页加一键模板; 复用现有协议层, 无新协议

## 开放问题 (Phase 1 开工前需用户答复)

- **Q1 应用重命名**: fork 后叫 `SpringDiary` 还是保留 `SpringNote` 名称? (影响 app.dart 标题、README、窗口标题; 不影响目录名)
- **Q2 牛马功能去留**: 牛马等级/日薪/牛马时钟组件 —— 保留为可选功能, 还是 P1 移除? (P0 默认保留不删)
- **Q3 心情标签集**: 固定 5 档 (😊😐😔😢😠) 还是自由 emoji + 自定义? (P0 建议固定 5 档, 后续扩展)
- **Q4 第 4 个模型**: "日记反思模型" 独立配置 (第 4 个默认模型槽) 还是复用"智能生成模型"? (建议独立, 但默认同模型, 可后续换)
- **Q5 周报/月报**: 现有周报月报面向工作 —— 保留原样, 还是也换日记向 prompt? (P0 建议保留原样, 日记周报留 P1)
