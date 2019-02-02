ESQ
===

`esq` aims to be a swiss army knife for quickly querying elasticsearch. It aims
to be useful for both ad-hoc analysis and for use in bash scripts.

While the ES query syntax is extremely powerful, it can be unfriendly and hard
to remember for developers.


Example Use
===========


1. select all ids and usenames from a 'user' index where the region field is "US". Hits `localhost:9200` by default.

    ```
    esq 'SELECT (id, name) FROM  users WHERE region == "US"'
    ```
