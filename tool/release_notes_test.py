"""Unit tests for the release-notes generator.

Run with:  python tool/release_notes_test.py

Stdlib only -- these run on the release workflow's ubuntu runner with no
`pip install` step, so keep it that way.
"""

import os
import subprocess
import tempfile
import unittest

from release_notes import Commit, format_notes, read_commits

REPO = "darthrommy/sappari-sheet"


def notes(commits, prev_tag="v26.9.0", new_tag="v26.9.1"):
    return format_notes(commits, prev_tag=prev_tag, new_tag=new_tag, repo=REPO)


class CategorisationTest(unittest.TestCase):
    def test_feat_commit_lands_under_features(self):
        body = notes([Commit("abc1234", "feat: add a Windows installer", "")])
        self.assertIn("## Features", body)
        self.assertIn("- Add a Windows installer (abc1234)", body)

    def test_fix_commit_lands_under_bug_fixes(self):
        body = notes([Commit("def5678", "fix: stop dropping the last frame", "")])
        self.assertIn("## Bug Fixes", body)
        self.assertIn("- Stop dropping the last frame (def5678)", body)

    def test_perf_commit_lands_under_performance(self):
        body = notes([Commit("aaa1111", "perf: cache cover-fitted cells", "")])
        self.assertIn("## Performance", body)
        self.assertIn("- Cache cover-fitted cells (aaa1111)", body)

    def test_internal_types_are_dropped_entirely(self):
        body = notes([
            Commit("bbb2222", "ci: update workflow actions", ""),
            Commit("ddd4444", "docs: expand the README", ""),
            Commit("eee5555", "refactor: split the sheet painter", ""),
            Commit("fff6666", "test: cover the settings store", ""),
            Commit("aaa7777", "build: bump the Flutter version", ""),
            Commit("bbb8888", "style: reformat the sidebar", ""),
            Commit("ccc9999", "chore(release): 26.9.1", ""),
        ])
        self.assertNotIn("update workflow actions", body)
        self.assertNotIn("expand the README", body)
        self.assertNotIn("split the sheet painter", body)
        self.assertNotIn("cover the settings store", body)
        self.assertNotIn("bump the Flutter version", body)
        self.assertNotIn("reformat the sidebar", body)
        self.assertNotIn("26.9.1", body.split("Full Changelog")[0])

    def test_sections_appear_in_fixed_order(self):
        body = notes([
            Commit("aaa1111", "perf: cache cover-fitted cells", ""),
            Commit("bbb2222", "fix: stop dropping the last frame", ""),
            Commit("ccc3333", "feat: add a Windows installer", ""),
            Commit("ddd4444", "feat!: drop 645 support", ""),
        ])
        order = [
            body.index("## Breaking Changes"),
            body.index("## Features"),
            body.index("## Bug Fixes"),
            body.index("## Performance"),
        ]
        self.assertEqual(order, sorted(order))

    def test_commits_keep_their_input_order_within_a_section(self):
        body = notes([
            Commit("aaa1111", "feat: first change", ""),
            Commit("bbb2222", "feat: second change", ""),
        ])
        self.assertLess(body.index("First change"), body.index("Second change"))


class ScopeTest(unittest.TestCase):
    def test_scope_is_rendered_in_bold_before_the_description(self):
        body = notes([Commit("abc1234", "fix(windows): match a CRLF pubspec", "")])
        self.assertIn("- **windows**: match a CRLF pubspec (abc1234)", body)

    def test_scoped_description_is_not_capitalised(self):
        # The bold scope already opens the line, so capitalising after the
        # colon would read as a mid-sentence capital.
        body = notes([Commit("abc1234", "feat(sidebar): remember the film format", "")])
        self.assertIn("- **sidebar**: remember the film format (abc1234)", body)


