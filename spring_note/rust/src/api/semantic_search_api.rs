use crate::ai::{AiModel, AiProvider};
use crate::semantic_search::{self, SemanticHit};

pub async fn index_diary_embeddings(
    app_data_dir: String,
    diary_directory: String,
    provider: AiProvider,
    model: AiModel,
) -> usize {
    semantic_search::index_diary_embeddings(&app_data_dir, &diary_directory, &provider, &model)
        .await
        .unwrap_or(0)
}

pub async fn semantic_search_diary(
    app_data_dir: String,
    query: String,
    provider: AiProvider,
    model: AiModel,
    top_k: i32,
) -> Vec<SemanticHit> {
    semantic_search::semantic_search(
        &app_data_dir,
        &query,
        &provider,
        &model,
        top_k.clamp(1, 50) as usize,
    )
    .await
    .unwrap_or_default()
}
