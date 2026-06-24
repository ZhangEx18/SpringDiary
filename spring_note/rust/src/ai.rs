use crate::frb_generated::StreamSink;
use crate::{ai_claude, ai_gemini, ai_openai, stats};
use serde_json::Value;

#[derive(Clone, Debug)]
pub struct AiProvider {
    pub id: String,
    pub name: String,
    pub protocol: String,
    pub api_key: String,
    pub base_url: String,
    pub api_path: String,
}

#[derive(Clone, Debug)]
pub struct AiModel {
    pub model_id: String,
    pub display_name: String,
}

#[derive(Clone, Debug)]
pub struct AiChatRequest {
    pub app_data_dir: String,
    pub provider: AiProvider,
    pub model: AiModel,
    pub system_prompt: String,
    pub user_prompt: String,
    pub purpose: String,
    pub api_log_enabled: bool,
}

#[derive(Clone, Debug)]
pub struct AiChatMessage {
    pub role: String,
    pub content: String,
    pub reasoning_content: String,
    pub tool_call_id: String,
    pub tool_calls: Vec<AiToolCall>,
}

#[derive(Clone, Debug)]
pub struct AiToolCall {
    pub id: String,
    pub name: String,
    pub arguments: String,
}

#[derive(Clone, Debug)]
pub struct StructuredNoteRequest {
    pub app_data_dir: String,
    pub provider: AiProvider,
    pub model: AiModel,
    pub input: String,
    pub industry: String,
    pub api_log_enabled: bool,
}

#[derive(Clone, Debug)]
pub struct DailyMergeRequest {
    pub app_data_dir: String,
    pub provider: AiProvider,
    pub model: AiModel,
    pub existing_markdown: String,
    pub raw_input: String,
    pub completed: Vec<String>,
    pub issues: Vec<String>,
    pub plans: Vec<String>,
    pub date: String,
    pub industry: String,
    pub api_log_enabled: bool,
}

#[derive(Clone, Debug)]
pub struct ReportRequest {
    pub app_data_dir: String,
    pub provider: AiProvider,
    pub model: AiModel,
    pub source_markdown: String,
    pub period_label: String,
    pub industry: String,
    pub api_log_enabled: bool,
}

#[derive(Clone, Debug)]
pub struct MemoryChatRequest {
    pub app_data_dir: String,
    pub provider: AiProvider,
    pub model: AiModel,
    pub question: String,
    pub context_markdown: String,
    pub api_log_enabled: bool,
}

#[derive(Clone, Debug)]
pub struct MemoryToolChatRequest {
    pub app_data_dir: String,
    pub provider: AiProvider,
    pub model: AiModel,
    pub messages: Vec<AiChatMessage>,
    pub thinking_enabled: bool,
    pub reasoning_effort: String,
    pub api_log_enabled: bool,
}

#[derive(Clone, Debug)]
pub struct FimCompleteRequest {
    pub app_data_dir: String,
    pub provider: AiProvider,
    pub model: AiModel,
    pub prompt: String,
    pub suffix: String,
    pub api_log_enabled: bool,
}

#[derive(Clone, Debug)]
pub struct AiTextResult {
    pub ok: bool,
    pub content: String,
    pub error_code: String,
    pub error_message: String,
    pub input_tokens: i32,
    pub output_tokens: i32,
    pub cached_tokens: i32,
    pub provider_name: String,
    pub model_id: String,
}

#[derive(Clone, Debug)]
pub struct MemoryToolChatResult {
    pub ok: bool,
    pub content: String,
    pub reasoning_content: String,
    pub tool_calls: Vec<AiToolCall>,
    pub error_code: String,
    pub error_message: String,
    pub input_tokens: i32,
    pub output_tokens: i32,
    pub cached_tokens: i32,
    pub provider_name: String,
    pub model_id: String,
}

