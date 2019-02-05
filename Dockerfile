FROM elasticsearch:1.6

MAINTAINER Justin Smith <jjsmith@agiledigital.com.au>

RUN plugin --install mobz/elasticsearch-head && plugin -install karmi/elasticsearch-paramedic && plugin -install lukas-vlcek/bigdesk/2.5.0 && plugin --install elasticsearch/elasticsearch-cloud-aws/2.6.1

RUN plugin --install statsd -url https://github.com/Automattic/elasticsearch-statsd-plugin/releases/download/v0.4.0/elasticsearch-statsd-0.4.0.zip

COPY start.sh /opt/bin/start.sh

COPY elasticsearch.yml /usr/share/elasticsearch/config/

COPY patent_listings_mapping.json /opt/data/patent_listings_mapping.json

COPY patent_template_mapping.json /opt/data/patent_template_mapping.json

COPY filing_template_mapping.json /opt/data/filing_template_mapping.json

ENTRYPOINT ["/opt/bin/start.sh"]
