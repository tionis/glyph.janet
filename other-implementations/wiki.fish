function wiki --description 'wiki editor script'
	# {(deps mv mkdir fzf git)}
	argparse --name=wiki 'h/help' 'd/wikidir=?' 'no_commit' 'no_pull' 'ask_commit_message' 'v/verbose' 'cat' -- $argv
	or return

	if set -q _flag_help
		echo 'Wiki commands:'
		echo '  rm $file - delete file'
		echo '  log $optional_natural_date - open log for specified date or today as fallback'
		echo '  sync - initiate sync'
		echo '  $filename - edit $filename'
		echo 'if no command is given the document to open is selected using fzf'
		return 0
	end

	if test -z $_flag_wikidir
		set wiki_working_dir $WIKI_DIR
		if test -z $wiki_working_dir; return 1; end
	else
		set wiki_working_dir $_flag_wikidir
	end

	# Check if $EDITOR is set, if not set it to vim
	if not set -q EDITOR
		set -gx EDITOR vim
	end

	pushd $wiki_working_dir # Change into wiki directory using the directory stack
	switch $argv[1]
		case rm
			fish -c "git -C \"$wiki_working_dir\" pull" >/dev/null 2>&1 &
			if test -z $argv[2]
				echo "Specify page to delete!"
				return 1
			end
			git -C $wiki_working_dir rm "$wiki_working_dir/$argv[2].md"
			and git -C $wiki_working_dir commit -m "wiki: removed file $argv[2]"
			return 0
		case log
			fish -c "git -C \"$wiki_working_dir\" pull" >/dev/null 2>&1 &
			if test -z $argv[2]
				set date (date -I)
			else
				set date (date -I --date="$argv[2..]")
			end
			if test -z $date
				echo "Could not select date, aborting..."
				popd
				return 1
			end
			if not test -e "log/$date.md"
				set weekday (date --date=$date +%A)
				printf "# $date - $weekday\n## ToDo\n\n## Log" >"log/$date.md"
			end
			set file_path "log/$date"
		case sync
			git -C "$wiki_working_dir" pull
			git -C "$wiki_working_dir" push
			popd
			return 0
		case search
			fish -c "git -C \"$wiki_working_dir\" pull" >/dev/null 2>&1 &
			set file_path (git grep -i -l "$_flag_search_term" -- ':(exclude).obsidian/*' './*' \
			| fzf --ansi --preview "grep --ignore-case --colour=always\
			--line-number --context 10 \"$_flag_search_term\" {}")
			#set file_path "./"(rg --color=never --files-with-matches --no-messages -U "$_flag_search_term" \
			#| rg -N '\.md$' --color=never | rg -N --color=never '\.md$' -r '' \
			#| fzf --preview "rg --ignore-case --pretty --context 10 -U '$_flag_search_term' ./{}.md")".md"
			if not test "$file_path" # Check if there are any search results given by selection
				echo "No search result selected!"
				popd
				return 1
			end
		case ''
			fish -c "git -C \"$wiki_working_dir\" pull" >/dev/null 2>&1 &
			set file_path "."(find -name \*.md -readable \
			| grep -oP '(?<=^\.).*(?=\.md$)' \
			| fzf --ansi --preview "glow $wiki_working_dir{}.md" )".md"
			if test -z $file_path
				echo "No file selected!"
				popd
				return 1
			end
		case '*'
			fish -c "git -C \"$wiki_working_dir\" pull" >/dev/null 2>&1 &
			set file_path "$argv[1].md"
			if not test -e $file_path # Check if dirs to path exist, if not create them
				set -l sub_file_path (dirname $file_path)
				if not test -d $sub_file_path	
					echo "Creating directories for path $sub_file_path"
					mkdir -p $sub_file_path
				end
			end
	end

	if set -q _flag_cat
		cat $file_path
	else
		pushd (dirname $file_path)
			$EDITOR (basename $file_path)
		popd
	end

	if not set -q _flag_no_commit
		set -l change_count (git -C "$wiki_working_dir" status --porcelain=v1| count)
		if test $change_count -ne 0 # TODO parse what actually changed and generate commit message based on that
			git reset
			git add $file_path
			if set -q _flag_ask_commit_message
				set commit_message (read -P "Commit Message: ")
				if test -z "$commit_message"
					set commit_message "wiki: updated $file_path"
				end
				git commit -m $commit_message
			else
				git commit -m "wiki: updated $file_path"
			end
		end
		fish -c "git -C \"$wiki_working_dir\" push" >/dev/null 2>&1 &
	end
	popd
end
