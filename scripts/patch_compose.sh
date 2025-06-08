#!/bin/bash
in="$1"; root="$2"
out="${in%.*}.patched.yml"
cp "$in" "${in}.bak"
> "$out"
while IFS= read -r l; do
  if [[ "$l" =~ image:[[:space:]]*([^[:space:]]+) ]]; then
    nm=$(sanitize "${BASH_REMATCH[1]}")
    echo "    image: ${nm}:offline"
  elif [[ "$l" =~ [-[:space:]]*([^:]+):(/.*) ]]; then
    vol=$(basename "${BASH_REMATCH[1]}")
    tgt="${root}/${vol}:${BASH_REMATCH[2]}"
    echo "      - $tgt"
  else
    echo "$l"
  fi
done < "$in"
