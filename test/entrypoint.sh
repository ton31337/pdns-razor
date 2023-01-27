#!/bin/sh

redis-server /etc/redis.conf &

cd /app ; crystal spec --error-trace

exit $?