class BreakingChangeTest(unittest.TestCase):
    def test_bang_marks_a_breaking_change(self):
        body = notes([Commit("abc1234", "feat!: drop 645 support", "")])
        self.assertIn("## Breaking Changes", body)
        self.assertIn("- Drop 645 support (abc1234)", body)

    def test_bang_with_scope_marks_a_breaking_change(self):
        body = notes([Commit("abc1234", "feat(export)!: drop 645 support", "")])
        self.assertIn("## Breaking Changes", body)
        self.assertIn("- **export**: drop 645 support (abc1234)", body)

    def test_breaking_change_footer_marks_a_breaking_change(self):
        body = notes([Commit(
            "abc1234",
            "fix: rewrite the settings file",
            "BREAKING CHANGE: old settings are discarded",
        )])
        self.assertIn("## Breaking Changes", body)
        self.assertIn("- Rewrite the settings file (abc1234)", body)

    def test_breaking_commit_is_not_also_listed_in_its_type_section(self):
        body = notes([Commit("abc1234", "feat!: drop 645 support", "")])
        self.assertNotIn("## Features", body)

    def test_prose_mentioning_the_footer_mid_body_is_not_breaking(self):
        # Regression: a commit explaining the convention began a body line with
        # "BREAKING CHANGE:" and was promoted to Breaking Changes. The footer
        # only counts as a footer -- at the end of the message, not in prose.
        body = notes([Commit(
            "abc1234",
            "ci: generate the release notes from commit subjects",
            "A `!` or a\n"
            "BREAKING CHANGE: footer promotes a commit even when its type\n"
            "would otherwise be dropped.\n"
            "\n"
            "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>",
        )])
        self.assertNotIn("## Breaking Changes", body)

    def test_footer_still_counts_when_a_trailer_follows_it(self):
        body = notes([Commit(
            "abc1234",
            "fix: rewrite the settings file",
            "The format changed.\n"
            "\n"
            "BREAKING CHANGE: old settings are discarded\n"
            "\n"
            "Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>",
        )])
        self.assertIn("## Breaking Changes", body)

    def test_footer_may_wrap_onto_a_continuation_line(self):
        body = notes([Commit(
            "abc1234",
            "fix: rewrite the settings file",
            "The format changed.\n"
            "\n"
            "BREAKING CHANGE: old settings are discarded and\n"
            "cannot be recovered.",
        )])
        self.assertIn("## Breaking Changes", body)

    def test_hyphenated_footer_spelling_is_accepted(self):
        body = notes([Commit(
            "abc1234",
            "fix: rewrite the settings file",
            "BREAKING-CHANGE: old settings are discarded",
        )])
        self.assertIn("## Breaking Changes", body)

    def test_a_breaking_internal_commit_still_surfaces(self):
        # An internal type is dropped for being noise, but a breaking change
        # is never noise -- users need to hear about it.
        body = notes([Commit(
            "abc1234",
            "build: require macOS 12",
            "BREAKING CHANGE: macOS 11 is no longer supported",
        )])
        self.assertIn("## Breaking Changes", body)
        self.assertIn("- Require macOS 12 (abc1234)", body)


class OtherChangesTest(unittest.TestCase):
    def test_unprefixed_commit_lands_in_a_collapsed_block(self):
        body = notes([Commit("abc1234", "Rebrand to Sappari Sheet", "")])
        self.assertIn("<details>", body)
        self.assertIn("<summary>Other changes (1)</summary>", body)
        self.assertIn("- Rebrand to Sappari Sheet (abc1234)", body)

    def test_unknown_type_prefix_is_treated_as_unprefixed(self):
        body = notes([Commit("abc1234", "wibble: do a thing", "")])
        self.assertIn("<summary>Other changes (1)</summary>", body)
        self.assertIn("- wibble: do a thing (abc1234)", body)

    def test_other_changes_block_is_omitted_when_empty(self):
        body = notes([Commit("abc1234", "feat: add a Windows installer", "")])
        self.assertNotIn("<details>", body)
        self.assertNotIn("Other changes", body)

    def test_other_changes_counts_every_unprefixed_commit(self):
        body = notes([
            Commit("aaa1111", "Rebrand to Sappari Sheet", ""),
            Commit("bbb2222", "Rebuild the sheet from the Figma design", ""),
        ])
        self.assertIn("<summary>Other changes (2)</summary>", body)

    def test_dropped_internal_commits_do_not_reach_other_changes(self):
        body = notes([
            Commit("aaa1111", "ci: update workflow actions", ""),
            Commit("bbb2222", "feat: add a Windows installer", ""),
        ])
        self.assertNotIn("Other changes", body)


class FullChangelogTest(unittest.TestCase):
    def test_compare_link_spans_the_two_tags(self):
        body = notes([Commit("abc1234", "feat: add a Windows installer", "")])
        self.assertIn(
            "**Full Changelog**: https://github.com/" + REPO
            + "/compare/v26.9.0...v26.9.1",
            body,
        )

    def test_first_release_links_to_the_commit_list_instead(self):
        body = notes(
            [Commit("abc1234", "feat: add a Windows installer", "")], prev_tag=""
        )
        self.assertIn(
            "**Full Changelog**: https://github.com/" + REPO + "/commits/v26.9.1",
            body,
        )
        self.assertNotIn("compare", body)

    def test_changelog_link_is_last(self):
        body = notes([Commit("abc1234", "feat: add a Windows installer", "")])
        self.assertTrue(body.rstrip().endswith("compare/v26.9.0...v26.9.1"))


