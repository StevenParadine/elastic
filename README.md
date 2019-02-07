Code of resources/elasticsearch
Modified to run on OpenShift
added RUN chmod +x /opt/bin/start.sh to Dockerfile so that the script can be run

elasticsearch.yml
Modified:
${SOURCE_IP_ELASTIC_SEARCH_1_6_SERVICE_HOST}:${SOURCE_IP_ELASTIC_SEARCH_1_6_SERVICE_PORT} changes to ${ELASTIC_SERVICE_HOST}:${ELASTIC_SERVICE_PORT} where ELASTIC is the name of the app
Disabled: s3.backup in elasticsearch
Added:
transport.host: localhost
transport.tcp.port: 9300
http.port: 9200

start.sh
Disabled keystore s3 backup
