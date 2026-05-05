import unittest
from pathlib import Path
import subprocess
import json


PROJECT_ROOT = Path(__file__).resolve().parents[1]


class UserRepoLayoutTests(unittest.TestCase):
    def _decompress_with_node(self, relative_path: str) -> str:
        script = """
const fs = require("node:fs");
const zlib = require("node:zlib");
const filePath = process.argv[1];
const input = fs.readFileSync(filePath);
process.stdout.write(zlib.zstdDecompressSync(input));
"""
        return subprocess.run(
            ["node", "-e", script, str(PROJECT_ROOT / relative_path)],
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
        ).stdout

    def test_user_download_repo_excludes_maintainer_only_files(self) -> None:
        excluded = [
            "docs/GITHUB_RELEASE.md",
            "locales/manual-overrides.json",
            "patches/test_release_config.py",
            "scripts/_find_mixed.py",
            "scripts/_patch_batch1.py",
            "scripts/_patch_batch2.py",
            "scripts/_patch_bulk.py",
            "scripts/_patch_core_ui.py",
            "scripts/_patch_nav.py",
            "scripts/apply_localization.py",
            "scripts/build_release_assets.py",
            "scripts/package_release.ps1",
            "scripts/restore_asar.py",
            "scripts/rollback_localization.py",
            "scripts/verify_localization.py",
            "tests/test_build_release_assets.py",
            "tests/test_github_release_docs.py",
        ]

        for relative_path in excluded:
            self.assertFalse((PROJECT_ROOT / relative_path).exists(), relative_path)

    def test_user_download_repo_keeps_runtime_entrypoints(self) -> None:
        required = [
            "README.md",
            "docs/USAGE.md",
            "config.json",
            "patches/main-ui-patches.json",
            "scripts/common.ps1",
            "scripts/apply_localization.ps1",
            "scripts/verify_localization.ps1",
            "scripts/rollback_localization.ps1",
            "一键应用.bat",
            "一键校验.bat",
            "一键回滚.bat",
        ]

        for relative_path in required:
            self.assertTrue((PROJECT_ROOT / relative_path).exists(), relative_path)

    def test_compressed_runtime_assets_do_not_contain_corner_watermark(self) -> None:
        output = self._decompress_with_node("patched-assets/v1/c6a992d55-CjiVONe_.css.zst")

        self.assertNotIn("by芹菜香", output)
        self.assertNotIn("body::after", output)
        self.assertIn("html[lang=zh-CN]", output)

    def test_patch_manifest_no_longer_uses_signed_language_label(self) -> None:
        patches = json.loads((PROJECT_ROOT / "patches" / "main-ui-patches.json").read_text(encoding="utf-8"))
        serialized = json.dumps(patches, ensure_ascii=False)

        self.assertIn("简体中文", serialized)
        self.assertNotIn("简体中文（by芹菜香）", serialized)
        self.assertNotIn("简体中文（By芹菜香）", serialized)
        self.assertNotIn("Chinese (Simplified)", serialized)

    def test_verification_targets_use_chinese_for_regression_samples(self) -> None:
        targets = json.loads(
            (PROJECT_ROOT / "locales" / "verification-targets.json").read_text(encoding="utf-8")
        )

        for group_name in ["ionLocale", "rootLocale", "statsigLocale"]:
            for key, value in targets[group_name].items():
                self.assertRegex(value, r"[^\x00-\x7F]", f"{group_name}:{key}")


if __name__ == "__main__":
    unittest.main()