class EmptyReleaseTest(unittest.TestCase):
    def test_release_with_no_notable_commits_still_says_something(self):
        body = notes([Commit("aaa1111", "ci: update workflow actions", "")])
        self.assertIn("No user-facing changes", body)
        self.assertIn("**Full Changelog**", body)

    def test_release_with_no_commits_at_all_still_says_something(self):
        body = notes([])
        self.assertIn("No user-facing changes", body)


class SubjectCleanupTest(unittest.TestCase):
    def test_unscoped_description_is_capitalised(self):
        body = notes([Commit("abc1234", "feat: add a Windows installer", "")])
        self.assertIn("- Add a Windows installer", body)

    def test_trailing_period_is_stripped(self):
        body = notes([Commit("abc1234", "feat: add a Windows installer.", "")])
        self.assertIn("- Add a Windows installer (abc1234)", body)

    def test_whitespace_around_the_description_is_stripped(self):
        body = notes([Commit("abc1234", "feat:   add a Windows installer   ", "")])
        self.assertIn("- Add a Windows installer (abc1234)", body)

    def test_type_matching_is_case_sensitive(self):
        # `Fix: ...` is not a conventional prefix; the hook rejects it, and if
        # one slips through it must not be silently promoted to a Bug Fix.
        body = notes([Commit("abc1234", "Fix: something", "")])
        self.assertIn("Other changes", body)
        self.assertNotIn("## Bug Fixes", body)


class ReadCommitsTest(unittest.TestCase):
    """Exercises the git-reading half against a real repository.

    Everything above tests the formatter with hand-built Commits. These build
    an actual repo instead, so the record/field separators are proven against
    output git really emits -- a body with blank lines in it included.
    """

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.cwd = os.getcwd()
        self.addCleanup(os.chdir, self.cwd)
        self.git("init", "-b", "main")
        self.git("config", "user.email", "test@example.com")
        self.git("config", "user.name", "Test")
        os.chdir(self.tmp.name)

    def git(self, *args):
        return subprocess.run(
            ["git", "-C", self.tmp.name, *args],
            check=True, capture_output=True, text=True, encoding="utf-8",
        ).stdout

    def commit(self, message):
        path = os.path.join(self.tmp.name, "file.txt")
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(message + "\n")
        self.git("add", "-A")
        self.git("commit", "--no-verify", "-m", message)

    def test_reads_a_commit_range_oldest_first(self):
        self.commit("feat: before the tag")
        self.git("tag", "v1.0.0")
        self.commit("feat: first after")
        self.commit("fix: second after")

        commits = read_commits("v1.0.0", "HEAD")

        self.assertEqual(
            [c.subject for c in commits],
            ["feat: first after", "fix: second after"],
        )

    def test_a_body_with_blank_lines_survives_the_record_separator(self):
        self.commit("feat: before the tag")
        self.git("tag", "v1.0.0")
        self.git(
            "commit", "--allow-empty", "--no-verify",
            "-m", "fix: rewrite the settings file",
            "-m", "The format changed.",
            "-m", "BREAKING CHANGE: old settings are discarded",
        )

        commits = read_commits("v1.0.0", "HEAD")

        self.assertEqual(len(commits), 1)
        self.assertIn("The format changed.", commits[0].body)
        self.assertIn("BREAKING CHANGE: old settings are discarded", commits[0].body)
        # And the footer is still recognised once it has been through git.
        body = format_notes(commits, prev_tag="v1.0.0", new_tag="v1.0.1", repo=REPO)
        self.assertIn("## Breaking Changes", body)

    def test_no_previous_tag_reads_the_whole_history(self):
        self.commit("feat: the very first commit")
        self.commit("fix: the second")

        commits = read_commits("", "HEAD")

        self.assertEqual(len(commits), 2)

    def test_an_unknown_revision_fails_with_a_readable_message(self):
        self.commit("feat: the only commit")

        with self.assertRaises(SystemExit) as caught:
            read_commits("v9.9.9", "HEAD")

        message = str(caught.exception)
        self.assertIn("v9.9.9..HEAD", message)
        self.assertNotIn("Traceback", message)


if __name__ == "__main__":
    unittest.main(verbosity=2)
