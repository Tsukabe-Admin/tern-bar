//! How fast copied content may enter the history. Without a limit, an app
//! that sets the clipboard in a loop (a web page can, while it has the focus)
//! would push every older entry out within a second. Copying by hand never
//! reaches the limit.

use std::time::{Duration, Instant};

/// New entries allowed in one burst.
const BURST: u32 = 30;

/// How long until one more is allowed.
const EVERY: Duration = Duration::from_secs(2);

/// How many entries may still be kept: BURST at most, one more every EVERY.
pub struct Allowance {
    left: u32,
    /// When `left` last grew, or was last full.
    since: Instant,
}

impl Allowance {
    pub fn new(now: Instant) -> Allowance {
        Allowance {
            left: BURST,
            since: now,
        }
    }

    /// Whether an entry may be kept at `now`.
    pub fn any(&mut self, now: Instant) -> bool {
        self.earn(now);
        self.left > 0
    }

    /// An entry was kept at `now`.
    pub fn spend(&mut self, now: Instant) {
        self.earn(now);
        self.left = self.left.saturating_sub(1);
    }

    fn earn(&mut self, now: Instant) {
        if self.left < BURST {
            let periods = now.saturating_duration_since(self.since).as_millis() / EVERY.as_millis();
            let earned = u32::try_from(periods)
                .unwrap_or(u32::MAX)
                .min(BURST - self.left);
            self.left += earned;
            // The part of a period already waited still counts.
            self.since += EVERY * earned;
        }
        if self.left == BURST {
            // Time spent full earns nothing.
            self.since = now;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_burst_then_one_more_every_period() {
        let start = Instant::now();
        let mut allowance = Allowance::new(start);
        for _ in 0..BURST {
            assert!(allowance.any(start));
            allowance.spend(start);
        }
        assert!(!allowance.any(start));
        assert!(!allowance.any(start + EVERY - Duration::from_millis(1)));
        assert!(allowance.any(start + EVERY));
        allowance.spend(start + EVERY);
        assert!(!allowance.any(start + EVERY));
        // Two and a half periods later: two more, and the half is not lost.
        let later = start + EVERY * 3 + EVERY / 2;
        allowance.spend(later);
        allowance.spend(later);
        assert!(!allowance.any(later));
        assert!(allowance.any(later + EVERY / 2));
    }

    #[test]
    fn a_long_quiet_time_allows_one_burst_and_no_more() {
        let start = Instant::now();
        let mut allowance = Allowance::new(start);
        allowance.spend(start);
        let later = start + Duration::from_secs(24 * 3600);
        for _ in 0..BURST {
            assert!(allowance.any(later));
            allowance.spend(later);
        }
        assert!(!allowance.any(later));
        assert!(!allowance.any(later + EVERY - Duration::from_millis(1)));
    }
}
