#!/usr/bin/env bash

pushd "$(dirname $0)/.."
dub build --build=release
export PATH=$PATH:$PWD
popd

pushd "$(dirname $0)"
dirs=$(find . -maxdepth 1 -type d -not -name '.')

for d in $dirs
do
  source $d/command.sh > $d/actual.out 2> $d/actual.err
done

popd