#[derive(Clone, Debug)]
pub struct MemoryToolChatStreamEvent {
    pub event_type: String,
    pub content_delta: String,
    pub reasoning_delta: String,
    pub content: String,
    pub reasoning_content: String,
    pub tool_calls: Vec<AiToolCall>,
    pub error_code: String,
    pub error_message: String,
    pub input_tokens: i32,
    pub output_tokens: i32,
    pub cached_tokens: i32,
}

#[derive(Clone, Debug)]
pub struct StructuredNoteResult {
    pub ok: bool,
    pub completed: Vec<String>,
    pub issues: Vec<String>,
    pub plans: Vec<String>,
    pub raw_content: String,
    pub error_code: String,
    pub error_message: String,
    pub input_tokens: i32,
    pub output_tokens: i32,
    pub cached_tokens: i32,
}

#[derive(Clone, Debug)]
pub struct ProviderTestResult {
    pub ok: bool,
    pub message: String,
    pub error_code: String,
}

#[derive(Clone, Debug)]
pub struct ModelListResult {
    pub ok: bool,
    pub models: Vec<AiModel>,
    pub error_code: String,
    pub error_message: String,
}

pub async fn chat(request: AiChatRequest) -> AiTextResult {
    if request.provider.api_key.trim().is_empty() {
        return AiTextResult::error(
            &request,
            "missing_api_key",
            "供应商 API Key 为空，已保留 mock 流程。",
            0,
            0,
            0,
        );
    }

    let response = match request.provider.protocol.as_str() {
        "gemini" => ai_gemini::chat(&request).await,
        "claude" => ai_claude::chat(&request).await,
        _ => ai_openai::chat(&request).await,
    };

    let result = match response {
        Ok(result) => result,
        Err(error) => AiTextResult::error(&request, "request_failed", &error, 0, 0, 0),
    };

    let _ = stats::record_model_call(&request.app_data_dir, &request, &result);
    result
}

pub async fn test_provider_connection(
    app_data_dir: String,
    provider: AiProvider,
    model: AiModel,
    api_log_enabled: bool,
) -> ProviderTestResult {
    let request = AiChatRequest {
        app_data_dir,
        provider,
        model,
        system_prompt: "You are a connection test endpoint. Reply with OK only.".to_string(),
        user_prompt: "Say OK.".to_string(),
        purpose: "provider_connection_test".to_string(),
        api_log_enabled,
    };
    let result = chat(request).await;
    if result.ok {
        ProviderTestResult {
            ok: true,
            message: "连接成功".to_string(),
            error_code: String::new(),
        }
    } else {
        ProviderTestResult {
            ok: false,
            message: result.error_message,
            error_code: result.error_code,
        }
    }
}

pub async fn fetch_provider_models(
    app_data_dir: String,
    provider: AiProvider,
    api_log_enabled: bool,
) -> ModelListResult {
    if provider.api_key.trim().is_empty() {
        return ModelListResult {
            ok: false,
            models: vec![],
            error_code: "missing_api_key".to_string(),
            error_message: "供应商 API Key 为空。".to_string(),
        };
    }

    let result = match provider.protocol.as_str() {
        "gemini" => ai_gemini::fetch_models(&app_data_dir, &provider, api_log_enabled).await,
        "claude" => ai_claude::fetch_models(&app_data_dir, &provider, api_log_enabled).await,
        _ => ai_openai::fetch_models(&app_data_dir, &provider, api_log_enabled).await,
    };

    match result {
        Ok(models) => {
            let request = AiChatRequest {
                app_data_dir,
                provider: provider.clone(),
                model: AiModel {
                    model_id: "models".to_string(),
                    display_name: "Models".to_string(),
                },
                system_prompt: String::new(),
                user_prompt: String::new(),
                purpose: "fetch_provider_models".to_string(),
                api_log_enabled,
            };
            let call_result = AiTextResult::success(&request, "", 0, 0, 0);
            let _ = stats::record_model_call(&request.app_data_dir, &request, &call_result);
            ModelListResult {
                ok: true,
                models,
                error_code: String::new(),
                error_message: String::new(),
            }
        }
        Err(error) => ModelListResult {
            ok: false,
            models: vec![],
            error_code: "request_failed".to_string(),
            error_message: error,
        },
    }
}

