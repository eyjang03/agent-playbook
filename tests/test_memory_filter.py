"""Project-topic filtering uses synthetic memory only."""
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import playbook


class MemoryFilterTests(unittest.TestCase):
    def render(self, fixture):
        with patch.object(playbook, "read", return_value=fixture):
            return playbook.codex_memory_for("/projects/Selected")

    def test_current_and_older_topics_are_filtered(self):
        for section in ("What's in Memory", "Older Memory Topics"):
            with self.subTest(section=section):
                text = self.render("## " + section + "\n### /projects/Unrelated\nPRIVATE_OTHER\n### /projects/Selected\nSELECTED_TOPIC\n")
                self.assertNotIn("PRIVATE_OTHER", text)
                self.assertIn("SELECTED_TOPIC", text)

    def test_switching_sections_does_not_carry_a_match_forward(self):
        text = self.render("## What's in Memory\n### /projects/Selected\nSELECTED_TOPIC\n## Older Memory Topics\n### /projects/Unrelated\nPRIVATE_OTHER\n")
        self.assertIn("SELECTED_TOPIC", text)
        self.assertNotIn("PRIVATE_OTHER", text)

    def test_general_preferences_remain_available(self):
        text = self.render("## General Tips\nGENERAL_PREFERENCE\n## Older Memory Topics\n### /projects/Unrelated\nPRIVATE_OTHER\n")
        self.assertIn("GENERAL_PREFERENCE", text)
        self.assertNotIn("PRIVATE_OTHER", text)

    def test_heading_case_does_not_disable_filter(self):
        text = self.render("## OLDER MEMORY TOPICS\n### /projects/Unrelated\nPRIVATE_OTHER\n")
        self.assertNotIn("PRIVATE_OTHER", text)


if __name__ == "__main__":
    unittest.main()
