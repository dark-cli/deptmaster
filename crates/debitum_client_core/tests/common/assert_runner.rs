//! Run assertion "commands" against get_contacts / get_events / get_transactions output.
//! Same style as run_commands: e.g. "contacts count 1", "contact name \"Alice\"", "events count >= 12".
//! Empty lines and # comments are skipped.
//!
//! Full vocabulary: see project docs at `docs/INTEGRATION_TEST_COMMANDS.md`.

fn parse_args(input: &str) -> Vec<String> {
    let mut args = Vec::new();
    let mut buf = String::new();
    let mut in_quotes = false;
    for c in input.chars() {
        if c == '"' {
            in_quotes = !in_quotes;
        } else if c == ' ' && !in_quotes {
            if !buf.is_empty() {
                args.push(std::mem::take(&mut buf));
            }
        } else {
            buf.push(c);
        }
    }
    if !buf.is_empty() {
        args.push(buf);
    }
    args
}

fn unquote(s: &str) -> String {
    let s = s.trim();
    if s.len() >= 2 && s.starts_with('"') && s.ends_with('"') {
        s[1..s.len() - 1].to_string()
    } else {
        s.to_string()
    }
}

/// Run a list of assertion commands. Returns Err on first failure.
/// Commands:
///   contacts count <n> | contacts count >= <n> | contacts count > <n>
///   contact name "<name>"         — some contact has this name
///   contact 0 name "<name>"      — first contact has this name
///   contact name "<name>" removed — no contact has this name
///   events count <n> | events count >= <n>
///   events event_type <CREATED|UPDATED|DELETED> count >= <n>
///   events aggregate_type contact event_type <CREATED|UPDATED|DELETED> count <n>
///   transactions count > <n> | transactions count >= <n>
pub fn assert_commands(
    contacts_json: &str,
    events_json: &str,
    transactions_json: &str,
    commands: &[&str],
) -> Result<(), String> {
    let contacts: Vec<serde_json::Value> =
        serde_json::from_str(contacts_json).map_err(|e| e.to_string())?;
    let events: Vec<serde_json::Value> =
        serde_json::from_str(events_json).map_err(|e| e.to_string())?;
    let transactions: Vec<serde_json::Value> =
        serde_json::from_str(transactions_json).map_err(|e| e.to_string())?;

    for cmd in commands {
        let cmd = cmd.trim();
        if cmd.is_empty() || cmd.starts_with('#') {
            continue;
        }
        run_one(
            cmd,
            &contacts,
            &events,
            &transactions,
        )?;
    }
    Ok(())
}

