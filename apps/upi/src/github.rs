//! The unauthenticated GitHub API quota (60 requests an hour per address).
//! Gear Lever, bun and fisher spend it; reading it is free.

use crate::sys;

/// `/rate_limit`: requests left and when the quota resets (unix time).
pub fn parse_rate_limit(json: &serde_json::Value) -> Option<(u64, i64)> {
    let core = &json["resources"]["core"];
    Some((core["remaining"].as_u64()?, core["reset"].as_i64()?))
}

/// Ok when `needed` requests are left, or when the quota cannot be read (the
/// step then reports its own errors). Err says when the quota resets.
pub fn enough(needed: u64) -> Result<(), String> {
    let Some((left, reset)) = sys::get_json("https://api.github.com/rate_limit")
        .ok()
        .and_then(|j| parse_rate_limit(&j))
    else {
        return Ok(());
    };
    if left >= needed {
        return Ok(());
    }
    let minutes = (reset - sys::now() + 59) / 60;
    Err(format!(
        "GitHub API limit: {left} left, {needed} needed; resets at {} (in {minutes} min)",
        sys::local_time(reset, "%H:%M")
    ))
}

/// What GitHub tools print once the quota is spent.
pub fn hit_limit(output: &str) -> bool {
    output.contains("rate limit exceeded") || output.contains("HTTPForbidden")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_quota() {
        let j = serde_json::json!({"resources": {"core": {"remaining": 12, "reset": 1790000000}}});
        assert_eq!(parse_rate_limit(&j), Some((12, 1790000000)));
        assert_eq!(parse_rate_limit(&serde_json::json!({})), None);
        assert!(hit_limit("API rate limit exceeded for 1.2.3.4"));
        assert!(!hit_limit("all good"));
    }
}
