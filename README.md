# Install
```
$ shards install or crystal deps
$ crystal build razor.cr --release --no-debug
```

# Redis
```
set example.com node1.route.example.app.io
sadd node1.route.example.app.io:A 1.1.1.1 2.2.2.2 3.3.3.3
sadd node1.route.example.app.io:AAAA 2001::1 2001::2 2001::3
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