pub async fn generate_structured_note(request: StructuredNoteRequest) -> StructuredNoteResult {
    let system_prompt = structured_system_prompt(&request.industry);
    let result = chat(AiChatRequest {
        app_data_dir: request.app_data_dir,
        provider: request.provider,
        model: request.model,
        system_prompt,
        user_prompt: request.input,
        purpose: "home_structured_note".to_string(),
        api_log_enabled: request.api_log_enabled,
    })
    .await;
    if !result.ok {
        return StructuredNoteResult {
            ok: false,
            completed: vec![],
            issues: vec![],
            plans: vec![],
            raw_content: result.content,
            error_code: result.error_code,
            error_message: result.error_message,
            input_tokens: result.input_tokens,
            output_tokens: result.output_tokens,
            cached_tokens: result.cached_tokens,
        };
    }

    parse_structured_note(&result)
}

pub async fn merge_daily_note(request: DailyMergeRequest) -> AiTextResult {
    let system_prompt = daily_merge_system_prompt(&request.industry);
    chat(AiChatRequest {
        app_data_dir: request.app_data_dir.clone(),
        provider: request.provider.clone(),
        model: request.model.clone(),
        system_prompt,
        user_prompt: daily_merge_user_prompt(&request),
        purpose: "daily_note_merge".to_string(),
        api_log_enabled: request.api_log_enabled,
    })
    .await
}

pub async fn generate_weekly_report(request: ReportRequest) -> AiTextResult {
    let user_prompt = report_user_prompt(&request.period_label, &request.source_markdown);
    let system_prompt = with_industry_context(WEEKLY_REPORT_SYSTEM_PROMPT, &request.industry);
    chat(AiChatRequest {
        app_data_dir: request.app_data_dir,
        provider: request.provider,
        model: request.model,
        system_prompt,
        user_prompt,
        purpose: "weekly_report".to_string(),
        api_log_enabled: request.api_log_enabled,
    })
    .await
}

pub async fn generate_monthly_report(request: ReportRequest) -> AiTextResult {
    let user_prompt = report_user_prompt(&request.period_label, &request.source_markdown);
    let system_prompt = with_industry_context(MONTHLY_REPORT_SYSTEM_PROMPT, &request.industry);
    chat(AiChatRequest {
        app_data_dir: request.app_data_dir,
        provider: request.provider,
        model: request.model,
        system_prompt,
        user_prompt,
        purpose: "monthly_report".to_string(),
        api_log_enabled: request.api_log_enabled,
    })
    .await
}

pub async fn memory_chat(request: MemoryChatRequest) -> AiTextResult {
    let user_prompt = memory_chat_user_prompt(&request.question, &request.context_markdown);
    chat(AiChatRequest {
        app_data_dir: request.app_data_dir,
        provider: request.provider,
        model: request.model,
        system_prompt: MEMORY_CHAT_SYSTEM_PROMPT.to_string(),
        user_prompt,
        purpose: "memory_chat".to_string(),
        api_log_enabled: request.api_log_enabled,
    })
    .await
}

