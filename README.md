# Install
```
$ shards install
$ shards update
$ crystal build razor.cr --release --no-debug
```

# Testing with docker
```
sudo ./docker/tests.sh
```

# Building binary with docker
```
sudo ./docker/build.sh
```

# Redis records

## Zone setup
```
HMSET node1.route.example.app.io:CONFIG SOA ...
HMSET node1.route.example.app.io:CONFIG TTL 3600
HMSET node1.route.example.app.io:CONFIG NS ns1.example.org,ns2.example.org
```
## Random
```
SADD node1.route.example.app.io:A 1.1.1.1 2.2.2.2 3.3.3.3
SADD node1.route.example.app.io:AAAA 2001::1 2001::2 2001::3
```
## Consistent Hashing
```
HMSET node1.route.example.app.io:CONFIG ANSWER consistent_hash
SADD node1.route.example.app.io:A 1.1.1.1 2.2.2.2 3.3.3.3
SADD node1.route.example.app.io:AAAA 2001::1 2001::2 2001::3
```
## Group Consistent hashing
```
HMSET node1.route.example.app.io:CONFIG ANSWER group_consistent_hash
SADD node1.route.example.app.io:GROUPS GROUP1 GROUP2
SADD GROUP1:A 192.168.1.1 192.168.1.2
SADD GROUP2:A 192.168.2.1 192.168.2.2
SADD GROUP1:AAAA 2001::1 2001::2
SADD GROUP2:AAAA 2002::1 2002::2
```
## GeoIP

This setup requires setting `zone` in `razor.json` to be like in this `routes.example.org`:
```
HMSET routes.example.org:CONFIG ANSWER geoip
HMSET routes.example.org:CONFIG SOA ...
HMSET routes.example.org:CONFIG TTL 3600
SADD routes.example.org:A 10.0.0.1 10.0.0.2
SADD routes.example.org:AAAA 2a02::1 2a02::2
SADD node1.route.example.app.io:A 1.1.1.1 2.2.2.2
SADD node1.route.example.app.io:AAAA 2001::1 2001::2
SADD node2.route.example.app.io:A 192.168.0.1 192.168.0.2
SADD node2.route.example.app.io:AAAA 2a02:4780::1 2a02:4780::2
SET geoip:eu:lt node1.route.example.app.io
SET geoip:eu node2.route.example.app.io
```

## Specifying IPv4/IPv6 ranges instead of plain hosts

You can specify the whole range like:
```
SADD routes.example.org:A 192.168.1.0/24 192.168.2.0/24
SADD routes.example.org:AAAA 2a02:4780:1::/48 2a02:4780:2::/48
```

And the Razor automatically picks up a random IPv4/IPv6 address from those ranges.

_Current limitation is that IPv4 subnet MUST be /24, and IPv6 /48_.

With this feature, you also have the ability to skip some specific hosts from being
returned by Razor to the client. It's called SKIPLIST. You define:
```
SADD example.org:A:SKIPLIST 192.168.1.100 192.168.2.255
SADD example.org:AAAA:SKIPLIST 2a02:4780:1:100::/64 2a02:4780:2:255::/64
```

Skip lists work by checking /32 for IPv4, and /64 for IPv6 addresses.

In this example, if the Razor picks the random IPv6 from 2a02:4780:2::/48, and
2a02:4780:2:255::/64 is defined as a skip-list item, then Razor picks another one
that is not _blocklisted_.

# Tests
```
# dnsperf -d data -n 10000
DNS Performance Testing Tool
Nominum Version 2.0.0.0

Statistics:

  Queries sent:         40000
  Queries completed:    40000 (100.00%)
  Queries lost:         0 (0.00%)

  Response codes:       NOERROR 40000 (100.00%)
  Average packet size:  request 27, response 49
  Run time (s):         0.551791
  Queries per second:   72491.214971

  Average Latency (s):  0.001175 (min 0.000487, max 0.011503)
  Latency StdDev (s):   0.000560
```
