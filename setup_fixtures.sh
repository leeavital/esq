#!/usr/bin/env bash

set -eo pipefail

function do_curl  {
  curl --silent --output /dev/null "$@"
}

function index {
  json="$1"

  do_curl http://localhost:9200/people/_doc -XPOST -H "Content-Type: application/json" -d "$json"
  echo "indexed $json"
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
    }
  }
}
EOD
)

do_curl http://localhost:9200/people/_mapping/_doc -H "Content-Type: application/json" -d "$json"
m=$(echo $json | jq -c .)
echo "put field mappings: $m"

index '{ "type": "person", "favoriteColor": "red", "username": "John", "locale": "UK" }'
index '{ "type": "person", "favoriteColor": "blue", "username": "Paul", "locale": "UK" }'
index '{ "type": "person", "favoriteColor": "orange", "username": "George", "locale": "UK" }'
index '{ "type": "person", "favoriteColor": "red", "username": "Ringo", "locale": "UK" }'
