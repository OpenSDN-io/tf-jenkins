FROM python:3.10.14

ENV GOSU_VERSION 1.11
ADD https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-amd64 /usr/local/bin/gosu
ADD https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-amd64.asc /usr/local/bin/gosu.asc
RUN gpg --keyserver keyserver.ubuntu.com --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
    && gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
    && chmod +x /usr/local/bin/gosu

# enable a simple init: https://github.com/krallin/tini
ENV TINI_VERSION v0.18.0
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /usr/local/bin/tini
ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini.asc /usr/local/bin/tini.asc
RUN gpg --keyserver keyserver.ubuntu.com --recv-keys 595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7 \
    && gpg --verify /usr/local/bin/tini.asc \
    && chmod +x /usr/local/bin/tini
ENTRYPOINT ["/usr/local/bin/tini", "--"]

ADD requirements.txt /requirements.txt
RUN pip install -r /requirements.txt
ADD pep-592.patch /tmp/pep-592.patch
WORKDIR /usr/local/lib/python3.7/site-packages/devpi_server
RUN git apply /tmp/pep-592.patch
WORKDIR /

VOLUME /devpi
ENV DEVPI_SERVERDIR /devpi/data
ENV DEVPI_USER www-data
#ENV SLACK_HOOK http://localhost/set-me-properly

ADD devpi-run.sh /devpi-run.sh
RUN chmod +x /devpi-run.sh

EXPOSE 3141
CMD ["/devpi-run.sh"]
