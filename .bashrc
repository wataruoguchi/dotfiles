set -o vi
EDITOR=vi

PROMPT_COMMAND='if [[ "$profile" != "$PWD" && "$PWD" != "$HOME" && -e .profile ]]; then profile="$PWD"; source .profile; fi'
precmd() { eval "$PROMPT_COMMAND" }

source ~/.gitshorthands

# ---- Eza (better ls) -----
if command -v eza &>/dev/null; then
  alias ls="eza --icons=always"
fi

# ---- Zoxide (better cd) ----
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init bash)"
  alias cd="z"
fi

# ---- Neo vim
if command -v nvim &>/dev/null; then
  alias vi="nvim"
fi
