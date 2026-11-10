use std::fs::OpenOptions;
use std::io::Write;
use std::time::{SystemTime, UNIX_EPOCH};
pub fn log_event(
	data_dir: &str,
	level: &str,
	event: &str,
	job_id: Option<u32>,
	details: &str,
) {
	let path = format!("{}/events.log", data_dir);
	let timestamp = SystemTime::now()
    	.duration_since(UNIX_EPOCH)
    	.unwrap()
    	.as_secs();
	let id = match job_id {
    	Some(id) => id.to_string(),
    	None => "-".to_string(),
	};
	let line = format!(
    	"{} {} {} job_id={} {}\n",
    	timestamp,
    	level,
    	event,
    	id,
    	details
	);
	if let Ok(mut file) = OpenOptions::new()
    	.create(true)
    	.append(true)
    	.open(path)
	{
    	let _ = file.write_all(line.as_bytes());
	}
}

