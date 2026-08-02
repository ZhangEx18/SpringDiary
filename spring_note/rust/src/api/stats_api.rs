use crate::stats::{
    self, DailyActivity, DailyTokenUsage, MoodEntry, ProviderTokenUsage, StatsSnapshot,
    StatsSummary,
};

pub fn record_app_startup(app_data_dir: String) -> bool {
    stats::record_app_startup(&app_data_dir).is_ok()
}

pub fn record_home_generation(app_data_dir: String) -> bool {
    stats::record_home_generation(&app_data_dir).is_ok()
}

pub fn record_work_time(app_data_dir: String, work_seconds: i32, coins: f64) -> bool {
    stats::record_work_time(&app_data_dir, work_seconds, coins).is_ok()
}

pub fn record_diary_entry(app_data_dir: String, date: String, mood: String) -> bool {
    stats::record_diary_entry(&app_data_dir, &date, &mood).is_ok()
}

pub fn get_mood_distribution(
    app_data_dir: String,
    start_date: String,
    end_date: String,
) -> Vec<MoodEntry> {
    stats::get_mood_distribution(&app_data_dir, &start_date, &end_date)
        .unwrap_or_default()
}

pub fn get_stats_snapshot(
    app_data_dir: String,
    daily_notes_dir: String,
    weekly_notes_dir: String,
    monthly_notes_dir: String,
    diary_notes_dir: String,
    start_date: String,
    end_date: String,
) -> StatsSnapshot {
    stats::get_stats_snapshot(
        &app_data_dir,
        &daily_notes_dir,
        &weekly_notes_dir,
        &monthly_notes_dir,
        &diary_notes_dir,
        &start_date,
        &end_date,
    )
    .unwrap_or_else(|_| empty_snapshot())
}

fn empty_snapshot() -> StatsSnapshot {
    StatsSnapshot {
        summary: StatsSummary {
            summaries: 0,
            fim_completions: 0,
            total_records: 0,
            daily_notes: 0,
            weekly_notes: 0,
            monthly_notes: 0,
            diary_notes: 0,
            input_tokens: 0,
            output_tokens: 0,
            cached_tokens: 0,
            app_launches: 0,
            work_seconds: 0,
            coins: 0.0,
        },
        activity: Vec::<DailyActivity>::new(),
        token_usage: Vec::<DailyTokenUsage>::new(),
        provider_usage: Vec::<ProviderTokenUsage>::new(),
    }
}
