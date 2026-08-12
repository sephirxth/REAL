from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("real_install", ROOT / "scripts" / "install.py")
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class InstallTests(unittest.TestCase):
    def test_adds_runtime_and_is_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            config = project / "project.godot"
            config.write_text('[application]\nconfig/name="Fixture"\n', encoding="utf-8")

            MODULE.install(project)
            first = config.read_text(encoding="utf-8")
            MODULE.install(project)
            second = config.read_text(encoding="utf-8")

            self.assertEqual(first, second)
            self.assertEqual(first.count("[autoload]"), 1)
            for name, filename in MODULE.AUTOLOADS:
                self.assertIn(name, first)
                self.assertTrue((project / "addons" / "real" / filename).is_file())

    def test_preserves_unrelated_autoloads(self) -> None:
        source = '[autoload]\nExisting="*res://existing.gd"\n\n[display]\nwindow/size/viewport_width=640\n'
        rendered = MODULE.render_project_config(source)
        self.assertIn('Existing="*res://existing.gd"', rendered)
        self.assertIn("[display]", rendered)
        self.assertLess(rendered.index("RuntimeActionExecutor"), rendered.index("[display]"))

    def test_refuses_to_overwrite_local_change(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp)
            (project / "project.godot").write_text("", encoding="utf-8")
            MODULE.install(project)
            target = project / "addons" / "real" / MODULE.RUNTIME_FILES[0]
            target.write_text("local change", encoding="utf-8")
            with self.assertRaises(FileExistsError):
                MODULE.install(project)


if __name__ == "__main__":
    unittest.main()
