export TMPDIR=${TMPDIR:-/tmp}
export GIT_REPOS_DIR=$TMPDIR/git-resource-repo-cache
PATH=/usr/local/bin:$PATH # for jq

load_pubkey() {
	local private_key_path=$TMPDIR/git-resource-private-key
	local private_key_user=$(jq -r '.source.private_key_user // empty' <<<"$1")
	local forward_agent=$(jq -r '.source.forward_agent // false' <<<"$1")
	local passphrase="$(jq -r '.source.private_key_passphrase // empty' <<<"$1")"

	(jq -r '.source.private_key // empty' <<<"$1") >$private_key_path

	if [ -s $private_key_path ]; then
		chmod 0600 $private_key_path

		eval $(ssh-agent) >/dev/null 2>&1
		trap "kill $SSH_AGENT_PID" EXIT
		SSH_ASKPASS_REQUIRE=force SSH_ASKPASS=$(dirname $0)/askpass.sh GIT_SSH_PRIVATE_KEY_PASS="$passphrase" DISPLAY= ssh-add $private_key_path >/dev/null

		mkdir -p ~/.ssh
		cat >~/.ssh/config <<EOF
StrictHostKeyChecking no
LogLevel quiet
EOF
		if [ ! -z "$private_key_user" ]; then
			cat >>~/.ssh/config <<EOF
User $private_key_user
EOF
		fi
		if [ "$forward_agent" = "true" ]; then
			cat >>~/.ssh/config <<EOF
ForwardAgent yes
EOF
		fi
		chmod 0600 ~/.ssh/config
	fi
}

remote_br() {
	local rr="$1"

	[ -n "$rr" ] || return

	git show-ref |
		sed -e "s/.*\srefs\///g" |
		grep -e "^remotes\/" |
		grep -v -e "^remotes/origin/HEAD$" |
		sort -u |
		grep -e "^remotes/$rr/" |
		sed -e "s/^remotes\/$rr\///g"
}

local_br() {
	git show-ref |
		grep -e "\srefs/heads/" |
		sed -e "s/.*\srefs\/heads\///g" |
		sort -u
}

hash_url() {
	local input="$1"
	code=$(printf "$input" | md5sum - | cut -c-7)
	printf "$code"
}

set_remote() {
	local name="$1"
	local url="$2"

	(git remote get-url $name >&/dev/null) || git remote add $name $url
	git remote set-url $name $url
}

checkout_empty() {
	(
		git checkout --orphan $(date | md5sum | cut -c-16)
		git rm -rf .
	) >&/dev/null
}

wipe_remotes() {
	git remote |
		while read -r line; do
			git remote rm "$line"
		done
}

wipe_branches() {
	local_br |
		while read -r line; do
			git branch -D "$line"
		done
}

prepare_dir() {
	local dpath="$1"

	[ -n "$dpath" ] || return 1

	[ -e "$dpath" ] || {
		install -d "$dpath" || return 1
	}

	[ -d "$dpath" ] || return 1

	return 0
}

prepare_git_dir() {
	local dpath="$1"

	prepare_dir "$dpath" || return 1

	[ -e "$dpath/.git" ] || {
		(
			set -e
			cd "$dpath"
			git init
		) || return 1
	}

	return 0
}

perl_sponge() {
	perl -spe'open(STDOUT, ">", $o)' -- -o=$1
}

record_pushed_br() {
	local push_repo=$1
	local br=$2

	(
		[ -n "$(git rev-parse --show-toplevel)" ] || exit

		RECORDS_FPATH="$(git rev-parse --show-toplevel)/.git/concourse-git-mirror-resource/curr/records"
		[ -e "$RECORDS_FPATH" ] || install -D /dev/null "$RECORDS_FPATH"

		res_local=$(git show-ref | grep -e "\srefs/heads/${br}$")
		res_remot=$(git show-ref | grep -e "\srefs/remotes/${push_repo}/${br}$")

		res_local_rev=$(echo -n $res_local | awk '{print $1}')
		res_remot_rev=$(echo -n $res_local | awk '{print $1}')

		if [ -n "$res_local_rev" -a "$res_local_rev" = "$res_remote_rev" ]; then
			echo $res_remot >>"$RECORDS_FPATH"
			cat "$RECORDS_FPATH" | sort -u | perl_sponge "$RECORDS_FPATH"
		fi
	)
}

rotate_record() {
	(
		[ -n "$(git rev-parse --show-toplevel)" ] || exit

		CURR_SAVE_PATH="$(git rev-parse --show-toplevel)/.git/concourse-git-mirror-resource/curr"
		PREV_SAVE_PATH="$(git rev-parse --show-toplevel)/.git/concourse-git-mirror-resource/prev"

		[ -e "$CURR_SAVE_PATH" ] || exit
		[ -e "$PREV_SAVE_PATH" ] && {
			rm -r "$PREV_SAVE_PATH" || exit
		}
		mv "$CURR_SAVE_PATH" "$PREV_SAVE_PATH"
	)
}

is_deleted_previously() {
	local push_repo=$1
	local br=$2

	[ -n "$(git rev-parse --show-toplevel)" ] || return 1

	RECORDS_FPATH="$(git rev-parse --show-toplevel)/.git/concourse-git-mirror-resource/prev/records"
	[ -e "$RECORDS_FPATH" ] || return 1

	prev_rev=$(cat $RECORDS_FPATH | grep -e "\srefs/remotes/${push_repo}/${br}$" | awk '{print $1}')
	curr_rev=$(git show-ref | grep -e "\srefs/remotes/${push_repo}/${br}$" | awk '{print $1}')

	[ -n "$prev_rev" ] || return 1

	# If the version of previously pushed remote branch is equal to the version
	#  of current existing remote branch, we judge they are the same one.
	[ "$prev_rev" = "$curr_rev" ] && return 0

	return 1
}

show_pulled_branches_status() {
	git show-ref | grep -e "\srefs/heads/"
}

show_pushed_branches_status() {
	CURR_SAVE_PATH="$(git rev-parse --show-toplevel)/.git/concourse-git-mirror-resource/curr"

	[ -e "$CURR_SAVE_PATH" ] && cat $CURR_SAVE_PATH
}
