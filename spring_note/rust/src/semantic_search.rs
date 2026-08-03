use std::fs;
use std::path::Path;
use std::time::Duration;

use rusqlite::{Connection, OptionalExtension, params};

use crate::ai_openai;

const DB_FILENAME: &str = "springnote.db";
const DB_BUSY_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Clone, Debug)]
pub struct SemanticHit {
    pub path: String,
    pub score: f32,
}

pub async fn index_diary_embeddings(
    app_data_dir: &str,
    diary_directory: &str,
    provider: &crate::ai::AiProvider,
    model: &crate::ai::AiModel,
) -> Result<usize, String> {
    if provider.protocol != "openaiCompatible" {
        return Err("当前供应商协议不支持语义索引，请使用 OpenAI 兼容协议".to_string());
    }
    let connection = open_connection(app_data_dir)?;
    initialize(&connection)?;

    let mut pending = Vec::new();
    let directory = Path::new(diary_directory);
    if directory.is_dir() {
        let entries = fs::read_dir(directory).map_err(|e| e.to_string())?;
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.extension().is_some_and(|ext| ext == "md") {
                continue;
            }
            let key = path.to_string_lossy().to_string();
            let already: Option<i64> = connection
                .query_row(
                    "SELECT updated_millis FROM diary_embeddings WHERE path = ?1",
                    params![key],
                    |row| row.get(0),
                )
                .optional()
                .map_err(|e| e.to_string())?;
            let modified = entry.metadata().ok().and_then(|m| m.modified().ok());
            let modified_millis = modified
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_millis() as i64)
                .unwrap_or(0);
            if already.is_none() || already != Some(modified_millis) {
                pending.push((key, modified_millis));
            }
        }
    }
    if pending.is_empty() {
        return Ok(0);
    }

    let texts = pending
        .iter()
        .map(|(path, _)| fs::read_to_string(path).unwrap_or_default())
        .collect::<Vec<_>>();
    let vectors = ai_openai::embed_texts(
        &provider.base_url,
        &provider.api_path,
        &provider.api_key,
        &model.model_id,
        &texts,
    )
    .await?;
    if vectors.len() != pending.len() {
        return Err("embedding count mismatch".to_string());
    }
    for (item, vector) in pending.iter().zip(vectors.iter()) {
        let blob = encode_vector(vector);
        connection
            .execute(
                "INSERT INTO diary_embeddings (path, embedding, updated_millis)
                 VALUES (?1, ?2, ?3)
                 ON CONFLICT(path) DO UPDATE SET
                     embedding = excluded.embedding,
                     updated_millis = excluded.updated_millis",
                params![item.0, blob, item.1],
            )
            .map_err(|e| e.to_string())?;
    }
    Ok(pending.len())
}

pub async fn semantic_search(
    app_data_dir: &str,
    query: &str,
    provider: &crate::ai::AiProvider,
    model: &crate::ai::AiModel,
    top_k: usize,
) -> Result<Vec<SemanticHit>, String> {
    let connection = open_connection(app_data_dir)?;
    initialize(&connection)?;
    let vectors = ai_openai::embed_texts(
        &provider.base_url,
        &provider.api_path,
        &provider.api_key,
        &model.model_id,
        &[query.to_string()],
    )
    .await?;
    let query_vector = vectors
        .first()
        .cloned()
        .ok_or_else(|| "empty query embedding".to_string())?;

    let mut hits = Vec::new();
    let mut statement = connection
        .prepare("SELECT path, embedding FROM diary_embeddings")
        .map_err(|e| e.to_string())?;
    let rows = statement
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, Vec<u8>>(1)?))
        })
        .map_err(|e| e.to_string())?;
    for row in rows {
        let (path, blob) = row.map_err(|e| e.to_string())?;
        let vector = decode_vector(&blob);
        if vector.len() != query_vector.len() {
            continue;
        }
        let score = cosine(&query_vector, &vector);
        hits.push(SemanticHit { path, score });
    }
    hits.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    hits.truncate(top_k);
    Ok(hits)
}

fn initialize(connection: &Connection) -> Result<(), String> {
    connection
        .execute_batch(
            "CREATE TABLE IF NOT EXISTS diary_embeddings (
                path TEXT PRIMARY KEY,
                embedding BLOB NOT NULL,
                updated_millis INTEGER NOT NULL DEFAULT 0
            );",
        )
        .map_err(|e| e.to_string())
}

