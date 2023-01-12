# Install
```
$ shards install
$ shards update
$ crystal build razor.cr --release --no-debug
```

# Redis records

## Zone setup
```
HMSET node1.route.example.app.io SOA "..."
HMSET node1.route.example.app.io TTL 3600
```
## Random
```
SADD node1.route.example.app.io:A 1.1.1.1 2.2.2.2 3.3.3.3
SADD node1.route.example.app.io:AAAA 2001::1 2001::2 2001::3
```
## Consistent Hashing
```
HMSET node1.route.example.app.io ANSWER consistent_hash
SADD node1.route.example.app.io:A 1.1.1.1 2.2.2.2 3.3.3.3
SADD node1.route.example.app.io:AAAA 2001::1 2001::2 2001::3
```
## Group Consistent hashing
```
HMSET node1.route.example.app.io ANSWER group_consistent_hash
SADD node1.route.example.app.io:GROUPS GROUP1 GROUP2
SADD GROUP1:A 192.168.1.1 192.168.1.2
SADD GROUP2:A 192.168.2.1 192.168.2.2
SADD GROUP1:AAAA 2001::1 2001::2
SADD GROUP2:AAAA 2002::1 2002::2
```

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