pub async fn memory_tool_chat(request: MemoryToolChatRequest) -> MemoryToolChatResult {
    let chat_request = AiChatRequest {
        app_data_dir: request.app_data_dir.clone(),
        provider: request.provider.clone(),
        model: request.model.clone(),
        system_prompt: MEMORY_TOOL_SYSTEM_PROMPT.to_string(),
        user_prompt: request
            .messages
            .iter()
            .map(|message| message.content.as_str())
            .collect::<Vec<_>>()
            .join("\n"),
        purpose: "memory_tool_chat".to_string(),
        api_log_enabled: request.api_log_enabled,
    };

    if request.provider.api_key.trim().is_empty() {
        return MemoryToolChatResult::error(
            &chat_request,
            "missing_api_key",
            "供应商 API Key 为空，已保留 mock 流程。",
            0,
            0,
            0,
        );
    }

    if request.provider.protocol != "openaiCompatible" {
        return MemoryToolChatResult::error(
            &chat_request,
            "unsupported_tool_protocol",
            "回忆书工具调用目前仅支持 OpenAI-compatible Chat Completions 或 Responses API。",
            0,
            0,
            0,
        );
    }

    let response = if ai_openai::is_responses_endpoint(&request.provider) {
        ai_openai::memory_tool_responses(&request, MEMORY_TOOL_SYSTEM_PROMPT).await
    } else {
        ai_openai::memory_tool_chat(&request, MEMORY_TOOL_SYSTEM_PROMPT).await
    };
    let result = match response {
        Ok(result) => result,
        Err(error) => MemoryToolChatResult::error(&chat_request, "request_failed", &error, 0, 0, 0),
    };

    let text_result = AiTextResult {
        ok: result.ok,
        content: result.content.clone(),
        error_code: result.error_code.clone(),
        error_message: result.error_message.clone(),
        input_tokens: result.input_tokens,
        output_tokens: result.output_tokens,
        cached_tokens: result.cached_tokens,
        provider_name: result.provider_name.clone(),
        model_id: result.model_id.clone(),
    };
    let _ = stats::record_model_call(&request.app_data_dir, &chat_request, &text_result);
    result
}

pub async fn memory_tool_chat_stream(
    request: MemoryToolChatRequest,
    sink: StreamSink<MemoryToolChatStreamEvent>,
) {
    let chat_request = AiChatRequest {
        app_data_dir: request.app_data_dir.clone(),
        provider: request.provider.clone(),
        model: request.model.clone(),
        system_prompt: MEMORY_TOOL_SYSTEM_PROMPT.to_string(),
        user_prompt: request
            .messages
            .iter()
            .map(|message| message.content.as_str())
            .collect::<Vec<_>>()
            .join("\n"),
        purpose: "memory_tool_chat_stream".to_string(),
        api_log_enabled: request.api_log_enabled,
    };

    if request.provider.protocol != "openaiCompatible" {
        let _ = sink.add(MemoryToolChatStreamEvent::error(
            "unsupported_tool_protocol",
            "回忆书流式工具调用目前仅支持 OpenAI-compatible Chat Completions 或 Responses API。",
        ));
        return;
    }

    let response = if ai_openai::is_responses_endpoint(&request.provider) {
        ai_openai::memory_tool_responses_stream(
            request.clone(),
            MEMORY_TOOL_SYSTEM_PROMPT,
            sink.clone(),
        )
        .await
    } else {
        ai_openai::memory_tool_chat_stream(request.clone(), MEMORY_TOOL_SYSTEM_PROMPT, sink.clone())
            .await
    };

    if let Err(error) = response {
        let _ = sink.add(MemoryToolChatStreamEvent::error("request_failed", &error));
        let result = AiTextResult::error(&chat_request, "request_failed", &error, 0, 0, 0);
        let _ = stats::record_model_call(&request.app_data_dir, &chat_request, &result);
    }
}

