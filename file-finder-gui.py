#!/usr/bin/env python3
"""
File Clerk Finder — Desktop GUI
Search your indexed files by keyword, open files or folders with a click.
"""

import tkinter as tk
from tkinter import ttk
import sqlite3
import subprocess
import os
import platform


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


def search_index(query):
    """Full-text search the file index."""
    if not os.path.exists(DB_PATH):
        return []

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row

    if not query.strip():
        results = conn.execute(
            "SELECT * FROM files ORDER BY date_filed DESC"
        ).fetchall()
    else:
        terms = " ".join(f"{t}*" for t in query.strip().split())
        results = conn.execute("""
            SELECT f.* FROM files f
            JOIN files_fts fts ON f.id = fts.rowid
            WHERE files_fts MATCH ?
            ORDER BY rank
        """, (terms,)).fetchall()

    conn.close()
    return [dict(r) for r in results]


def open_file(path):
    """Open a file with the default application (cross-platform)."""
    if not os.path.exists(path):
        return
    system = platform.system()
    if system == "Darwin":
        subprocess.Popen(["open", path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif system == "Windows":
        os.startfile(path)
    else:
        subprocess.Popen(["xdg-open", path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def open_folder(path):
    """Open the containing folder in the file manager (cross-platform)."""
    folder = os.path.dirname(path) if os.path.isfile(path) else path
    if not os.path.exists(folder):
        return
    system = platform.system()
    if system == "Darwin":
        subprocess.Popen(["open", folder], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    elif system == "Windows":
        os.startfile(folder)
    else:
        subprocess.Popen(["xdg-open", folder], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class FileFinderApp:
    def __init__(self, root):
        self.root = root
        self.root.title("File Clerk — Find My Files")
        self.root.geometry("820x600")
        self.root.minsize(600, 400)
        self.results = []
        self._build_ui()
        self._do_search()

    def _build_ui(self):
        # Search bar
        search_frame = ttk.Frame(self.root, padding=10)
        search_frame.pack(fill=tk.X)

        ttk.Label(search_frame, text="Search:", font=("sans-serif", 12)).pack(side=tk.LEFT, padx=(0, 8))

        self.search_var = tk.StringVar()
        self.search_entry = ttk.Entry(search_frame, textvariable=self.search_var, font=("sans-serif", 12))
        self.search_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))
        self.search_entry.bind("<Return>", lambda e: self._do_search())
        self.search_entry.bind("<KeyRelease>", lambda e: self._do_search())

        ttk.Button(search_frame, text="Search", command=self._do_search).pack(side=tk.LEFT)

        # Status bar
        self.status_var = tk.StringVar(value="")
        ttk.Label(self.root, textvariable=self.status_var, padding=(10, 2)).pack(fill=tk.X)

        # Results treeview
        results_frame = ttk.Frame(self.root, padding=(10, 0, 10, 10))
        results_frame.pack(fill=tk.BOTH, expand=True)

        columns = ("name", "folder", "type", "tags")
        self.tree = ttk.Treeview(results_frame, columns=columns, show="headings", selectmode="browse")

        self.tree.heading("name", text="File Name", anchor=tk.W)
        self.tree.heading("folder", text="Folder", anchor=tk.W)
        self.tree.heading("type", text="Type", anchor=tk.W)
        self.tree.heading("tags", text="Tags", anchor=tk.W)

        self.tree.column("name", width=200, minwidth=120)
        self.tree.column("folder", width=200, minwidth=100)
        self.tree.column("type", width=80, minwidth=60)
        self.tree.column("tags", width=300, minwidth=150)

        scrollbar = ttk.Scrollbar(results_frame, orient=tk.VERTICAL, command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)

        self.tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        self.tree.bind("<Double-1>", self._on_double_click)
        self.tree.bind("<<TreeviewSelect>>", self._on_select)

        # Detail panel
        detail_frame = ttk.LabelFrame(self.root, text="Details", padding=10)
        detail_frame.pack(fill=tk.X, padx=10, pady=(0, 10))

        self.detail_text = tk.Text(detail_frame, height=5, wrap=tk.WORD, font=("sans-serif", 10),
                                   bg="#f5f5f5", relief=tk.FLAT, state=tk.DISABLED)
        self.detail_text.pack(fill=tk.X)

        # Action buttons
        btn_frame = ttk.Frame(self.root, padding=(10, 0, 10, 10))
        btn_frame.pack(fill=tk.X)

        self.btn_open = ttk.Button(btn_frame, text="Open File", command=self._open_selected, state=tk.DISABLED)
        self.btn_open.pack(side=tk.LEFT, padx=(0, 8))

        self.btn_folder = ttk.Button(btn_frame, text="Open Folder", command=self._open_selected_folder, state=tk.DISABLED)
        self.btn_folder.pack(side=tk.LEFT)

        ttk.Label(btn_frame, text="Double-click a result to open it", foreground="gray").pack(side=tk.RIGHT)

        self.search_entry.focus_set()

    def _do_search(self):
        query = self.search_var.get()
        self.results = search_index(query)

        for item in self.tree.get_children():
            self.tree.delete(item)

        for i, r in enumerate(self.results):
            self.tree.insert("", tk.END, iid=str(i), values=(
                r["filed_name"],
                r["folder"],
                r["file_type"],
                r["tags"]
            ))

        count = len(self.results)
        if query.strip():
            self.status_var.set(f'{count} result{"s" if count != 1 else ""} for "{query}"')
        else:
            self.status_var.set(f"{count} files indexed")

        self._clear_detail()
        self.btn_open.config(state=tk.DISABLED)
        self.btn_folder.config(state=tk.DISABLED)

    def _on_select(self, event):
        selection = self.tree.selection()
        if not selection:
            return

        idx = int(selection[0])
        r = self.results[idx]

        self.detail_text.config(state=tk.NORMAL)
        self.detail_text.delete("1.0", tk.END)
        self.detail_text.insert(tk.END, f"Path: {r['file_path']}\n")
        self.detail_text.insert(tk.END, f"Original name: {r['original_name']}\n")
        self.detail_text.insert(tk.END, f"Filed: {r['date_filed'] or 'N/A'}  |  Created: {r['date_created'] or 'N/A'}\n")
        self.detail_text.insert(tk.END, f"\n{r['summary']}")
        self.detail_text.config(state=tk.DISABLED)

        self.btn_open.config(state=tk.NORMAL)
        self.btn_folder.config(state=tk.NORMAL)

    def _on_double_click(self, event):
        self._open_selected()

    def _open_selected(self):
        selection = self.tree.selection()
        if not selection:
            return
        idx = int(selection[0])
        open_file(self.results[idx]["file_path"])

    def _open_selected_folder(self):
        selection = self.tree.selection()
        if not selection:
            return
        idx = int(selection[0])
        open_folder(self.results[idx]["file_path"])

    def _clear_detail(self):
        self.detail_text.config(state=tk.NORMAL)
        self.detail_text.delete("1.0", tk.END)
        self.detail_text.config(state=tk.DISABLED)


if __name__ == "__main__":
    root = tk.Tk()
    app = FileFinderApp(root)
    root.mainloop()
