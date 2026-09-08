"""Behaviour tests for .githooks/commit-msg.

Run with:  python tool/commit_msg_hook_test.py

These run the real hook script through `sh` against real message files, rather
than re-implementing its rules in Python -- a hook that passes a paraphrase of
itself proves nothing about what `git commit` will actually do.
"""

import pathlib
import subprocess
import tempfile
import unittest

HOOK = pathlib.Path(__file__).resolve().parents[1] / ".githooks" / "commit-msg"


def run_hook(message):
    """Run the hook over a commit message. Returns (exit code, stderr)."""
    with tempfile.TemporaryDirectory() as tmp:
        path = pathlib.Path(tmp) / "COMMIT_EDITMSG"
        path.write_text(message, encoding="utf-8")
        done = subprocess.run(
            ["sh", str(HOOK), str(path)],
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        return done.returncode, done.stderr


class AcceptsTest(unittest.TestCase):
    def assertAccepted(self, message):
        code, err = run_hook(message)
        self.assertEqual(code, 0, "rejected with: " + err)

    def test_accepts_a_plain_type(self):
        self.assertAccepted("feat: remember the film format between runs\n")

    def test_accepts_every_allowed_type(self):
        for type_ in (
            "feat", "fix", "perf", "docs", "refactor",
            "test", "build", "ci", "chore", "style", "revert",
        ):
            with self.subTest(type=type_):
                self.assertAccepted(type_ + ": do a thing\n")

    def test_accepts_a_scope(self):
        self.assertAccepted("fix(windows): match the version line in a CRLF pubspec\n")

    def test_accepts_a_breaking_marker(self):
        self.assertAccepted("feat!: drop 645 support\n")

    def test_accepts_a_scope_with_a_breaking_marker(self):
        self.assertAccepted("feat(export)!: drop 645 support\n")

    def test_accepts_a_subject_followed_by_a_body(self):
        self.assertAccepted(
            "fix: stop dropping the last frame\n"
            "\n"
            "The grid walked the frame list with an off-by-one bound.\n"
        )

    def test_accepts_a_git_generated_merge_subject(self):
        self.assertAccepted("Merge branch 'main' of github.com:darthrommy/sappari-sheet\n")

    def test_accepts_a_git_generated_revert_subject(self):
        self.assertAccepted('Revert "feat: drop 645 support"\n')

    def test_accepts_a_fixup_subject(self):
        # `git commit --fixup` writes these; rebase --autosquash consumes them.
        self.assertAccepted("fixup! feat: remember the film format\n")

    def test_accepts_a_squash_subject(self):
        self.assertAccepted("squash! feat: remember the film format\n")

    def test_ignores_leading_comment_lines(self):
        self.assertAccepted("# a comment git put here\nfeat: do a thing\n")


class RejectsTest(unittest.TestCase):
    def assertRejected(self, message):
        code, err = run_hook(message)
        self.assertEqual(code, 1, "accepted, but should not have been")
        return err

    def test_rejects_a_bare_prose_subject(self):
        self.assertRejected("Remember the photographer between runs\n")

    def test_rejects_an_unknown_type(self):
        self.assertRejected("wibble: do a thing\n")

    def test_rejects_a_capitalised_type(self):
        self.assertRejected("Fix: match the version line\n")

    def test_rejects_a_missing_space_after_the_colon(self):
        self.assertRejected("feat:do a thing\n")

    def test_rejects_an_empty_description(self):
        self.assertRejected("feat: \n")

    def test_rejects_an_empty_message(self):
        self.assertRejected("\n")

    def test_rejects_a_message_that_is_only_comments(self):
        self.assertRejected("# please enter a commit message\n#\n")

    def test_rejects_an_empty_scope(self):
        self.assertRejected("feat(): do a thing\n")

    def test_rejects_a_bang_before_the_scope(self):
        self.assertRejected("feat!(export): drop 645 support\n")

    def test_explains_the_rule_and_lists_the_allowed_types(self):
        err = self.assertRejected("Remember the photographer between runs\n")
        self.assertIn("Remember the photographer between runs", err)
        self.assertIn("feat", err)
        self.assertIn("fix", err)
        self.assertIn("chore", err)

    def test_names_the_release_notes_as_the_reason(self):
        err = self.assertRejected("Remember the photographer between runs\n")
        self.assertIn("release notes", err.lower())


if __name__ == "__main__":
    unittest.main(verbosity=2)