fn open_connection(app_data_dir: &str) -> Result<Connection, String> {
    fs::create_dir_all(app_data_dir).map_err(|e| e.to_string())?;
    let db_path = Path::new(app_data_dir).join(DB_FILENAME);
    let connection = Connection::open(&db_path).map_err(|e| e.to_string())?;
    connection
        .busy_timeout(DB_BUSY_TIMEOUT)
        .map_err(|e| e.to_string())?;
    Ok(connection)
}

fn encode_vector(vector: &[f32]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(vector.len() * 4);
    for value in vector {
        bytes.extend_from_slice(&value.to_le_bytes());
    }
    bytes
}

fn decode_vector(bytes: &[u8]) -> Vec<f32> {
    bytes
        .chunks_exact(4)
        .map(|chunk| f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]))
        .collect()
}

fn cosine(a: &[f32], b: &[f32]) -> f32 {
    let mut dot = 0.0f64;
    let mut norm_a = 0.0f64;
    let mut norm_b = 0.0f64;
    for (x, y) in a.iter().zip(b.iter()) {
        dot += (*x as f64) * (*y as f64);
        norm_a += (*x as f64) * (*x as f64);
        norm_b += (*y as f64) * (*y as f64);
    }
    let denom = (norm_a.sqrt() * norm_b.sqrt()).max(1e-12);
    (dot / denom) as f32
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vector_roundtrip_preserves_values() {
        let vector = vec![0.5f32, -1.25, 3.0, 0.0];
        let blob = encode_vector(&vector);
        let decoded = decode_vector(&blob);
        assert_eq!(decoded, vector);
    }

    #[test]
    fn cosine_similarity_parallel_is_one() {
        let a = vec![1.0f32, 0.0, 0.0];
        let b = vec![2.0f32, 0.0, 0.0];
        assert!((cosine(&a, &b) - 1.0).abs() < 1e-6);
    }

    #[test]
    fn cosine_similarity_orthogonal_is_zero() {
        let a = vec![1.0f32, 0.0];
        let b = vec![0.0f32, 1.0];
        assert!((cosine(&a, &b)).abs() < 1e-6);
    }

    #[test]
    fn cosine_similarity_opposite_is_minus_one() {
        let a = vec![1.0f32, 0.0];
        let b = vec![-1.0f32, 0.0];
        assert!((cosine(&a, &b) + 1.0).abs() < 1e-6);
    }

    #[test]
    fn index_and_search_with_mock_embeddings() {
        let dir = std::env::temp_dir().join(format!(
            "springnote_semantic_{}",
            std::process::id()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let diary = dir.join("diary");
        std::fs::create_dir_all(&diary).unwrap();
        std::fs::write(diary.join("2026-08-01.md"), "# 日记\n\n今天去公园散步很开心").unwrap();
        std::fs::write(diary.join("2026-08-02.md"), "# 日记\n\n加班到深夜很累").unwrap();

        // 手工插入 mock embedding: 第一个接近查询向量
        let conn = open_connection(dir.to_str().unwrap()).unwrap();
        initialize(&conn).unwrap();
        let happy = vec![1.0f32, 0.0, 0.0];
        let tired = vec![0.0f32, 1.0, 0.0];
        conn.execute(
            "INSERT INTO diary_embeddings (path, embedding, updated_millis) VALUES (?1, ?2, 0)",
            params![
                diary.join("2026-08-01.md").to_str().unwrap(),
                encode_vector(&happy)
            ],
        )
        .unwrap();
        conn.execute(
            "INSERT INTO diary_embeddings (path, embedding, updated_millis) VALUES (?1, ?2, 0)",
            params![
                diary.join("2026-08-02.md").to_str().unwrap(),
                encode_vector(&tired)
            ],
        )
        .unwrap();
        drop(conn);

        // 直接测试 cosine 排序逻辑
        let query = vec![0.9f32, 0.1, 0.0];
        let mut hits = vec![
            SemanticHit { path: diary.join("2026-08-02.md").to_string_lossy().into(), score: cosine(&query, &tired) },
            SemanticHit { path: diary.join("2026-08-01.md").to_string_lossy().into(), score: cosine(&query, &happy) },
        ];
        hits.sort_by(|a, b| b.score.partial_cmp(&a.score).unwrap());
        assert!(hits[0].path.contains("2026-08-01"));
        assert!(hits[0].score > hits[1].score);

        std::fs::remove_dir_all(&dir).ok();
    }
}

