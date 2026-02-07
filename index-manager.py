#!/usr/bin/env python3
"""
file-clerk index manager
Manages the SQLite metadata index for filed documents.
Used by both the filer (daily cron) and finder (on-demand search).
"""

import sqlite3
import os
import sys
import json
from datetime import datetime


def get_config():
    """Load config.env from the same directory as this script."""
    config_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.env")
    config = {}
    if os.path.exists(config_path):
        with open(config_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, _, value = line.partition('=')
                    config[key.strip()] = value.strip().strip('"').strip("'")
    return config


_config = get_config()
DB_PATH = _config.get("DB_PATH",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "index.sqlite"))


def init_db():
    """Create the index database and tables if they don't exist."""
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT UNIQUE NOT NULL,
            original_name TEXT,
            filed_name TEXT,
            folder TEXT,
            file_type TEXT,
            summary TEXT,
            tags TEXT,
            date_created TEXT,
            date_filed TEXT,
            source TEXT DEFAULT 'desktop'
        )
    """)
    conn.execute("""
        CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(
            file_path, filed_name, summary, tags,
            content='files',
            content_rowid='id'
        )
    """)
    conn.executescript("""
        CREATE TRIGGER IF NOT EXISTS files_ai AFTER INSERT ON files BEGIN
            INSERT INTO files_fts(rowid, file_path, filed_name, summary, tags)
            VALUES (new.id, new.file_path, new.filed_name, new.summary, new.tags);
        END;
        CREATE TRIGGER IF NOT EXISTS files_ad AFTER DELETE ON files BEGIN
            INSERT INTO files_fts(files_fts, rowid, file_path, filed_name, summary, tags)
            VALUES ('delete', old.id, old.file_path, old.filed_name, old.summary, old.tags);
        END;
        CREATE TRIGGER IF NOT EXISTS files_au AFTER UPDATE ON files BEGIN
            INSERT INTO files_fts(files_fts, rowid, file_path, filed_name, summary, tags)
            VALUES ('delete', old.id, old.file_path, old.filed_name, old.summary, old.tags);
            INSERT INTO files_fts(rowid, file_path, filed_name, summary, tags)
            VALUES (new.id, new.file_path, new.filed_name, new.summary, new.tags);
        END;
    """)
    conn.commit()
    conn.close()


def add_file(file_path, original_name, filed_name, folder, file_type, summary, tags, date_created, source="desktop"):
    """Add or update a file entry in the index."""
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""
        INSERT INTO files (file_path, original_name, filed_name, folder, file_type, summary, tags, date_created, date_filed, source)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(file_path) DO UPDATE SET
            summary=excluded.summary,
            tags=excluded.tags,
            date_filed=excluded.date_filed
    """, (file_path, original_name, filed_name, folder, file_type, summary, tags, date_created, datetime.now().isoformat(), source))
    conn.commit()
    conn.close()


def search(query):
    """Full-text search across all indexed files."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    results = conn.execute("""
        SELECT f.* FROM files f
        JOIN files_fts fts ON f.id = fts.rowid
        WHERE files_fts MATCH ?
        ORDER BY rank
    """, (query,)).fetchall()
    conn.close()
    return [dict(r) for r in results]


def list_all():
    """List all indexed files."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    results = conn.execute("SELECT * FROM files ORDER BY date_filed DESC").fetchall()
    conn.close()
    return [dict(r) for r in results]


def dump_json():
    """Dump entire index as JSON (for AI to read)."""
    return json.dumps(list_all(), indent=2, default=str)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: index-manager.py [init|add|search|list|dump]")
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "init":
        init_db()
        print("Database initialized.")

    elif cmd == "add":
        if len(sys.argv) < 10:
            print("Usage: index-manager.py add <file_path> <original_name> <filed_name> <folder> <file_type> <summary> <tags> <date_created> [source]")
            sys.exit(1)
        source = sys.argv[10] if len(sys.argv) > 10 else "desktop"
        add_file(*sys.argv[2:10], source)
        print(f"Indexed: {sys.argv[2]}")

    elif cmd == "search":
        if len(sys.argv) < 3:
            print("Usage: index-manager.py search <query>")
            sys.exit(1)
        results = search(sys.argv[2])
        if results:
            for r in results:
                print(f"  {r['file_path']}")
                print(f"    Tags: {r['tags']}")
                print(f"    Summary: {r['summary']}")
                print()
        else:
            print("No results found.")

    elif cmd == "list":
        results = list_all()
        for r in results:
            print(f"  {r['file_path']}")
            print(f"    Tags: {r['tags']}")
            print()

    elif cmd == "dump":
        print(dump_json())

    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)
