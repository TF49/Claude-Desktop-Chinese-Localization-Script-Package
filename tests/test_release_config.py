import json
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]


class ReleaseConfigTests(unittest.TestCase):
    def test_config_lists_install_candidates_and_relative_resource_paths(self) -> None:
        config = json.loads((PROJECT_ROOT / "config.json").read_text(encoding="utf-8"))

        self.assertIn(
            r"C:\Program Files\WindowsApps\Claude_*_x64__pzs8sxrjxfjjc\app\resources",
            config["installCandidates"],
        )
        self.assertIn(r"%LOCALAPPDATA%\AnthropicClaude\app-*\resources", config["installCandidates"])
        self.assertNotIn("supportedVersion", config)
        self.assertNotIn("supportedVersions", config)
        self.assertNotIn("supportedInstallRoot", config)
        self.assertNotIn("resourceChecks", config)
        self.assertNotIn("applyTargets", config)
        self.assertEqual(config["resourceRelativePaths"]["appAsar"], "app.asar")
        self.assertEqual(config["resourceRelativePaths"]["ionEnLocale"], r"ion-dist\i18n\en-US.json")
        self.assertEqual(config["applyRelativePaths"]["rootLocale"], "zh-CN.json")
        self.assertEqual(config["applyRelativePaths"]["ionLocale"], r"ion-dist\i18n\zh-CN.json")
        self.assertEqual(
            config["applyRelativePaths"]["statsigLocale"],
            r"ion-dist\i18n\statsig\zh-CN.json",
        )

    def test_patch_manifest_contains_locale_allowlist_and_runtime_fallback_rules(self) -> None:
        patches = json.loads(
            (PROJECT_ROOT / "patches" / "main-ui-patches.json").read_text(encoding="utf-8")
        )
        descriptions = {item["description"] for item in patches}

        self.assertIn("支持 zh-CN 语言代码", descriptions)
        self.assertIn("语言菜单显示简体中文", descriptions)
        self.assertIn("安装说明选项", descriptions)
        self.assertIn("zh-CN 中文字体回退", descriptions)
        self.assertIn("侧边栏 New task 默认文案", descriptions)
        self.assertIn("侧边栏 Projects 默认文案", descriptions)
        self.assertIn("侧边栏 Scheduled 默认文案", descriptions)
        self.assertIn("侧边栏 Customize 默认文案", descriptions)
        self.assertNotIn("zh-CN 角落署名", descriptions)

        locale_patch = next(item for item in patches if item["description"] == "支持 zh-CN 语言代码")
        self.assertIn('"zh-CN"', locale_patch["replace"])
        self.assertIn('HP=["en-US"', locale_patch["find"])
        self.assertIn('"id-ID"]', locale_patch["find"])

        language_name_patch = next(
            item for item in patches if item["description"] == "语言菜单显示简体中文"
        )
        self.assertIn("简体中文", language_name_patch["replace"])
        self.assertNotIn("by芹菜香", language_name_patch["replace"])
        self.assertNotIn("Chinese (Simplified)", language_name_patch["replace"])
        self.assertIn("getDisplayNames(VP,NIn)", language_name_patch["find"])
        self.assertIn("localName:n.formatters.getDisplayNames(t,NIn).of(t)", language_name_patch["find"])

        font_patch = next(item for item in patches if item["description"] == "zh-CN 中文字体回退")
        self.assertIn("--font-claude-response: var(--font-anthropic-serif)", font_patch["find"])
        self.assertIn('html[lang=zh-CN]', font_patch["replace"])
        self.assertIn("Microsoft YaHei UI", font_patch["replace"])

        sidebar_patch = next(item for item in patches if item["description"] == "侧边栏 Projects 默认文案")
        self.assertIn('defaultMessage:"Projects"', sidebar_patch["find"])
        self.assertIn('defaultMessage:"项目"', sidebar_patch["replace"])

        serialized = json.dumps(patches, ensure_ascii=False)
        self.assertIn("简体中文", serialized)
        self.assertNotIn("by芹菜香", serialized)
        self.assertNotIn("body::after", serialized)


if __name__ == "__main__":
    unittest.main()
