#!/usr/bin/env python3
import os
import re
import sys

# ----------------------------------------
# Config
# ----------------------------------------

# File extensions to inspect
SRC_EXTS = {".sv", ".svh", ".v", ".vh"}

# Regex patterns
RE_MODULE       = re.compile(r'^\s*module\s+([a-zA-Z_][a-zA-Z0-9_$]*)')
RE_ENDMODULE    = re.compile(r'^\s*endmodule\b')

RE_PC_PATH_DECL     = re.compile(r'\bPC_Path\b')
RE_ADDR_PATH_DECL   = re.compile(r'\bAddrPath\b')

RE_TO_ADDR_FROM_PC  = re.compile(r'\bToAddrFromPC\s*\(')
RE_TO_PC_FROM_ADDR  = re.compile(r'\bToPC_FromAddr\s*\(')

# ----------------------------------------
# ANSI color helpers (for terminal only)
# ----------------------------------------

class Color:
    RESET   = "\033[0m"
    BOLD    = "\033[1m"
    CYAN    = "\033[36m"
    MAGENTA = "\033[35m"
    GREEN   = "\033[32m"
    YELLOW  = "\033[33m"
    BLUE    = "\033[34m"

# CORRECTED: use ":" instead of "="
HIT_COLOR = {
    "PC_Path declaration":     Color.CYAN,
    "AddrPath declaration":    Color.MAGENTA,
    "ToAddrFromPC() call":     Color.GREEN,
    "ToPC_FromAddr() call":    Color.YELLOW,
}
def colorize_hit(hit_label: str) -> str:
    c = HIT_COLOR.get(hit_label, "")
    if not c:
        return hit_label
    return f"{c}{hit_label}{Color.RESET}"

# ----------------------------------------
# Helper functions
# ----------------------------------------

def is_source_file(path: str) -> bool:
    _, ext = os.path.splitext(path)
    return ext in SRC_EXTS

def walk_sources(root_dir: str):
    for dirpath, dirnames, filenames in os.walk(root_dir):
        for f in filenames:
            full = os.path.join(dirpath, f)
            if is_source_file(full):
                yield full

def scan_file(path: str, out_handle):
    current_module = None

    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for lineno, raw_line in enumerate(f, start=1):
                line = raw_line.rstrip("\n")

                # Track module context
                m_mod = RE_MODULE.match(line)
                if m_mod:
                    current_module = m_mod.group(1)

                if RE_ENDMODULE.match(line):
                    current_module = None

                stripped = line.strip()
                if stripped.startswith("//") or stripped == "":
                    continue

                # Figure out what this line contains
                hits = []

                if RE_PC_PATH_DECL.search(line):
                    hits.append("PC_Path declaration")

                if RE_ADDR_PATH_DECL.search(line):
                    hits.append("AddrPath declaration")

                if RE_TO_ADDR_FROM_PC.search(line):
                    hits.append("ToAddrFromPC() call")

                if RE_TO_PC_FROM_ADDR.search(line):
                    hits.append("ToPC_FromAddr() call")

                if hits:
                    mod_str = current_module if current_module is not None else "<no-module>"
                    hit_types_plain = ", ".join(hits)

                    # ---- Write plain text to the report file ----
                    out_handle.write(
                        f"{path}:{lineno}: [{mod_str}] [{hit_types_plain}]\n"
                        f"    {line.strip()}\n\n"
                    )

                    # ---- Print color-coded summary to terminal ----
                    colored_hits = ", ".join(colorize_hit(h) for h in hits)
                    print(
                        f"{Color.BOLD}{path}{Color.RESET}:"
                        f"{Color.BLUE}{lineno}{Color.RESET} "
                        f"[{mod_str}] [{colored_hits}]"
                    )

    except Exception as e:
        out_handle.write(f"# ERROR reading {path}: {e}\n\n")
        print(f"{Color.RED}[ERROR]{Color.RESET} reading {path}: {e}", file=sys.stderr)

# ----------------------------------------
# Main
# ----------------------------------------

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 scan_pc_addr_usage.py <SRC_ROOT> <OUT_REPORT.txt>")
        sys.exit(1)

    src_root = sys.argv[1]
    out_path = sys.argv[2]

    with open(out_path, "w", encoding="utf-8") as out:
        out.write("# PC_Path / AddrPath usage and ToAddrFromPC / ToPC_FromAddr calls\n")
        out.write(f"# Source root: {os.path.abspath(src_root)}\n\n")

        for src_file in walk_sources(src_root):
            scan_file(src_file, out)

    print(f"\n[INFO] Scan complete. Report written to: {out_path}")

if __name__ == "__main__":
    main()
