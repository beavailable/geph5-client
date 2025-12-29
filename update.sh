#!/usr/bin/bash
set -euo pipefail
shopt -s inherit_errexit

# $@: arguments
_curl() {
    local retries
    retries=0
    while true; do
        if curl -sSL --fail-early --fail-with-body --connect-timeout 10 "$@"; then
            break
        fi
        ((++retries))
        if [[ $retries -ge 3 ]]; then
            return 1
        fi
        sleep $((retries * 5))
    done
}

read -r version revision <<<$(sed -nE '1s/^\S+ \((\S+)-(\S+)\) .+$/\1 \2/p' debian/changelog)
new_version=''
tags=$(_curl "https://api.github.com/repos/geph-official/geph5/git/refs/tags" | sed -nE 's!^\s+"ref": "refs/tags/geph5-client-v(\S+)",$!\1!p' | tac)
for tag in $tags; do
    if [[ "$tag" == "$version" ]]; then
        break
    fi
    if dpkg --compare-versions "$tag" gt "$version"; then
        new_version="$tag"
        break
    fi
done

if [[ -n "$new_version" ]]; then
    new_version="$new_version-1"
elif [[ "${GEPH_FORCE_RELEASE:-}" == 'true' ]]; then
    new_version="$version-$((revision + 1))"
else
    exit 0
fi

changelog=$(cat debian/changelog)
{
    echo "geph5-client ($new_version) unstable; urgency=medium"
    echo
    echo '  * New release.'
    echo
    echo " -- beavailable <beavailable@proton.me>  $(date '+%a, %d %b %Y %H:%M:%S %z')"
    echo
    echo "$changelog"
} >debian/changelog

user='github-actions[bot]'
email='41898282+github-actions[bot]@users.noreply.github.com'
git -c user.name="$user" -c user.email="$email" commit -am "Release $new_version" --author "$GITHUB_ACTOR <$GITHUB_ACTOR_ID+$GITHUB_ACTOR@users.noreply.github.com>"
git -c user.name="$user" -c user.email="$email" tag "$new_version" -am "Release $new_version"
git push origin --follow-tags --atomic

echo "release-tag=geph5-client-v${new_version%-*}" >>$GITHUB_OUTPUT
