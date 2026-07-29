#!/usr/bin/env bash
# Symlink this repo's config directories into $HOME.
#
# Every directory under .config/ here becomes ~/.config/<name> -> repo, except
# the ones listed in FILE_LINK_ONLY below (see why there). Executables listed in
# BIN_LINK are additionally linked into ~/.local/bin so they land on PATH.
#
#   ./install.sh              create/repair links, warn about anything in the way
#   ./install.sh --dry-run    print the plan, change nothing
#
# Nothing is ever deleted, moved, or overwritten. The only things this script
# removes are symlinks it is replacing, which costs nothing — their targets are
# left alone. Anything real sitting where a link should go is reported and
# skipped; clearing it is your call. Written for bash 3.2 — macOS ships no
# newer /bin/bash.

set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_SRC="${DOTFILES}/.config"
CONFIG_DST="${HOME}/.config"
BIN_DST="${HOME}/.local/bin"

DRY_RUN=0

# Directories whose application writes runtime state into the very directory it
# reads config from — linking the whole directory would drag that state into the
# repo. herdr keeps herdr-server.log, session.json, plugins.json and a 2 MB
# plugins/ tree beside config.toml; herdr-mirror keeps daemon state beside
# hosts.toml. For these, the directory stays real and only the listed files are
# linked.
#
# Format, one entry per line: "<dir> <file> [more files...]"
FILE_LINK_ONLY="
herdr config.toml
herdr-mirror hosts.toml
"

# Executables that have to be reachable on PATH, not just present in the config
# directory. herdr's config.toml binds prefix+= to the bare command name
# `herdr-balance-panes`, which herdr resolves through PATH — the copy under
# .config/herdr/bin/ alone leaves that keybinding dead.
#
# These need ~/.local/bin on PATH; .zshrc does that, and .zshrc is deliberately
# out of scope for this script (see the closing note).
#
# Format, one path per line, relative to .config/.
BIN_LINK="
herdr/bin/herdr-balance-panes
"

n_ok=0; n_linked=0; n_repointed=0; n_warned=0

# Set while handling a FILE_LINK_ONLY directory whose destination was a symlink
# we replaced with a real, empty directory.
FRESH_DIR=0

say() { printf '%s\n' "$*"; }
run() { if [ "${DRY_RUN}" -eq 1 ]; then say "      would: $*"; else "$@"; fi; }

usage() {
  # Print the header comment block — everything from line 2 up to the first
  # non-comment line — so the help text can never drift out of sync with it.
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
  exit 0
}

# Is $1 a symlink already resolving to $2?
points_at() {
  [ -L "$1" ] || return 1
  [ "$(readlink "$1")" = "$2" ]
}

# link_one <src> <dst> <label>
link_one() {
  local src="$1" dst="$2" label="$3"

  # Mid-dry-run the parent may still be the symlink we only *said* we would
  # replace, so anything under it would resolve into the repo and report
  # nonsense. Nothing can be sitting in a directory that would be created empty.
  if [ "${DRY_RUN}" -eq 1 ] && [ "${FRESH_DIR}" -eq 1 ]; then
    say "  link      ${label}"
    n_linked=$((n_linked + 1))
    return 0
  fi

  if points_at "${dst}" "${src}"; then
    say "  ok        ${label}"
    n_ok=$((n_ok + 1))
    return 0
  fi

  if [ -L "${dst}" ]; then
    # A symlink pointing somewhere else: removing it loses nothing, so repoint.
    say "  repoint   ${label}  (was -> $(readlink "${dst}"))"
    run rm "${dst}"
    run ln -s "${src}" "${dst}"
    n_repointed=$((n_repointed + 1))
    return 0
  fi

  if [ -e "${dst}" ]; then
    say "  WARNING   ${label}  (real $([ -d "${dst}" ] && echo directory || echo file) — left untouched, not linked)"
    n_warned=$((n_warned + 1))
    return 0
  fi

  say "  link      ${label}"
  run mkdir -p "$(dirname "${dst}")"
  run ln -s "${src}" "${dst}"
  n_linked=$((n_linked + 1))
}

