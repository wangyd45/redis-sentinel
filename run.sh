#!/bin/bash

# Copyright 2014 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

DOMAIN=`hostname -d`
eval sentinel_host=\${$(echo ${NAME}|tr 'a-z' 'A-Z')_SENTINEL_SERVICE_HOST}
master=$(redis-cli -a $REDIS_PASS -h ${sentinel_host} -p 26379 --csv SENTINEL get-master-addr-by-name mymaster | tr ',' ' ' | cut -d' ' -f1)
FIRST_REDIS_POD_HOST=$(ping ${NAME}-0.$DOMAIN -c 1 -w 1 | sed '1{s/[^(]*(//;s/).*//;q}')


function launchmaster() {
  sed -i "s/%redis-pass%/${REDIS_PASS}/" /redis/conf/redis.conf
  sed -i "s/%redis-port%/${REDIS_PORT}/" /redis/conf/redis.conf
  redis-server /redis/conf/redis.conf --protected-mode no
}

function launchsentinel() {
    REDIS_DOMAIN=`hostname -d |awk -F. '{$1="";print $0}'|sed 's/ /./g'`
    FIRST_REDIS_POD_HOST=$(ping ${NAME}-0.$NAME$REDIS_DOMAIN -c 1 -w 1 | sed '1{s/[^(]*(//;s/).*//;q}')

  while true; do
    master=$(redis-cli -a $REDIS_PASS -h ${sentinel_host} -p 26379 --csv SENTINEL get-master-addr-by-name mymaster | tr ',' ' ' | cut -d' ' -f1)
    if [[ -n ${master} ]]; then
      master="${master//\"}"
    else
      master=$FIRST_REDIS_POD_HOST
    fi

    redis-cli -a $REDIS_PASS -h ${master} -p ${REDIS_PORT} INFO
    if [[ "$?" == "0" ]]; then
      break
    fi
    echo "Connecting to master failed.  Waiting..."
    sleep 10
  done


  echo "sentinel monitor mymaster ${master} ${REDIS_PORT} 2" > /redis/conf/sentinel.conf
  echo "sentinel auth-pass mymaster ${REDIS_PASS}" >> /redis/conf/sentinel.conf
  echo "sentinel down-after-milliseconds mymaster 60000" >> /redis/conf/sentinel.conf
  echo "sentinel failover-timeout mymaster 180000" >> /redis/conf/sentinel.conf
  echo "sentinel parallel-syncs mymaster 1" >> /redis/conf/sentinel.conf
  echo "bind 0.0.0.0" >> /redis/conf/sentinel.conf

  redis-sentinel /redis/conf/sentinel.conf --protected-mode no
}

function launchslave() {
  while true; do
    master=$(redis-cli -a $REDIS_PASS -h ${sentinel_host} -p 26379 --csv SENTINEL get-master-addr-by-name mymaster | tr ',' ' ' | cut -d' ' -f1)
    if [[ -n ${master} ]]; then
      master="${master//\"}"
    else
      echo "Failed to find master."
      sleep 60
      exit 1
    fi 
    redis-cli -a $REDIS_PASS -h ${master} INFO
    if [[ "$?" == "0" ]]; then
      break
    fi
    echo "Connecting to master failed.  Waiting..."
    sleep 10
  done
  echo "slaveof ${master} ${REDIS_PORT}" >>  /redis/conf/redis.conf
  sed -i "s/%redis-pass%/${REDIS_PASS}/" /redis/conf/redis.conf
  sed -i "s/%redis-port%/${REDIS_PORT}/" /redis/conf/redis.conf
  redis-server /redis/conf/redis.conf --protected-mode no
}


if [[ -z ${master} ]]; then
  if [[ "$(hostname -i)" == "${FIRST_REDIS_POD_HOST}" ]]; then
    launchmaster
    exit 0
  fi
fi

#if [[ "$(hostname -i)" == "" ]]; then
#  launchmaster
#  exit 0
#fi

if [[ "${SENTINEL}" == "true" ]]; then
  launchsentinel
  exit 0
fi

launchslave