pub async fn fim_complete(request: FimCompleteRequest) -> AiTextResult {
    let chat_request = AiChatRequest {
        app_data_dir: request.app_data_dir.clone(),
        provider: request.provider.clone(),
        model: request.model.clone(),
        system_prompt: String::new(),
        user_prompt: request.prompt.clone(),
        purpose: "fim_edit_completion".to_string(),
        api_log_enabled: request.api_log_enabled,
    };

    if request.provider.api_key.trim().is_empty() {
        return AiTextResult::error(
            &chat_request,
            "missing_api_key",
            "供应商 API Key 为空，无法执行编辑补全。",
            0,
            0,
            0,
        );
    }

    if request.provider.protocol != "openaiCompatible" {
        return AiTextResult::error(
            &chat_request,
            "unsupported_fim_protocol",
            "编辑补全仅支持 OpenAI-compatible completions 协议。",
            0,
            0,
            0,
        );
    }

    let result = match ai_openai::fim_complete(&request).await {
        Ok(result) => result,
        Err(error) => AiTextResult::error(&chat_request, "request_failed", &error, 0, 0, 0),
    };

    let _ = stats::record_model_call(&request.app_data_dir, &chat_request, &result);
    result
}

pub fn estimate_tokens(text: &str) -> i32 {
    let chars = text.chars().count() as i32;
    (chars / 4).max(1)
}

pub fn extract_text(value: &Value, paths: &[&[&str]]) -> Option<String> {
    for path in paths {
        let mut current = value;
        for segment in *path {
            if let Ok(index) = segment.parse::<usize>() {
                current = current.as_array()?.get(index)?;
            } else {
                current = current.get(*segment)?;
            }
        }
        if let Some(text) = current.as_str() {
            return Some(text.to_string());
        }
    }
    None
}

pub fn usage_from_value(value: &Value) -> (i32, i32, i32) {
    let input = read_i32(value, &["usage", "prompt_tokens"])
        .or_else(|| read_i32(value, &["usageMetadata", "promptTokenCount"]))
        .or_else(|| read_i32(value, &["usage", "input_tokens"]))
        .unwrap_or(0);
    let output = read_i32(value, &["usage", "completion_tokens"])
        .or_else(|| read_i32(value, &["usageMetadata", "candidatesTokenCount"]))
        .or_else(|| read_i32(value, &["usage", "output_tokens"]))
        .unwrap_or(0);
    let cached = read_i32(value, &["usage", "prompt_tokens_details", "cached_tokens"]).unwrap_or(0);
    (input, output, cached)
}

fn read_i32(value: &Value, path: &[&str]) -> Option<i32> {
    let mut current = value;
    for segment in path {
        current = current.get(*segment)?;
    }
    current.as_i64().map(|value| value as i32)
}

fn daily_merge_user_prompt(request: &DailyMergeRequest) -> String {
    format!(
        "日期：{}\n\n已有日报 Markdown：\n{}\n\n新增随手记录：\n{}\n\n新增结构化内容：\n完成事项：\n{}\n\n问题记录：\n{}\n\n明日计划：\n{}",
        request.date,
        if request.existing_markdown.trim().is_empty() {
            "（空）"
        } else {
            request.existing_markdown.trim()
        },
        request.raw_input.trim(),
        format_items(&request.completed),
        format_items(&request.issues),
        format_items(&request.plans),
    )
}

fn format_items(items: &[String]) -> String {
    if items.is_empty() {
        return "- 暂无".to_string();
    }
    items
        .iter()
        .map(|item| format!("- {item}"))
        .collect::<Vec<_>>()
        .join("\n")
}

fn report_user_prompt(period_label: &str, source_markdown: &str) -> String {
    format!(
        "周期：{}\n\n原始 Markdown 内容：\n{}",
        period_label.trim(),
        source_markdown.trim()
    )
}

fn memory_chat_user_prompt(_question: &str, context_markdown: &str) -> String {
    format!(
        "请根据下面的完整上下文回答最后一条 User 消息。上下文按时间顺序组织，后续请求会只在末尾追加新消息以利于供应商 KV/cache 命中。\n\n上下文材料：\n{}",
        context_markdown.trim()
    )
}

