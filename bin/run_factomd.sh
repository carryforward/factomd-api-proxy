#!/usr/bin/env bash

docker stop factomd

docker rm factomd

docker run -d --name factomd \
  -p 8088:8088 -p 8090:8090 -p 8108:8108 \
  -v $(pwd)/scratch/factomd/config:/app/config \
  -v $(pwd)/scratch/factomd/config:/app/config \
  bedrocksolutions/factomd:v6.4.3-alpine

docker logs -f factomd
