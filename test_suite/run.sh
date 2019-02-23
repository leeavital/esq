#!/usr/bin/env bash

set -e

pushd "$(dirname "$0")/.." > /dev/null
dub build --build=release
export PATH=$PATH:$PWD
popd > /dev/null

pushd "$(dirname "$0")" > /dev/null
dirs=$(find . -maxdepth 1 -type d -not -name '.')

set +e

failed=no

# TODO: it would be really nice to have a flag that assumed that the executable was right, and
# filled out all of the actual.{err,out} files for me to code review quickly. Updating these test
# cases could become really tedious
for d in $dirs
do
  echo "testing $d"
  # shellcheck source=/dev/null
  source "$d/command.sh" > "$d/actual.out" 2> "$d/actual.err"

  if ! err_diff=$(diff "$d/actual.err" "$d/expected.err")
  then
    echo "stderr did not match when diffing $(readlink -f $d/actual.err) and $(readlink -f $d/expected.err)"
    echo "$err_diff"
    failed=yes
  fi

  if ! out_diff=$(diff "$d/actual.out" "$d/expected.out")
  then
    echo "stdout did not match when diffing $(readlink -f $d/actual.out) and $(readlink -f $d/expected.out)"
    echo "$out_diff"
    failed=yes
  fi
done

popd > /dev/null

if [[ "$failed" = "yes" ]]
then
  exit 1
fi
