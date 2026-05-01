#!/usr/bin/bash
set -euo pipefail
shopt -s inherit_errexit

NEW_VERSION=''
NEW_REVISION=''

# $@: arguments
_curl() {
    local retries
    retries=0
    while true; do
        if curl -sSL --fail-early --fail-with-body --connect-timeout 10 -H "Authorization: Bearer $GITHUB_TOKEN" "$@"; then
            break
        fi
        ((++retries))
        if [[ $retries -ge 3 ]]; then
            return 1
        fi
        sleep $((retries * 5))
    done
}
fetch_new_version() {
    local version revision tags tag
    read -r version revision <<<$(sed -nE '1s/^\S+ \((\S+)-(\S+)\) .+$/\1 \2/p' debian/changelog)
    tags=$(_curl "https://api.github.com/repos/geph-official/geph5/git/refs/tags" | sed -nE 's!^\s+"ref": "refs/tags/geph5-client-v([0-9.]+)",$!\1!p' | sort -rV)
    for tag in $tags; do
        if [[ "$tag" == "$version" ]]; then
            break
        fi
        if dpkg --compare-versions "$tag" gt "$version"; then
            NEW_VERSION="$tag"
            break
        fi
    done

    if [[ -n "$NEW_VERSION" ]]; then
        NEW_REVISION='1'
    elif [[ "${ENV_FORCE_RELEASE:-}" == 'true' ]]; then
        NEW_VERSION="$version"
        NEW_REVISION=$((revision + 1))
    fi
}
release_new_version() {
    local changelog debian_version user email
    debian_version="$NEW_VERSION-$NEW_REVISION"
    changelog=$(cat debian/changelog)
    {
        echo "geph5-client ($debian_version) unstable; urgency=medium"
        echo
        echo '  * New release.'
        echo
        echo " -- beavailable <beavailable@proton.me>  $(date '+%a, %d %b %Y %H:%M:%S %z')"
        echo
        echo "$changelog"
    } >debian/changelog

    user='github-actions[bot]'
    email='41898282+github-actions[bot]@users.noreply.github.com'
    git -c user.name="$user" -c user.email="$email" commit -am "Release $debian_version" --author "$GITHUB_ACTOR <$GITHUB_ACTOR_ID+$GITHUB_ACTOR@users.noreply.github.com>"
    git -c user.name="$user" -c user.email="$email" tag "$debian_version" -am "Release $debian_version"
    git push origin --follow-tags --atomic
}

fetch_new_version
[[ -n "$NEW_VERSION" ]] || exit 0
release_new_version

echo "release-tag=geph5-client-v$NEW_VERSION" >>$GITHUB_OUTPUT
