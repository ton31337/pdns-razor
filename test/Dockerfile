FROM alpine:3.17

RUN apk add crystal shards redis
RUN sed -i 's/^unixsocketperm \d\+/unixsocketperm 777/' /etc/redis.conf
RUN sed -i 's/^unixsocket \/run\/redis\/redis.sock/unixsocket \/tmp\/redis.sock/' /etc/redis.conf
RUN mkdir /app
COPY . /app
WORKDIR /app
RUN shards install

CMD ./test/entrypoint.sh
