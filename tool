#!/bin/sh
set -euo pipefail

list_directory() {
  local line="$1"
  local target_path

  target_path=$(printf '%s' "$line" | jq -r '.payload.arguments.parameters.path // "."')
  if [ -z "$target_path" ]; then
    target_path='.'
  fi

  if list_output=$(ls -1 -- "$target_path" 2>&1); then
    printf 'Contents of %s:\n%s' "$target_path" "$list_output"
  else
    printf 'Error reading directory %s: %s' "$target_path" "$list_output"
  fi
}

dispatch() {
  local tool_name="$1"
  local line="$2"

  case "$tool_name" in
    list_directory)
      list_directory "$line"
      ;;
    *)
      return 1
      ;;
  esac
}

tool_calls=0
while IFS= read -r line; do
  if [ -z "$(printf '%s' "$line" | tr -d '[:space:]')" ]; then
    continue
  fi

  if ! printf '%s' "$line" | jq -e 'has("type") and .type == "tool_call"' >/dev/null 2>&1; then
    continue
  fi

  tool_name=$(printf '%s' "$line" | jq -r '.payload.name // empty')
  if [ -z "$tool_name" ]; then
    continue
  fi

  if ! result_text=$(dispatch "$tool_name" "$line"); then
    continue
  fi

  tool_calls=$((tool_calls + 1))
  printf '%s\n' "$(
    jq -nc --arg tool_name "$tool_name" --arg text "$result_text" \
      '{type: "tool_result", source: "tool", payload: {tool_name: $tool_name, text: $text}}'
  )"
done

exit "$tool_calls"
