#!/bin/bash -e

set -o pipefail

check_env() {
    if [ -z "${!1}" ]; then
        echo "::error::environment variable $1 is not set" >&2
        exit 1
    fi
}

check_command() {
    if ! [ -x "$(command -v $1)" ]; then
      echo "::error::command $1 is not available." >&2
      exit 1
    fi
}

check_env GITHUB_REPOSITORY
check_env GITHUB_EVENT_PATH
check_env GITHUB_TOKEN
check_env GITHUB_EVENT_NAME
check_command curl
check_command jq

set -u

fetch() {
  curl -sL -H "Authorization: token ${GITHUB_TOKEN}" "https://api.github.com${1}"
}

fetch_pr_json() {
    fetch /repos/${GITHUB_REPOSITORY}/pulls/$1
}

fetch_commits() {
    fetch /repos/${GITHUB_REPOSITORY}/pulls/$1/commits | jq -r .[].sha
}

event_jq() {
    jq $@ "${GITHUB_EVENT_PATH}"
}

is_pr_comment() {
    [ ${GITHUB_EVENT_NAME} = issue_comment ] && event_jq -e .issue.pull_request > /dev/null
}

get_comment_text() {
    event_jq -r .comment.body
}

get_author() {
    event_jq -r .comment.user.login
}

get_pr_id() {
    event_jq -r .issue.pull_request.id
}

if ! is_pr_comment; then
    echo '::debug::skipping as this is not a PR comment'
    exit 0
fi

backport_branch=$(get_comment_text | sed -En 's/^\s*backport ([0-9]+\.[0-9]+)\s.*/\1/p')
pull_request=$(fetch_pr_json $(get_pr_id))
pr_branch="backport/$backport_branch/$(echo ${pull_request} | jq -r .head.ref)"

git fetch origin
git checkout -b ${pr_branch}
git reset --hard origin/${backport_branch}
for commit in $(fetch_commits); do
    git cherry-pick $commit
done
git push -u origin ${pr_branch}

create_pr_body=$(echo ${pull_request} | jq "{title: (\"[BACKPORT] \" + .title), head: \"${pr_branch}\", base: \"${backport_branch}\", body: .body}")
echo "::debug::${create_pr_body}"