fn parse_structured_note(result: &AiTextResult) -> StructuredNoteResult {
    let parsed = serde_json::from_str::<Value>(&strip_markdown_fence(&result.content));
    let Ok(value) = parsed else {
        return StructuredNoteResult {
            ok: false,
            completed: vec![],
            issues: vec![],
            plans: vec![],
            raw_content: result.content.clone(),
            error_code: "invalid_structured_output".to_string(),
            error_message: "AI 返回内容不是可解析的结构化 JSON。".to_string(),
            input_tokens: result.input_tokens,
            output_tokens: result.output_tokens,
            cached_tokens: result.cached_tokens,
        };
    };

    StructuredNoteResult {
        ok: true,
        completed: read_string_array(&value, "completed"),
        issues: read_string_array(&value, "issues"),
        plans: read_string_array(&value, "plans"),
        raw_content: result.content.clone(),
        error_code: String::new(),
        error_message: String::new(),
        input_tokens: result.input_tokens,
        output_tokens: result.output_tokens,
        cached_tokens: result.cached_tokens,
    }
}

fn read_string_array(value: &Value, key: &str) -> Vec<String> {
    value
        .get(key)
        .and_then(Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(Value::as_str)
                .map(str::trim)
                .filter(|item| !item.is_empty())
                .map(ToString::to_string)
                .collect()
        })
        .unwrap_or_default()
}

fn strip_markdown_fence(content: &str) -> String {
    let trimmed = content.trim();
    if !trimmed.starts_with("```") {
        return trimmed.to_string();
    }
    trimmed
        .lines()
        .skip(1)
        .take_while(|line| !line.trim_start().starts_with("```"))
        .collect::<Vec<_>>()
        .join("\n")
}

impl AiTextResult {
    pub fn success(
        request: &AiChatRequest,
        content: impl Into<String>,
        input_tokens: i32,
        output_tokens: i32,
        cached_tokens: i32,
    ) -> Self {
        Self {
            ok: true,
            content: content.into(),
            error_code: String::new(),
            error_message: String::new(),
            input_tokens,
            output_tokens,
            cached_tokens,
            provider_name: request.provider.name.clone(),
            model_id: request.model.model_id.clone(),
        }
    }

    pub fn error(
        request: &AiChatRequest,
        code: impl Into<String>,
        message: impl Into<String>,
        input_tokens: i32,
        output_tokens: i32,
        cached_tokens: i32,
    ) -> Self {
        Self {
            ok: false,
            content: String::new(),
            error_code: code.into(),
            error_message: message.into(),
            input_tokens,
            output_tokens,
            cached_tokens,
            provider_name: request.provider.name.clone(),
            model_id: request.model.model_id.clone(),
        }
    }
}

impl MemoryToolChatResult {
    pub fn success(
        request: &MemoryToolChatRequest,
        content: impl Into<String>,
        reasoning_content: impl Into<String>,
        tool_calls: Vec<AiToolCall>,
        input_tokens: i32,
        output_tokens: i32,
        cached_tokens: i32,
    ) -> Self {
        Self {
            ok: true,
            content: content.into(),
            reasoning_content: reasoning_content.into(),
            tool_calls,
            error_code: String::new(),
            error_message: String::new(),
            input_tokens,
            output_tokens,
            cached_tokens,
            provider_name: request.provider.name.clone(),
            model_id: request.model.model_id.clone(),
        }
    }

    pub fn error(
        request: &AiChatRequest,
        code: impl Into<String>,
        message: impl Into<String>,
        input_tokens: i32,
        output_tokens: i32,
        cached_tokens: i32,
    ) -> Self {
        Self {
            ok: false,
            content: String::new(),
            reasoning_content: String::new(),
            tool_calls: vec![],
            error_code: code.into(),
            error_message: message.into(),
            input_tokens,
            output_tokens,
            cached_tokens,
            provider_name: request.provider.name.clone(),
            model_id: request.model.model_id.clone(),
        }
    }
}

