#!/bin/bash -e

set -o pipefail

check_env() {
    if [ -z "${!1}" ]; then
        echo "Error: environment variable $1 is not set" >&2
        exit 1
    fi
}

check_command() {
    if ! [ -x "$(command -v $1)" ]; then
      echo "Error: command $1 is not available." >&2
      exit 1
    fi
}

check_env GITHUB_REPOSITORY
check_env GITHUB_EVENT_PATH
check_env GITHUB_TOKEN
check_command curl
check_command jq

set -u

fetch() {
  curl -sL -H "Authorization: token ${GITHUB_TOKEN}" "https://api.github.com${1}"
}

pr_json() {
    fetch /repos/${GITHUB_REPOSITORY}/pulls/3719
}

commits() {
    fetch /repos/${GITHUB_REPOSITORY}/pulls/3719/commits | jq -r .[].sha
}

pull_request=$(pr_json)

# TODO parse comment
backport_branch=0.22
pr_branch="backport/$backport_branch/$(echo ${pull_request} | jq -r .head.ref)"

git fetch origin
git checkout -b ${pr_branch}
git reset --hard origin/${backport_branch}
for commit in $(commits); do
    git cherry-pick $commit
done
git push -u origin ${pr_branch}

echo ${pull_request} | jq "{title: (\"[BACKPORT] \" + .title), head: \"${pr_branch}\", base: \"${backport_branch}\", body: .body}"

