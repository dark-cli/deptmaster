use std::time::{Duration, Instant};
use flutter_rust_bridge::frb;

#[frb(ignore)]
pub(crate) struct Backoff {
    schedule: Vec<Duration>,
    index: usize,
    next_allowed_at: Option<Instant>,
}

impl Backoff {
    pub(crate) fn new(schedule: Vec<Duration>) -> Self {
        Self {
            schedule,
            index: 0,
            next_allowed_at: None,
        }
    }

    pub(crate) fn can_attempt(&self) -> bool {
        match self.next_allowed_at {
            Some(at) => Instant::now() >= at,
            None => true,
        }
    }

    pub(crate) fn on_failure(&mut self) -> Duration {
        let delay = self
            .schedule
            .get(self.index)
            .cloned()
            .unwrap_or_else(|| Duration::from_secs(1));
        self.next_allowed_at = Some(Instant::now() + delay);
        if self.index + 1 < self.schedule.len() {
            self.index += 1;
        }
        delay
    }

    pub(crate) fn reset(&mut self) {
        self.index = 0;
        self.next_allowed_at = None;
    }

    pub(crate) fn remaining(&self) -> Option<Duration> {
        self.next_allowed_at
            .and_then(|at| at.checked_duration_since(Instant::now()))
    }
}