impl MemoryToolChatStreamEvent {
    pub fn error(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            event_type: "error".to_string(),
            content_delta: String::new(),
            reasoning_delta: String::new(),
            content: String::new(),
            reasoning_content: String::new(),
            tool_calls: vec![],
            error_code: code.into(),
            error_message: message.into(),
            input_tokens: 0,
            output_tokens: 0,
            cached_tokens: 0,
        }
    }
}

const STRUCTURED_SYSTEM_PROMPT: &str = r#"你是 SpringNote 的日报结构化助手。请把用户的中文工作记录整理成 JSON，不要输出 Markdown，不要解释。
JSON 格式必须是：
{"completed":["完成事项"],"issues":["问题记录"],"plans":["明日计划"]}
如果某一类没有内容，返回空数组。"#;

fn structured_system_prompt(industry: &str) -> String {
    with_industry_context(STRUCTURED_SYSTEM_PROMPT, industry)
}

const DAILY_MERGE_SYSTEM_PROMPT: &str = r#"你是 SpringNote 的日报整理助手。请把已有日报 Markdown 和新增记录合并成一篇自然、清晰、可继续编辑的日报。
写作原则：
1. 保留事实，不编造进展、时间、结论或情绪。
2. 去掉重复表达，把零散记录整理成顺口的人类工作记录。
3. Markdown 要美观清爽，可以自由使用标题、短段落、列表、引用等结构，不要拘泥于“完成事项 / 问题记录 / 明日计划”三段式。
4. 如果内容很少，就保持简短；如果内容较多，可以自然分组并突出重点、卡点和下一步。
5. 语气像认真写给自己或团队看的日报，不要像模板填空，也不要过度正式。
6. 只输出最终 Markdown，不要解释。"#;

fn daily_merge_system_prompt(industry: &str) -> String {
    with_industry_context(DAILY_MERGE_SYSTEM_PROMPT, industry)
}

fn with_industry_context(base_prompt: &str, industry: &str) -> String {
    let industry = industry.trim();
    if industry.is_empty() {
        return base_prompt.to_string();
    }

    format!(
        "{base_prompt}\n用户偏好：用户所在行业是「{industry}」。请结合该行业的常见工作语境理解术语、任务和表达，但不要脱离输入内容编造事实。"
    )
}

const WEEKLY_REPORT_SYSTEM_PROMPT: &str = r#"你是 SpringNote 的周报整理助手。请基于一周日报 Markdown 生成一篇自然、有重点、可直接编辑的周报。
写作原则：
1. 保留来源中的事实，不编造没有依据的成果、风险或计划。
2. 不需要固定套用“主要工作 / 关键进展 / 问题 / 下周计划”等模板，可以根据材料自由组织结构。
3. Markdown 要层次清楚、阅读舒服；可以使用标题、段落、列表、重点小结，但避免机械堆栏目。
4. 优先呈现这一周真正发生了什么、推进到了哪里、遇到什么卡点、接下来怎么走。
5. 语气自然，像一个认真复盘工作的人的周报，不要像 AI 模板。
6. 只输出最终 Markdown，不要解释。"#;

const MONTHLY_REPORT_SYSTEM_PROMPT: &str = r#"你是 SpringNote 的月报整理助手。请基于月度周报 Markdown 生成一篇自然、有复盘感、可继续编辑的月报。
写作原则：
1. 保留来源中的事实，不编造成果、数据、评价或计划。
2. 不需要固定套用“核心成果 / 项目进展 / 问题复盘 / 个人成长 / 下月计划”等模板，可以根据材料自由组织结构。
3. Markdown 要美观、有呼吸感；可以使用标题、短段落、列表、总结和展望，但不要写成僵硬表格。
4. 重点体现这个月的主线、阶段性变化、值得保留的经验、还没解决的问题和自然的下一步。
5. 语气克制、真诚、有人的表达，不要过度包装，也不要像 AI 汇报模板。
6. 只输出最终 Markdown，不要解释。"#;

