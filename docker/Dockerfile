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

FROM debian:11 as razor-build-debian11
RUN apt update -y
RUN apt install curl -y
RUN curl -fsSL https://crystal-lang.org/install.sh | bash
RUN apt install -y crystal git libssl-dev libgmp-dev
RUN mkdir /app
COPY . /app
WORKDIR /app
RUN shards install
RUN crystal build razor.cr --release --no-debug -o razor-debian11
