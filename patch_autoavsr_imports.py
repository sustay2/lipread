import os
import re
import shutil
from typing import Iterable, List, Optional

ROOT = os.path.join("ai_inference", "auto_avsr")
PACKAGE = "auto_avsr"


def discover_modules(root: str) -> set:
    modules = set()
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        rel_dir = os.path.relpath(dirpath, root)
        if rel_dir == ".":
            rel_dir = ""
        else:
            rel_dir = rel_dir.replace(os.sep, ".")
        if "__init__.py" in filenames or rel_dir:
            if rel_dir:
                modules.add(rel_dir)
        for filename in filenames:
            if filename.endswith(".py") and filename != "__init__.py":
                mod_name = filename[:-3]
                full = f"{rel_dir}.{mod_name}" if rel_dir else mod_name
                modules.add(full)
    return modules


def is_internal_module(module: str, modules: set) -> bool:
    if module.startswith(PACKAGE + "."):
        return True
    candidates: Iterable[str]
    parts = module.split(".")
    candidates = [".".join(parts[:i]) for i in range(1, len(parts) + 1)]
    return any(c in modules for c in candidates)


def resolve_relative(module: str, file_dir: str) -> Optional[str]:
    dots = len(module) - len(module.lstrip("."))
    base = module.lstrip(".")
    rel_parts = [] if file_dir == "." else file_dir.split(os.sep)
    if dots > len(rel_parts) + 1:
        return None
    target_parts = rel_parts[: len(rel_parts) + 1 - dots]
    if base:
        target_parts.append(base.replace(".", os.sep))
    target_module_path = os.path.join(*target_parts) if target_parts else ""
    target_module = target_module_path.replace(os.sep, ".")
    return f"{PACKAGE}.{target_module}" if target_module else PACKAGE


def patch_line(line: str, file_dir: str, modules: set) -> str:
    from_pattern = re.compile(r"^(\s*)from\s+([\w\.]+)\s+import\s+([^#\n]+)(\s*(#.*)?)$")
    import_pattern = re.compile(r"^(\s*)import\s+([^#\n]+)(\s*(#.*)?)$")

    from_match = from_pattern.match(line)
    if from_match:
        indent, module, imports, comment = from_match.group(1), from_match.group(2), from_match.group(3), from_match.group(4)
        new_module = module
        if module.startswith("."):
            resolved = resolve_relative(module, file_dir)
            if resolved:
                new_module = resolved
        elif is_internal_module(module, modules):
            if not module.startswith(PACKAGE + "."):
                new_module = f"{PACKAGE}.{module}"
        if new_module != module:
            return f"{indent}from {new_module} import {imports}{comment}\n"
        return line

    import_match = import_pattern.match(line)
    if import_match:
        indent, modules_part, comment = import_match.group(1), import_match.group(2), import_match.group(3)
        parts = [p.strip() for p in modules_part.split(",")]
        new_parts: List[str] = []
        changed = False
        for part in parts:
            sub_match = re.match(r"([\w\.]+)(\s+as\s+\w+)?", part)
            if not sub_match:
                new_parts.append(part)
                continue
            mod_name, alias = sub_match.group(1), sub_match.group(2) or ""
            new_mod = mod_name
            if mod_name.startswith("."):
                resolved = resolve_relative(mod_name, file_dir)
                if resolved:
                    new_mod = resolved
            elif is_internal_module(mod_name, modules):
                if not mod_name.startswith(PACKAGE + "."):
                    new_mod = f"{PACKAGE}.{mod_name}"
            if new_mod != mod_name:
                changed = True
            new_parts.append(f"{new_mod}{alias}")
        if changed:
            joined = ", ".join(new_parts)
            return f"{indent}import {joined}{comment}\n"
        return line

    return line


def process_file(filepath: str, modules: set) -> bool:
    rel_path = os.path.relpath(filepath, ROOT)
    file_dir = os.path.dirname(rel_path)
    if file_dir == "":
        file_dir = "."
    with open(filepath, "r", encoding="utf-8") as f:
        lines = f.readlines()

    new_lines = [patch_line(line, file_dir, modules) for line in lines]
    if new_lines != lines:
        backup_path = filepath + ".bak"
        shutil.copyfile(filepath, backup_path)
        with open(filepath, "w", encoding="utf-8") as f:
            f.writelines(new_lines)
        return True
    return False


def main() -> None:
    if not os.path.isdir(ROOT):
        print(f"Root path '{ROOT}' does not exist. Nothing to patch.")
        return

    modules = discover_modules(ROOT)
    changed_files: List[str] = []

    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for filename in filenames:
            if not filename.endswith(".py"):
                continue
            filepath = os.path.join(dirpath, filename)
            if filepath.endswith(".bak"):
                continue
            if process_file(filepath, modules):
                changed_files.append(filepath)

    if changed_files:
        print("Patched files:")
        for path in changed_files:
            print(f" - {os.path.relpath(path)}")
    else:
        print("No changes made.")


if __name__ == "__main__":
    main()
