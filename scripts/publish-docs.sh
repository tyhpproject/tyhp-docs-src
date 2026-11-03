#!/usr/bin/env bash
# Build docs in this repo and publish HTML to tyhpproject/tyhp-docs (GitHub Pages / tyhplang.com).
# This script pushes to a public repo.
# Git remotes use HTTPS (not SSH).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_ROOT
readonly DOCS_REPO="tyhpproject/tyhp-docs"
readonly DOCS_CNAME="tyhplang.com"
readonly OUTPUT_ZIP="${PROJECT_ROOT}/output.zip"

PUBLISH_WORKDIR=""
ZIP_BACKUP=""
ZIP_EXISTED=0
DRY_RUN=0
ALLOW_DIRTY=0

usage() {
  cat <<'EOF'
Usage: scripts/publish-docs.sh [options]

Builds the site (composer install, php generate_docs.php), replaces the
contents of a fresh clone of tyhpproject/tyhp-docs with output/ (keeping CNAME
and adding .nojekyll), commits "Publish Tyhp docs from tyhp-docs-src <commit>",
and pushes it. GitHub Pages serves the result at https://tyhplang.com.

The generator rewrites the committed output.zip on every build. This script
puts the original output.zip back when it exits, so publishing leaves the
working tree as it found it. To refresh output.zip, run php generate_docs.php
and commit the archive.

Options:
  --dry-run       Build, clone, and stage the new site, then print the change
                  summary. Does not commit or push.
  --allow-dirty   Publish from a working tree with uncommitted changes (the
                  site then contains pages that are not in git).
  -h, --help      Show this help.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        ;;
      --allow-dirty)
        ALLOW_DIRTY=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "error: unknown argument: $1 (see --help)" >&2
        exit 1
        ;;
    esac
    shift
  done
}

cleanup() {
  restore_output_zip
  if [[ -n "${PUBLISH_WORKDIR}" && -d "${PUBLISH_WORKDIR}" ]]; then
    rm -rf "${PUBLISH_WORKDIR}"
  fi
}

require_tool() {
  local tool_name="$1"
  if ! command -v "$tool_name" >/dev/null 2>&1; then
    echo "Missing required tool: ${tool_name}" >&2
    exit 1
  fi
}

check_clean_tree() {
  local status
  local count
  status="$(git -C "$PROJECT_ROOT" status --porcelain --untracked-files=normal)"
  [[ -n "$status" ]] || return 0
  count="$(printf '%s\n' "$status" | wc -l | tr -d ' ')"
  if [[ "$ALLOW_DIRTY" -eq 1 ]]; then
    echo "warning: publishing from a dirty working tree (${count} path(s)); --allow-dirty is set." >&2
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "warning: the working tree has ${count} uncommitted path(s); a real publish stops here unless --allow-dirty is passed." >&2
    return 0
  fi
  echo "error: the working tree has ${count} uncommitted path(s). Commit the docs that ship first, or pass --allow-dirty." >&2
  exit 1
}

backup_output_zip() {
  ZIP_BACKUP="$(mktemp "${TMPDIR:-/tmp}/tyhp-docs-output-zip.XXXXXX")"
  if [[ -f "$OUTPUT_ZIP" ]]; then
    ZIP_EXISTED=1
    cp -p "$OUTPUT_ZIP" "$ZIP_BACKUP"
  fi
}

restore_output_zip() {
  [[ -n "$ZIP_BACKUP" ]] || return 0
  if [[ "$ZIP_EXISTED" -eq 1 ]]; then
    cp -p "$ZIP_BACKUP" "$OUTPUT_ZIP"
  else
    rm -f "$OUTPUT_ZIP"
  fi
  rm -f "$ZIP_BACKUP"
  ZIP_BACKUP=""
}

source_revision() {
  local sha
  sha="$(git -C "$PROJECT_ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
  if [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain --untracked-files=normal 2>/dev/null)" ]]; then
    sha+="-dirty"
  fi
  printf '%s\n' "$sha"
}

main() {
  parse_args "$@"

  require_tool php
  require_tool composer
  require_tool git
  require_tool rsync
  require_tool sass
  require_tool zip

  cd "$PROJECT_ROOT"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY RUN: the site is built and staged in a temporary clone; nothing is committed or pushed."
  fi
  check_clean_tree
  local revision
  revision="$(source_revision)"

  trap cleanup EXIT
  backup_output_zip
  composer install --no-interaction
  php generate_docs.php
  restore_output_zip

  local output_dir="${PROJECT_ROOT}/output"
  if [[ ! -d "$output_dir" ]]; then
    echo "Docs generator did not write ${output_dir}" >&2
    exit 1
  fi

  PUBLISH_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/tyhp-docs-publish.XXXXXX")"

  git clone --depth 1 "https://github.com/${DOCS_REPO}.git" "${PUBLISH_WORKDIR}/tyhp-docs"
  cd "${PUBLISH_WORKDIR}/tyhp-docs"

  local cname_backup=""
  if [[ -f CNAME ]]; then
    cname_backup="$(mktemp "${TMPDIR:-/tmp}/tyhp-docs-cname.XXXXXX")"
    cp CNAME "$cname_backup"
  fi

  # Replace the published tree with generated HTML + assets. Keep .git.
  find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +

  rsync -a --exclude 'output.zip' "${output_dir}/" ./

  if [[ -n "$cname_backup" ]]; then
    cp "$cname_backup" CNAME
    rm -f "$cname_backup"
  else
    printf '%s\n' "$DOCS_CNAME" > CNAME
  fi

  touch .nojekyll

  git add -A
  if git diff --cached --quiet; then
    echo "No docs changes to publish."
    return 0
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY RUN: would commit and push these changes to ${DOCS_REPO}:"
    git diff --cached --stat
    return 0
  fi

  git commit -m "Publish Tyhp docs from tyhp-docs-src ${revision}"

  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"
  git push origin "$branch"
  echo "Published docs to https://github.com/${DOCS_REPO} (https://${DOCS_CNAME})"
}

main "$@"
