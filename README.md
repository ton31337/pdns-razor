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
