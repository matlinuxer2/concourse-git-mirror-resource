ARG base_image=alpine:latest

FROM ${base_image} AS resource

RUN apk update && apk upgrade
RUN apk --no-cache add \
  bash \
  curl \
  git \
  git-daemon \
  git-lfs \
  gnupg \
  gzip \
  jq \
  openssl-dev \
  make \
  g++ \
  openssh \
  perl \
  tar \
  libstdc++ \
  coreutils

WORKDIR /root

RUN git config --global user.email "git@localhost"
RUN git config --global user.name "git"

ADD assets/ /opt/resource/
RUN chmod +x /opt/resource/*

FROM resource
