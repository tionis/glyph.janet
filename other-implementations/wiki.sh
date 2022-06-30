#!/bin/sh
wiki_working_dir="$WIKI_DIR"
if test -z "$wiki_working_dir"; then exit 1; fi

# Check if $EDITOR is set, if not set it to vim
if test -z EDITOR; then
	set -gx EDITOR vim
fi

original_dir="$(pwd)"
cd "$wiki_working_dir" || exit 1 # Change into wiki directory using the directory stack
case $1 in
	rm)
		sh -c "git -C \"$wiki_working_dir\" pull" >/dev/null 2>&1 &
		if test -z "$2"; then
			echo "Specify page to delete!"
			return 1
		fi
		git -C "$wiki_working_dir" rm "$wiki_working_dir/$2.md" \
		&& git -C "$wiki_working_dir" commit -m "wiki: removed file $2"
		exit 0
		;;
	log)
		sh -c "git -C \"$wiki_working_dir\" pull" >/dev/null 2>&1 &
		if test -z "$2"; then
			date=$(date -I)
		else
			date="$(date -I --date="$*")"
		fi
		if test -z "$date"; then
			echo "Could not select date, aborting..."
			cd "$original_dir" || exit 1
			return 1
		fi
		if not test -e "log/$date.md"; then
			weekday="$(date --date="$date" "+%A")"
			printf "# %s - %s\n## ToDo\n\n## Log" >"log/$date.md" "$date" "$weekday"
		fi
		file_path="log/$date"
		;;
	sync)
		git -C "$wiki_working_dir" pull
		git -C "$wiki_working_dir" push
		cd "$original_dir" || exit 1
		exit 0
		;;
	search)
		sh -c "git -C \"$wiki_working_dir\" pull" >/dev/null 2>&1 &
		file_path="$(git grep -i -l "$2" -- ':(exclude).obsidian/*' './*' \
		| fzf --ansi --preview "grep --ignore-case --colour=always\
		--line-number --context 10 \"$2\" {}")"
		#set file_path "./"(rg --color=never --files-with-matches --no-messages -U "$_flag_search_term" \
		#| rg -N '\.md$' --color=never | rg -N --color=never '\.md$' -r '' \
		#| fzf --preview "rg --ignore-case --pretty --context 10 -U '$_flag_search_term' ./{}.md")".md"
		if not test "$file_path"; then # Check if there are any search results given by selection
			echo "No search result selected!"
			cd "$original_dir" || exit 1
			return 1
		fi
		;;
	help)
		echo "Wiki commands:"
		echo "  rm \$file - delete file"
		echo "  log \$optional_natural_date - open log for specified date or today as fallback"
		echo "  sync - initiate sync"
		echo "  \$filename - edit \$filename"
		echo "if no command is given the document to open is selected using fzf"
		exit 0
		;;
	"")
		sh -c "git -C \"$wiki_working_dir\" pull" >/dev/null 2>&1 &
		file_path=./$(find . -name \*.md -readable\
		| grep -oP '(?<=^\.).*(?=\.md$)' \
		| fzf --ansi --preview "glow $wiki_working_dir{}.md" )".md"
		if test -z "$file_path"; then
			echo "No file selected!"
			cd "$original_dir" || exit 1
			return 1
		fi
		;;
	*)
		sh -c "git -C \"$wiki_working_dir\" pull" >/dev/null 2>&1 &
		file_path="$1.md"
		if not test -e "$file_path"; then # Check if dirs to path exist, if not create them
			sub_file_path="$(dirname "$file_path")"
			if not test -d "$sub_file_path"; then	
				echo "Creating directories for path $sub_file_path"
				mkdir -p "$sub_file_path"
			fi
		fi
esac

prev_dir=$(pwd)
cd "$(dirname "$file_path")" || exit 1
	$EDITOR "$(basename "$file_path")"
cd "$prev_dir" || exit 1

change_count=$(git -C "$wiki_working_dir" status --porcelain=v1| count)
if test "$change_count" -ne 0; then # TODO parse what actually changed and generate commit message based on that
	git reset
	git add "$file_path"
	git commit -m "wiki: updated $file_path"
fi
sh -c "git -C \"$wiki_working_dir\" push" >/dev/null 2>&1 &
cd "$original_dir" || exit 1
