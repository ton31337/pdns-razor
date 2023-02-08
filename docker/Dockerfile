FROM alpine:3.17 as razor-tests
RUN apk add crystal shards redis openssl-dev
RUN sed -i 's/^unixsocketperm \d\+/unixsocketperm 777/' /etc/redis.conf
RUN sed -i 's/^unixsocket \/run\/redis\/redis.sock/unixsocket \/tmp\/redis.sock/' /etc/redis.conf
RUN mkdir /app
COPY . /app
WORKDIR /app
RUN shards install
CMD ./docker/entrypoint.sh

FROM rockylinux:8 as razor-build-rockylinux8
RUN curl -fsSL https://crystal-lang.org/install.sh | bash
RUN dnf install -y crystal git openssl-devel gmp-devel
RUN mkdir /app
COPY . /app
WORKDIR /app
RUN shards install
RUN crystal build razor.cr --release --no-debug -o razor-rockylinux8
