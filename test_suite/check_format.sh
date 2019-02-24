#!/usr/bin/env bash

make format

out=$(git status --porcelain -u no)

if [[ "$out" != "" ]]
then
  echo "format would change tracked files"
  echo "$out"
  exit 1
fi

exit 0
