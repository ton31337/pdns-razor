#!/bin/sh

redis-server /etc/redis.conf &

cd /app && \
    crystal spec spec/razor_geoip_spec.cr --error-trace && \
    crystal spec spec/razor_txt_tracing_spec.cr --error-trace

exit $?
