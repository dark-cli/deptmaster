use tokio_cron_scheduler::{Job, JobScheduler};
use tracing::info;
use std::sync::Arc;
use crate::database::DatabasePool;
use crate::config::Config;

pub struct BackgroundScheduler {
    #[allow(dead_code)]
    scheduler: Arc<JobScheduler>,
    #[allow(dead_code)]
    db_pool: DatabasePool,
    #[allow(dead_code)]
    config: Arc<Config>,
}

impl BackgroundScheduler {
    pub async fn new(
        db_pool: DatabasePool,
        config: Arc<Config>,
    ) -> anyhow::Result<Self> {
        let scheduler = JobScheduler::new().await?;

        // Example: Daily cleanup at 2 AM (e.g. old projection_snapshots, expired data).
        // Not related to app login/logout; app-side logout is in Flutter/Rust client (token + config clear).
        scheduler
            .add(
                Job::new_async("0 0 2 * * *", |_uuid, _l| {
                    Box::pin(async move {
                        info!("Running daily cleanup job");
                        // Optional: prune old projection_snapshots, etc. Leave no-op for now.
                    })
                })?
            )
            .await?;

        scheduler.start().await?;
        info!("Background scheduler started");

        Ok(Self {
            scheduler: Arc::new(scheduler),
            db_pool,
            config,
        })
    }

    pub async fn shutdown(&self) {
        // JobScheduler doesn't have a shutdown method in this version
        // It will shutdown when dropped
        info!("Background scheduler stopped");
    }
}
