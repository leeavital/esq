#!/usr/bin/env bash

set -eo pipefail

function do_curl  {
  set -e
  curl  "$@"
}

function index {
  json="$1"

  do_curl http://localhost:9200/people/person -XPOST -H "Content-Type: application/json" -d "$json"
  echo "indexed $json\n\n"
}

do_curl http://localhost:9200/people -XDELETE
echo "deleted index"

do_curl http://localhost:9200/people -XPUT
echo "created index"


json=$(cat <<EOD
{
  "properties": {
    "favoriteColor": {
      "type": "keyword"
    },
    "username": {
      "type": "keyword"
    },
    "locale": {
      "type": "keyword"
    },
    "birthyear": {
      "type": "number"
    }
  }
}
EOD
)

do_curl http://localhost:9200/people/_mapping/person -H "Content-Type: application/json" -d "$json"
m=$(echo $json | jq -c .)
echo "put field mappings: $m"

index '{ "type": "person", "favoriteColor": "red", "username": "John", "locale": "UK", "birthyear":  1940 }'
index '{ "type": "person", "favoriteColor": "blue", "username": "Paul", "locale": "UK", "birthyear": 1942 }'
index '{ "type": "person", "favoriteColor": "orange", "username": "George", "locale": "UK", "birthyear": 1943 }'
index '{ "type": "person", "favoriteColor": "red", "username": "Ringo", "locale": "UK", "birthyear": 1940 }'
