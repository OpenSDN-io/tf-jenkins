FROM ubuntu:22.04

ENV TZ=Europe/Moscow

COPY entrypoint.sh /entrypoint.sh
COPY sync_docs.sh /sync_docs.sh

RUN apt-get update \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
    && apt-get install -y --no-install-recommends less git tox awscli cron curl \
    && chmod a+x /entrypoint.sh \
    && chmod a+x /sync_docs.sh

ENTRYPOINT ["/entrypoint.sh"]
