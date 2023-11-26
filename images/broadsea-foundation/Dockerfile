# Use Ubuntu 22.04 (jammy) as the base image
FROM ubuntu:22.04

LABEL maintainer="Hayden Spence <haydenbspence@gmail.com>"

# Set the shell to use and switch to the root user
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
USER root

# Set environment variables and perform initial system setup
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update --yes && \
   apt-get upgrade --yes && \
   apt-get install --yes --no-install-recommends \
       ca-certificates \
       locales \
       sudo \
       curl && \
   apt-get clean && rm -rf /var/lib/apt/lists/* && \
   echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
   locale-gen

ENV LC_ALL=en_US.UTF-8 \
   LANG=en_US.UTF-8 \
   LANGUAGE=en_US.UTF-8
