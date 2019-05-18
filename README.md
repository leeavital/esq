ESQ
===

[![Build Status](https://travis-ci.org/leeavital/esq.svg?branch=master)](https://travis-ci.org/leeavital/esq)

`esq` is your swiss army knife for quick and dirty elasticsearch. It aims
to be useful for both ad-hoc day to day operations and for use in shell scripts.

By emitting `curl` commands, `esq` can be used without being installed on a
client machine, and even without HTTP access to the host where elasticsearch is
running. If you have a terminal session, you can pipe or copy the output of `esq`
into it. For example `esq 'SELECT FROM "myindex" LIMIT 10' | ssh myelasticsearchhost` or
`esq 'SELECT FROM "myindex" LIMIT 10' | kubectl exec -it myelasticsearchtoolbox`.

While the ES query syntax is extremely powerful, it can be unfriendly. It's
hard to remember the exact syntax if you're writing not writing queries every day.

Newer versions of Elasticsearch ship with [a SQL interface](https://www.elastic.co/products/stack/elasticsearch-sql), but:
- it is not always enabled
- not everyone is running the latest and greatest elasticsearch

The following is an inexhaustive list of what you might do with `esq` (\* denotes not implemented yet):

- Check that documents do or do not exist for a certain query
- Delete documents that match a certain search (\*)
- Alter index settings
- See how many documents fall into buckets (e.g. count `users` by `country` field) (\*)

Example Use
===========


1. select the usernames of people whose locale is not US and whose usernames are neither John nor Ringo

    ```
    esq 'SELECT username FROM people WHERE locale != "US" AND (username = "John" OR username = "Ringo") '
    ```

1. select a list of user IDs ordered by username in descending order from a remote host

    ```
    esq 'SELECT id FROM users WHERE region = 'US' ORDER BY username DESC'
    ```

1. alter index settings

    ```
    esq 'ALTER INDEX "users" "index.refresh_interval" = "1s"'
    ```

1. bucket users by favorite color

   ```
   esq 'SELECT DISTINCT favoriteColor FROM people'
   ```


1. count the number of unique favorite colors in the people index

  ```
  esq 'SELECT COUNT DISTINCT favoriteColor FROM people'
  ```

1. select any 10 documents using a URL different than localhost:9200

  ```
  esq 'SELECT * FROM * LIMIT 10 ON HOST remote.elasticsearch.host:4040'
  ```

Build and Install
==================

Requirements:

- A working D build environment (download from https://dlang.org/ or your systems package manager)
- `make`

Run `make esq` to build a binary
Run `make install` to build and install
