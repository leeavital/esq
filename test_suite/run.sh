#!/usr/bin/env bash

set -e

pushd "$(dirname $0)/.." > /dev/null
dub build --build=release
export PATH=$PATH:$PWD
popd > /dev/null

pushd "$(dirname $0)" > /dev/null
dirs=$(find . -maxdepth 1 -type d -not -name '.')

set +e

for d in $dirs
do
  echo "testing $d"
  source $d/command.sh > $d/actual.out 2> $d/actual.err

  err_diff=$(diff $d/actual.err $d/expected.err)
  if [[ "$?" != "0" ]]
  then
    echo "stderr did not match"
    echo "$err_diff"
  fi

  out_diff=$(diff $d/actual.out $d/expected.out)
  if [[ "$?" != "0" ]]
  then
    echo "stdout did not match"
    echo "$out_diff"
  fi
done

popd > /dev/null
