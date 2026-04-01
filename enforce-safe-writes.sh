#!/bin/bash

zero="0000000000000000000000000000000000000000"
while read oldrev newrev refname; do
  # Block branch deletion (newrev is all zeros)
  if [ "$newrev" = "$zero" ]; then
    echo "ERROR: Deletion of '$refname' is not allowed remotely."
    exit 1
  fi

  # Block force pushes (non-fast-forward)
  if [ "$oldrev" != "$zero" ]; then
    if ! git merge-base --is-ancestor "$oldrev" "$newrev" 2>/dev/null; then
      echo "ERROR: Force push to '$refname' is not allowed remotely."
      exit 1
    fi
  fi

  # Block all pushes to refs/replace/ (silently rewrites apparent commit history)
  case "$refname" in
    refs/replace/*)
      echo "ERROR: Pushing to refs/replace/ is not allowed."
      exit 1
      ;;
  esac

  # Block updates to existing tags (tags must be immutable)
  case "$refname" in
    refs/tags/*)
      if [ "$oldrev" != "$zero" ]; then
        echo "ERROR: Updating existing tag '$refname' is not allowed."
        exit 1
      fi
      ;;
  esac
done
exit 0
