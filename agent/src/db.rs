use rusqlite::{params, Connection};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

#[derive(Clone)]
pub struct LocalDb {
    conn: Arc<Mutex<Connection>>,
}

pub struct DbStats {
    pub total_files: i64,
    pub pending_sync: i64,
}

impl LocalDb {
    pub fn open(data_dir: &str) -> anyhow::Result<Self> {
        let dir = PathBuf::from(data_dir);
        std::fs::create_dir_all(&dir)?;

        let db_path = dir.join("agent.db");
        let conn = Connection::open(&db_path)?;

        // Create tables
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS file_cache (
                path TEXT PRIMARY KEY,
                sha256_hash TEXT NOT NULL,
                size_bytes INTEGER NOT NULL,
                modified_at TEXT NOT NULL,
                synced_at TEXT,
                status TEXT NOT NULL DEFAULT 'pending',
                remote_id TEXT
            );
            CREATE TABLE IF NOT EXISTS sync_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                path TEXT NOT NULL,
                action TEXT NOT NULL,
                status TEXT NOT NULL,
                error TEXT,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
            CREATE INDEX IF NOT EXISTS idx_file_cache_status ON file_cache(status);
            CREATE INDEX IF NOT EXISTS idx_sync_log_created ON sync_log(created_at);"
        )?;

        Ok(Self { conn: Arc::new(Mutex::new(conn)) })
    }

    pub fn upsert_file(&self, path: &str, hash: &str, size: i64, modified: &str) -> anyhow::Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO file_cache (path, sha256_hash, size_bytes, modified_at, status) VALUES (?1, ?2, ?3, ?4, 'pending')
             ON CONFLICT(path) DO UPDATE SET sha256_hash=?2, size_bytes=?3, modified_at=?4, status='pending'",
            params![path, hash, size, modified],
        )?;
        Ok(())
    }

    pub fn mark_synced(&self, path: &str, remote_id: &str) -> anyhow::Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "UPDATE file_cache SET status='synced', synced_at=datetime('now'), remote_id=?2 WHERE path=?1",
            params![path, remote_id],
        )?;
        Ok(())
    }

    pub fn get_pending(&self) -> anyhow::Result<Vec<(String, String, i64)>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare("SELECT path, sha256_hash, size_bytes FROM file_cache WHERE status='pending' LIMIT 100")?;
        let rows = stmt.query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?, row.get::<_, i64>(2)?))
        })?;
        Ok(rows.filter_map(|r| r.ok()).collect())
    }

    pub fn remove_file(&self, path: &str) -> anyhow::Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute("DELETE FROM file_cache WHERE path=?1", params![path])?;
        Ok(())
    }

    pub fn log_sync(&self, path: &str, action: &str, status: &str, error: Option<&str>) -> anyhow::Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO sync_log (path, action, status, error) VALUES (?1, ?2, ?3, ?4)",
            params![path, action, status, error],
        )?;
        Ok(())
    }

    pub fn stats(&self) -> anyhow::Result<DbStats> {
        let conn = self.conn.lock().unwrap();
        let total: i64 = conn.query_row("SELECT COUNT(*) FROM file_cache", [], |r| r.get(0))?;
        let pending: i64 = conn.query_row("SELECT COUNT(*) FROM file_cache WHERE status='pending'", [], |r| r.get(0))?;
        Ok(DbStats { total_files: total, pending_sync: pending })
    }
}
