# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate translated data and its packaging in both app variants."""
import importlib.util
import json
import plistlib
from pathlib import Path
import re
import unittest

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('stage_localization', REPO / 'build/stages/stage-artifacts.py')
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)

def strings(path):
    values = {}
    for line in path.read_text().splitlines():
        if not line or line.startswith('/*'):
            continue
        match = re.fullmatch(r'("(?:[^"\\]|\\.)*") = ("(?:[^"\\]|\\.)*");', line)
        if not match:
            raise ValueError(f'malformed .strings line: {line}')
        key, value = map(json.loads, match.groups())
        if key in values or not value:
            raise ValueError(f'duplicate key or empty translation: {key}')
        values[key] = value
    return values

class ChineseLocalization(unittest.TestCase):
    def test_same_keys_and_placeholders_in_each_language(self):
        en = strings(REPO / 'app/Localization/en.lproj/Localizable.strings')
        for locale in ('zh-Hant', 'zh-Hans'):
            translated = strings(REPO / f'app/Localization/{locale}.lproj/Localizable.strings')
            self.assertEqual(set(translated), set(en))
            self.assertNotEqual(translated['Home'], en['Home'])
            for key, text in translated.items():
                self.assertEqual(re.findall(r'%(?:\d+\$)?[@dfsu]', text),
                                 re.findall(r'%(?:\d+\$)?[@dfsu]', en[key]))

    def test_both_variants_copy_translations_and_permission_messages(self):
        text = (REPO / 'app/xtool.yml').read_text()
        release = stage.release_xtool_yml(text)
        info = plistlib.loads((REPO / 'app/Info.plist').read_bytes())
        for locale in ('en', 'zh-Hant', 'zh-Hans'):
            self.assertIn(locale, info['CFBundleLocalizations'])
            path = f'Localization/{locale}.lproj'
            self.assertIn(path, text)
            self.assertIn(path, release)
            permissions = strings(REPO / 'app' / path / 'InfoPlist.strings')
            self.assertIn('NSLocalNetworkUsageDescription', permissions)
            self.assertIn('NSPhotoLibraryAddUsageDescription', permissions)
        self.assertIn('Localization', stage.RELEASE_LINKS)

    def test_chinese_and_japanese_codepages_are_staged(self):
        self.assertTrue({'c_936.nls', 'c_950.nls', 'c_932.nls'}.issubset(stage.NLS))
