FROM docker.elastic.co/elasticsearch/elasticsearch-oss:6.2.4

MAINTAINER Justin Smith <jjsmith@agiledigital.com.au>

RUN ./bin/elasticsearch-plugin install repository-s3
RUN ./bin/elasticsearch-plugin install https://github.com/Automattic/elasticsearch-statsd-plugin/releases/download/6.2.4.0/elasticsearch-statsd-6.2.4.0.zip

COPY start.sh /opt/bin/start.sh

COPY elasticsearch.yml /usr/share/elasticsearch/config/

COPY es_*.json /opt/data/

ENTRYPOINT ["/opt/bin/start.sh"]
