#!/bin/sh
# Established by voxtype.service
# 
# Launches the voxtype daemon injecting dictionary list.
# - Flattens dictionary.txt into comma separated string Whispr can read
# - Ignores comments
# - Inject dictionary into --initial-prompt string
# - Starts voxtype daemon
#
# This allows us to have a dedicated dictionary list instead of editing the dictionary
# inline in the ~/.config/voxtype.config.toml

dictionary_file="$HOME/.config/voxtype/dictionary.txt"

if [ -r "$dictionary_file" ]; then
	terms=$(
		grep -vE '^[[:space:]]*(#|$)' "$dictionary_file" \
			| sed 's/^[[:space:]]*//; s/[[:space:]]*$//' \
			| paste -sd, - \
			| sed 's/,/, /g'
	)
	if [ -n "$terms" ]; then
		exec /usr/bin/voxtype --initial-prompt "Dictionary: $terms" daemon
	fi
fi

# Non-readable / empty dictionary: fall back to config.toml as-is.
exec /usr/bin/voxtype daemon