# Files to link individually for <dir>, or empty if the whole dir gets linked.
files_for() {
  printf '%s\n' "${FILE_LINK_ONLY}" | while read -r entry_dir entry_files; do
    [ -n "${entry_dir}" ] || continue
    if [ "${entry_dir}" = "$1" ]; then
      printf '%s' "${entry_files}"
      return 0
    fi
  done
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n | --dry-run) DRY_RUN=1 ;;
    -h | --help) usage ;;
    -f | --force)
      say "--force is gone: this script never overwrites anything. Move the" >&2
      say "file or directory aside yourself, then rerun." >&2
      exit 2
      ;;
    *) say "unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

[ -d "${CONFIG_SRC}" ] || { say "no ${CONFIG_SRC} — is ${DOTFILES} the dotfiles repo?" >&2; exit 1; }

say "dotfiles: ${DOTFILES}"
[ "${DRY_RUN}" -eq 1 ] && say "mode:     dry run (nothing will change)"
say ""

for src in "${CONFIG_SRC}"/*/; do
  [ -d "${src}" ] || continue
  src="${src%/}"
  name="$(basename "${src}")"
  files="$(files_for "${name}")"

  if [ -z "${files}" ]; then
    link_one "${src}" "${CONFIG_DST}/${name}" ".config/${name}"
  else
    # Directory stays real; link only the declared config files inside it. An
    # older install may have left a symlink to the repo here — dropping it costs
    # nothing (the repo directory it points at is untouched), and leaving it
    # would make the links below resolve back into the repo, onto themselves.
    dst_dir="${CONFIG_DST}/${name}"
    FRESH_DIR=0
    if [ -L "${dst_dir}" ]; then
      say "  unlink    .config/${name}/  (was -> $(readlink "${dst_dir}")) — must be a real directory"
      run rm "${dst_dir}"
      n_repointed=$((n_repointed + 1))
      FRESH_DIR=1
    fi
    run mkdir -p "${dst_dir}"
    for f in ${files}; do
      if [ -e "${src}/${f}" ]; then
        link_one "${src}/${f}" "${dst_dir}/${f}" ".config/${name}/${f}"
      else
        say "  missing   .config/${name}/${f}  (not in the repo — skipped)"
      fi
    done
    FRESH_DIR=0
  fi
done

for rel in ${BIN_LINK}; do
  bin_src="${CONFIG_SRC}/${rel}"
  bin_name="$(basename "${rel}")"

  if [ ! -e "${bin_src}" ]; then
    say "  missing   .local/bin/${bin_name}  (not in the repo — skipped)"
    continue
  fi

  # A link to a non-executable file resolves fine and then fails to run, which
  # surfaces as a keybinding that silently does nothing. Say so up front.
  if [ ! -x "${bin_src}" ]; then
    say "  WARNING   .config/${rel} is not executable — chmod +x it or the link will not run"
    n_warned=$((n_warned + 1))
  fi

  link_one "${bin_src}" "${BIN_DST}/${bin_name}" ".local/bin/${bin_name}"
done

say ""
say "linked ${n_linked}, repointed ${n_repointed}, already correct ${n_ok}, warnings ${n_warned}"

if [ "${n_warned}" -gt 0 ]; then
  say ""
  say "Warnings above are real files or directories sitting where a link should"
  say "go. This script will not move or delete them. Inspect each one, move it"
  say "aside yourself (mv <path> <path>.bak), then rerun."
fi

say ""
say "Note: top-level dotfiles (.zshrc, .p10k.zsh, .gitshorthands, .bashrc) are"
say "deliberately NOT handled here — this script links things under .config/, plus"
say "the executables it puts in ~/.local/bin. The \$HOME copies of .zshrc and"
say ".gitshorthands currently differ from the repo, so linking them is a merge,"
say "not an install. Note that .zshrc is what puts ~/.local/bin on PATH."
