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

        // projection_snapshots are wallet-scoped and already capped on save: we keep only
        // MAX_SNAPSHOTS (5) per wallet and prune when saving a new one (cleanup_old_snapshots).
        // No daily cleanup job needed for snapshots. Placeholder for any future global maintenance.
        scheduler
            .add(
                Job::new_async("0 0 2 * * *", |_uuid, _l| {
                    Box::pin(async move {
                        info!("Daily maintenance job (no-op; projection_snapshots are pruned per-wallet on save)");
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
