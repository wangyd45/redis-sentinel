FROM docker.io/centos:7.6.1810

ADD redis-5.0.4.tgz /opt/

COPY redis.conf /redis/conf/redis.conf
COPY run.sh /run.sh

RUN mkdir /redis/data && \
    touch /redis/conf/sentinel.conf && \
    chmod -R 777 /run.sh /redis && \
    ln -s /opt/redis-5.0.4/src/redis-cli /usr/bin/redis-cli && \
    ln -s /opt/redis-5.0.4/src/redis-server /usr/bin/redis-server && \
    ln -s /opt/redis-5.0.4/src/redis-sentinel /usr/bin/redis-sentinel


CMD [ "/run.sh" ]

ENTRYPOINT [ "bash", "-c" ]