fn run_one(
    command: &str,
    contacts: &[serde_json::Value],
    events: &[serde_json::Value],
    transactions: &[serde_json::Value],
) -> Result<(), String> {
    let args = parse_args(command);
    if args.is_empty() {
        return Err("Empty assert command".to_string());
    }
    let action = args[0].to_lowercase();
    let args: Vec<&str> = args.iter().map(String::as_str).collect();

    // contacts count <n> | contacts count >= <n> | contacts count > <n>
    if action == "contacts" {
        if args.len() >= 3 && args[1].to_lowercase() == "count" {
            let op = args.get(2);
            let n: usize = args
                .get(3)
                .or_else(|| op)
                .and_then(|s| s.parse().ok())
                .ok_or_else(|| format!("contacts count: need number, got {:?}", args))?;
            if args.len() >= 4 && args[2] == ">=" {
                if contacts.len() < n {
                    return Err(format!("contacts count >= {}; got {}", n, contacts.len()));
                }
            } else if args.len() >= 4 && args[2] == ">" {
                if contacts.len() <= n {
                    return Err(format!("contacts count > {}; got {}", n, contacts.len()));
                }
            } else {
                if contacts.len() != n {
                    return Err(format!("contacts count {}; got {}", n, contacts.len()));
                }
            }
            return Ok(());
        }
    }

    // contact name "<name>" | contact 0 name "<name>" | contact name "<name>" removed
    if action == "contact" {
        if args.len() >= 3 && args[1].to_lowercase() == "name" {
            let name = unquote(args[2]);
            let removed = args.get(3).map(|s| s.to_lowercase() == "removed").unwrap_or(false);
            let found = contacts.iter().any(|c| c["name"].as_str() == Some(name.as_str()));
            if removed {
                if found {
                    return Err(format!("contact name \"{}\" should be removed; got {:?}", name, contacts));
                }
            } else if !found {
                return Err(format!("contact name \"{}\" not found; got {:?}", name, contacts));
            }
            return Ok(());
        }
        if args.len() >= 4 && args[1] == "0" && args[2].to_lowercase() == "name" {
            let name = unquote(args[3]);
            let first = contacts.first().and_then(|c| c["name"].as_str()).unwrap_or("");
            if first != name {
                return Err(format!("contact 0 name \"{}\"; got \"{}\"", name, first));
            }
            return Ok(());
        }
    }

    // events count <n> | events count >= <n>
    if action == "events" {
        if args.len() >= 3 && args[1].to_lowercase() == "count" {
            let op = args.get(2);
            let n: usize = args
                .get(3)
                .or_else(|| op)
                .and_then(|s| s.parse().ok())
                .ok_or_else(|| format!("events count: need number, got {:?}", args))?;
            if args.len() >= 4 && args[2] == ">=" {
                if events.len() < n {
                    return Err(format!("events count >= {}; got {}", n, events.len()));
                }
            } else {
                if events.len() != n {
                    return Err(format!("events count {}; got {}", n, events.len()));
                }
            }
            return Ok(());
        }
        // events event_type CREATED count >= 9 | count > 0  (args: events, event_type, CREATED, count, [>=|>], n)
        if args.len() >= 5 && args[1].to_lowercase() == "event_type" {
            let event_type = args[2].to_uppercase();
            if args[3].to_lowercase() != "count" {
                return Err(format!("events event_type X count [>=|>] n; got {:?}", args));
            }
            let (n, op_ge, op_gt) = if args.len() >= 6 && args[4] == ">=" {
                (args[5].parse::<usize>().ok(), true, false)
            } else if args.len() >= 6 && args[4] == ">" {
                (args[5].parse::<usize>().ok(), false, true)
            } else {
                (args.get(4).and_then(|s| s.parse().ok()), false, false)
            };
            let n = n.ok_or_else(|| format!("events event_type count: need number, got {:?}", args))?;
            let count = events.iter().filter(|e| e["event_type"].as_str() == Some(event_type.as_str())).count();
            if op_ge {
                if count < n {
                    return Err(format!("events event_type {} count >= {}; got {}", event_type, n, count));
                }
            } else if op_gt {
                if count <= n {
                    return Err(format!("events event_type {} count > {}; got {}", event_type, n, count));
                }
            } else if count != n {
                return Err(format!("events event_type {} count {}; got {}", event_type, n, count));
            }
            return Ok(());
        }
        // events aggregate_type contact count >= n | events aggregate_type transaction count > n
        if args.len() >= 5 && args[1].to_lowercase() == "aggregate_type" && args[3].to_lowercase() == "count" {
            let agg = args[2].to_lowercase();
            let (n, op_ge, op_gt) = if args.len() >= 6 && args[4] == ">=" {
                (args[5].parse::<usize>().ok(), true, false)
            } else if args.len() >= 6 && args[4] == ">" {
                (args[5].parse::<usize>().ok(), false, true)
            } else {
                (args.get(4).and_then(|s| s.parse().ok()), false, false)
            };
            let n = n.ok_or_else(|| format!("events aggregate_type count: need number, got {:?}", args))?;
            let count = events.iter()
                .filter(|e| e["aggregate_type"].as_str().map(|s| s.to_lowercase()) == Some(agg.clone()))
                .count();
            if op_ge {
                if count < n {
                    return Err(format!("events aggregate_type {} count >= {}; got {}", agg, n, count));
                }
            } else if op_gt {
                if count <= n {
                    return Err(format!("events aggregate_type {} count > {}; got {}", agg, n, count));
                }
            } else if count != n {
                return Err(format!("events aggregate_type {} count {}; got {}", agg, n, count));
            }
            return Ok(());
        }
        // events aggregate_type transaction event_type DELETED or UNDO count >= 1  (10 args)
        if args.len() >= 10 && args[1].to_lowercase() == "aggregate_type" && args[3].to_lowercase() == "event_type" && args[5].to_lowercase() == "or" && args[7].to_lowercase() == "count" {
            let agg = args[2].to_lowercase();
            let n: usize = args.get(9).and_then(|s| s.parse().ok())
                .ok_or_else(|| format!("events aggregate_type event_type DELETED or UNDO count >= n; need number, got {:?}", args))?;
            let count = events.iter()
                .filter(|e| e["aggregate_type"].as_str().map(|s| s.to_lowercase()) == Some(agg.clone()))
                .filter(|e| {
                    let et = e["event_type"].as_str();
                    et == Some("DELETED") || et == Some("UNDO")
                })
                .count();
            if count < n {
                return Err(format!("events aggregate_type {} event_type DELETED or UNDO count >= {}; got {}", agg, n, count));
            }
            return Ok(());
        }
        // events aggregate_type contact event_type CREATED count 3 | count >= 10 | count > 2  (7–8 args)
        if args.len() >= 7 && args[1].to_lowercase() == "aggregate_type" && args[3].to_lowercase() == "event_type" && args[5].to_lowercase() == "count" {
            let agg = args[2].to_lowercase();
            let event_type_raw = args[4].to_uppercase();
            let (n, op_ge, op_gt) = if args.len() >= 8 && args[6] == ">=" {
                (args[7].parse::<usize>().ok(), true, false)
            } else if args.len() >= 8 && args[6] == ">" {
                (args[7].parse::<usize>().ok(), false, true)
            } else {
                (args.get(6).and_then(|s| s.parse().ok()), false, false)
            };
            let n = n.ok_or_else(|| format!("events aggregate_type event_type count: need number, got {:?}", args))?;
            let count = events.iter()
                .filter(|e| e["aggregate_type"].as_str().map(|s| s.to_lowercase()) == Some(agg.clone()))
                .filter(|e| e["event_type"].as_str() == Some(event_type_raw.as_str()))
                .count();
            if op_ge {
                if count < n {
                    return Err(format!("events aggregate_type {} event_type {} count >= {}; got {}", agg, event_type_raw, n, count));
                }
            } else if op_gt {
                if count <= n {
                    return Err(format!("events aggregate_type {} event_type {} count > {}; got {}", agg, event_type_raw, n, count));
                }
            } else if count != n {
                return Err(format!("events aggregate_type {} event_type {} count {}; got {}", agg, event_type_raw, n, count));
            }
            return Ok(());
        }
    }

    // transactions count > <n> | transactions count >= <n>
    if action == "transactions" {
        if args.len() >= 3 && args[1].to_lowercase() == "count" {
            let op = args.get(2);
            let n: usize = args
                .get(3)
                .or_else(|| op)
                .and_then(|s| s.parse().ok())
                .ok_or_else(|| format!("transactions count: need number, got {:?}", args))?;
            if args.len() >= 4 && args[2] == ">" {
                if transactions.len() <= n {
                    return Err(format!("transactions count > {}; got {}", n, transactions.len()));
                }
            } else if args.len() >= 4 && args[2] == ">=" {
                if transactions.len() < n {
                    return Err(format!("transactions count >= {}; got {}", n, transactions.len()));
                }
            } else {
                if transactions.len() != n {
                    return Err(format!("transactions count {}; got {}", n, transactions.len()));
                }
            }
            return Ok(());
        }
    }

    Err(format!("Unknown assert command: {}", command))
}
