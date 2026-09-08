"""Generate a release's notes from the conventional-commit subjects in a range.

Deterministic by construction: the same commit range always produces the same
markdown, with no model in the loop. The release workflow calls it as

    python tool/release_notes.py --prev-tag v26.9.0 --new-tag v26.9.1 \
        --repo darthrommy/sappari-sheet > notes.md

and hands the result to `gh release create --notes-file`. Run it by hand with
the same arguments to preview a release's notes before cutting one.

Commit subjects are expected to read `type(scope)!: description`, which
`.githooks/commit-msg` enforces at commit time. Anything that slips through
that gate is still reported, under a collapsed "Other changes" block -- a
forgotten prefix should cost a reader a click, never a missing line.

Stdlib only: the publish job has no `pip install` step.
"""

import argparse
import re
import subprocess
import sys
from collections import namedtuple

Commit = namedtuple("Commit", "sha subject body")

# Types that earn a section of their own, in the order the sections render.
TYPE_SECTIONS = (
    ("feat", "Features"),
    ("fix", "Bug Fixes"),
    ("perf", "Performance"),
)

# Types that are real work but say nothing to someone downloading the app.
# Dropped from the notes entirely -- the Full Changelog link still covers them.
INTERNAL_TYPES = frozenset(
    {"docs", "refactor", "test", "build", "ci", "chore", "style", "revert"}
)

KNOWN_TYPES = frozenset(t for t, _ in TYPE_SECTIONS) | INTERNAL_TYPES

# `type(scope)!: description`. Deliberately case-sensitive: `Fix:` is not a
# conventional prefix, and guessing that it meant `fix:` would make the output
# depend on a judgement call rather than on the text.
SUBJECT_RE = re.compile(
    r"^(?P<type>[a-z]+)(?:\((?P<scope>[^()]+)\))?(?P<breaking>!)?:(?P<desc>.+)$"
)

# The conventional-commits breaking marker, as it opens a footer line.
BREAKING_FOOTER_RE = re.compile(r"^BREAKING[ -]CHANGE:", re.MULTILINE)

# A footer opens with a single-word token and a colon (`Co-Authored-By: ...`,
# `Refs: ...`) or with the breaking marker, whose token contains a space.
FOOTER_START_RE = re.compile(r"^(?:BREAKING[ -]CHANGE|[A-Za-z][A-Za-z-]*):[ \t]")

EMPTY_NOTE = "No user-facing changes in this release."

# Record and field separators for `git log --pretty`. Chosen because git will
# not emit them itself, so a commit body containing newlines cannot be mistaken
# for the start of the next record.
FIELD_SEP = "\x1f"
RECORD_SEP = "\x1e"


def is_breaking_body(body):
    """Does the message end with a BREAKING CHANGE footer?

    Only the trailing footer block counts, not the body above it. A commit that
    *describes* the convention will happily open a prose line with "BREAKING
    CHANGE:", and reading that as a breaking change is how this generator once
    announced its own arrival as one.

    The block is found by walking paragraphs backwards while each still opens
    with a footer token, so a footer may wrap onto continuation lines and may
    be followed by trailers like Co-Authored-By.
    """
    paragraphs = (body or "").split("\n\n")
    for paragraph in reversed(paragraphs):
        if not paragraph.strip():
            continue
        if not FOOTER_START_RE.match(paragraph.lstrip("\n")):
            return False  # prose: the footer block ended before this
        if BREAKING_FOOTER_RE.search(paragraph):
            return True
    return False


def _describe(scope, desc):
    """Render one commit's text: bold scope, or a capitalised description."""
    desc = desc.strip().rstrip(".")
    if scope:
        return "**" + scope + "**: " + desc
    return desc[:1].upper() + desc[1:]


def _bullet(text, sha):
    return "- " + text + " (" + sha + ")"


def format_notes(commits, prev_tag, new_tag, repo):
    """Turn a list of Commits into the release's markdown body.

    Pure: no git, no network, no clock. Everything the output depends on is an
    argument, which is what makes the generator testable and reproducible.
    """
    breaking = []
    sections = {type_: [] for type_, _ in TYPE_SECTIONS}
    other = []

    for commit in commits:
        match = SUBJECT_RE.match(commit.subject)
        type_ = match.group("type") if match else None

        if type_ not in KNOWN_TYPES:
            # No usable prefix. Keep the subject verbatim -- it was written as
            # prose, so capitalising or trimming it would only mangle it.
            other.append(_bullet(commit.subject.strip(), commit.sha))
            continue

        text = _describe(match.group("scope"), match.group("desc"))

        # A breaking change outranks its type: `build:` is normally dropped as
        # noise, but "macOS 11 is no longer supported" never is.
        if match.group("breaking") or is_breaking_body(commit.body):
            breaking.append(_bullet(text, commit.sha))
        elif type_ in sections:
            sections[type_].append(_bullet(text, commit.sha))

    blocks = []
    if breaking:
        blocks.append("## Breaking Changes\n\n" + "\n".join(breaking))
    for type_, heading in TYPE_SECTIONS:
        if sections[type_]:
            blocks.append("## " + heading + "\n\n" + "\n".join(sections[type_]))
    if other:
        blocks.append(
            "<details>\n<summary>Other changes ("
            + str(len(other))
            + ")</summary>\n\n"
            + "\n".join(other)
            + "\n\n</details>"
        )

    if not blocks:
        blocks.append(EMPTY_NOTE)

    base = "https://github.com/" + repo
    if prev_tag:
        link = base + "/compare/" + prev_tag + "..." + new_tag
    else:
        # First release: there is no earlier tag to diff against.
        link = base + "/commits/" + new_tag
    blocks.append("**Full Changelog**: " + link)

    return "\n\n".join(blocks) + "\n"


def read_commits(prev_tag, new_tag):
    """Read the commits a release covers, newest last, merges excluded."""
    span = (prev_tag + ".." + new_tag) if prev_tag else new_tag
    out = subprocess.run(
        [
            "git",
            "log",
            "--no-merges",
            "--reverse",
            "--pretty=format:%h" + FIELD_SEP + "%s" + FIELD_SEP + "%b" + RECORD_SEP,
            span,
        ],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
    ).stdout

    commits = []
    for record in out.split(RECORD_SEP):
        record = record.strip("\n")
        if not record:
            continue
        sha, subject, body = record.split(FIELD_SEP)
        commits.append(Commit(sha, subject, body))
    return commits


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--prev-tag", default="", help="the previous release's tag; empty on the first"
    )
    parser.add_argument("--new-tag", required=True, help="the tag being released")
    parser.add_argument("--repo", required=True, help="OWNER/NAME, for the diff link")
    args = parser.parse_args(argv)

    sys.stdout.write(
        format_notes(
            read_commits(args.prev_tag, args.new_tag),
            prev_tag=args.prev_tag,
            new_tag=args.new_tag,
            repo=args.repo,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
