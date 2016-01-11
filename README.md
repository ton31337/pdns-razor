# Install
```
$ shards install
$ crystal build razor.cr --release
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

  Queries sent:         20000
  Queries completed:    20000 (100.00%)
  Queries lost:         0 (0.00%)

  Response codes:       NOERROR 20000 (100.00%)
  Average packet size:  request 25, response 85
  Run time (s):         1.079667
  Queries per second:   18524.230156

  Average Latency (s):  0.005133 (min 0.000187, max 0.015157)
  Latency StdDev (s):   0.001977
```