const MEMORY_CHAT_SYSTEM_PROMPT: &str = r#"你是 SpringNote 的回忆书问答助手。请只基于提供的上下文材料回答用户问题。
上下文可能包含完整对话历史、历史 Markdown、ReAct 工具执行轨迹和工具观察结果。
回答连续追问时，要结合完整对话历史理解省略指代，例如“什么时候”“这个配置”“刚才说的”等。
如果材料不足，请明确说明缺少依据。不要编造事实。"#;

const MEMORY_TOOL_SYSTEM_PROMPT: &str = r#"你是 SpringNote 的回忆书问答助手。你必须基于用户的历史日报、周报、月报回答问题。
你可以自主调用工具检索或读取记录；需要信息时先调用工具，不要让应用预先替你检索。
连续追问时结合完整消息历史理解省略指代，例如“什么时候”“这个配置”“刚才说的”等。
回答必须只依据工具返回和对话上下文；材料不足时明确说明缺少依据，不要编造事实。
最终回答使用自然中文和清晰 Markdown，不要输出工具调用 JSON。"#;

#[cfg(test)]
mod tests {
    use super::*;

    fn request() -> AiChatRequest {
        AiChatRequest {
            app_data_dir: ".".to_string(),
            provider: AiProvider {
                id: "openai".to_string(),
                name: "OpenAI".to_string(),
                protocol: "openaiCompatible".to_string(),
                api_key: "key".to_string(),
                base_url: "https://api.example.com/v1".to_string(),
                api_path: "/chat/completions".to_string(),
            },
            model: AiModel {
                model_id: "gpt-test".to_string(),
                display_name: "GPT Test".to_string(),
            },
            system_prompt: String::new(),
            user_prompt: String::new(),
            purpose: "test".to_string(),
            api_log_enabled: false,
        }
    }

    #[test]
    fn parses_structured_note_json() {
        let result = AiTextResult::success(
            &request(),
            r#"{"completed":["A"],"issues":["B"],"plans":["C"]}"#,
            1,
            2,
            0,
        );
        let parsed = parse_structured_note(&result);
        assert!(parsed.ok);
        assert_eq!(parsed.completed, vec!["A"]);
        assert_eq!(parsed.issues, vec!["B"]);
        assert_eq!(parsed.plans, vec!["C"]);
    }

    #[test]
    fn strips_markdown_json_fence() {
        let stripped = strip_markdown_fence("```json\n{\"completed\":[]}\n```");
        assert_eq!(stripped, "{\"completed\":[]}");
    }

    #[test]
    fn builds_daily_merge_prompt_in_rust() {
        let prompt = daily_merge_user_prompt(&DailyMergeRequest {
            app_data_dir: ".".to_string(),
            provider: request().provider,
            model: request().model,
            existing_markdown: "# old".to_string(),
            raw_input: "done".to_string(),
            completed: vec!["A".to_string()],
            issues: vec![],
            plans: vec!["B".to_string()],
            date: "2026-06-18".to_string(),
            industry: String::new(),
            api_log_enabled: false,
        });

        assert!(prompt.contains("日期：2026-06-18"));
        assert!(prompt.contains("- A"));
        assert!(prompt.contains("- 暂无"));
        assert!(prompt.contains("- B"));
    }

    #[test]
    fn builds_memory_chat_prompt_with_context() {
        let prompt = memory_chat_user_prompt(
            "什么时候删除 nacos 配置？",
            "## 当前对话历史\nUser: nacos 是在哪天配置的\n\n## ReAct 工具执行轨迹\nThought: search\nAct: keyword_search(keywords=[nacos])\nObservation: hit",
        );

        assert!(prompt.starts_with("请根据下面的完整上下文回答最后一条 User 消息"));
        assert!(prompt.contains("当前对话历史"));
        assert!(prompt.contains("ReAct 工具执行轨迹"));
        assert!(prompt.contains("keyword_search"));
    }
}
