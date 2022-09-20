#! /usr/bin/env bash
mkdir -p _repos
while read -r repo; do
    # github.com/x/y 
    # extract REPO=y; REPO_DIR=_repos/y
    REPO=$(basename "$repo")
    REPO_DIR="_repos/${REPO}"

    # we'll need local copies of the repos;
    # either clone or fetch.
    if [[ -d "${REPO_DIR}" ]]; then
        echo "Fetching ${REPO}..."
        (cd "${REPO_DIR}" && git fetch --all)
    else
        echo "Cloning ${REPO}..."
        (cd _repos && git clone -q "$repo")
    fi

    # if the repo is one of the special -packages hackage repo,
    # let's just reset them. So we only add ontop of the
    # recent state.
    if [[ "${REPO}" == *-packages ]]; then 
        git -C "${REPO_DIR}" reset --hard origin
    else 
        # iterate over all tags, we want to look for
        # 
        #   <custom hackage>/rev/<number>
        #
        # extract the number, and then use the `add-to-github.sh`
        # script to create the necessary packages.
        #
        for tag in $(git -C "${REPO_DIR}" tag -l); do
            # ignore known tags
            if ! grep -q "${REPO} $tag" known_tags; then
                # hardcoded custom hackages for now
                for target in ghc-next-packages cardano-haskell-packages; do
                    case "$tag" in
                        $target/rev/*)
                            git -C "${REPO_DIR}" reset --hard "$tag"
                            REV=$(git -C "${REPO_DIR}" rev-parse "$tag")
                            echo "Found $tag @ $REV in ${REPO}; creating packages in $target..."

                            # for all paths that contain .cabal files...
                            while read -r subdir; do
                                if [[ $subdir == "." ]]; then 
                                    # if the path is ./. just add the root directory
                                    (cd "_repos/$target" && ./scripts/add-from-github.sh -r "$(basename "$tag")" "$repo" "$REV")
                                else
                                    # if it's not, add the subdirectory
                                    (cd "_repos/$target" && ./scripts/add-from-github.sh -r "$(basename "$tag")" "$repo" "$REV" "$subdir")
                                fi
                            done <<<"$(cd "${REPO_DIR}" && find . -name "*.cabal" -exec dirname {} \; | sort | uniq)"

                            # store the tag in the known_tags file
                            echo "${REPO} $tag $REV" >> known_tags
                            ;;
                        $target/release/*)
                            echo "No Support for relases yet... ${REPO} $tag"
                            ;;
                    esac
                done
            fi
        done
    fi
done <<<"$(grep -v -e '^[[:space:]]*$' -e '^#' repos)"

# and now for the crazy part! Push the updated hackages
for target in ghc-next-packages; do
    git -C "_repos/$target" push
done
