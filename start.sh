#!/bin/bash -x

function wait_for_server() {
  until [ `curl -s -o /dev/null -w "%{http_code}" "http://localhost:9200" | grep -cim1 "200"` -ge 1 ]; do
    sleep 1
  done
}

# To avoid clusters sharing in docker land, lets see if we were given an ENVIRONMENT if so use that as suffix
# otherwise use the hostname to avoid sharing
if [ "${ENVIRONMENT}" != "" ]
then
  CLUSTER_NAME="source_ip_${ENVIRONMENT}"
else
  CLUSTER_NAME="source_ip_development"
  echo "ENVIRONMENT is not set, you should set this in elastic search and public-api to the same value to isolate the cluster. Using [${CLUSTER_NAME}] as default cluster name."
fi

echo "Setting Cluster Name to [${CLUSTER_NAME}]"
export CLUSTER_NAME


echo "Setting default config for search slowlog"
if [ "${SLOWLOG_TRACE_THRESHOLD}" == "" ]
then
  SLOWLOG_TRACE_THRESHOLD="-1"
  export SLOWLOG_TRACE_THRESHOLD
fi

if [ "${SLOWLOG_DEBUG_THRESHOLD}" == "" ]
then
  SLOWLOG_DEBUG_THRESHOLD="-1"
  export SLOWLOG_DEBUG_THRESHOLD
fi

if [ "${SLOWLOG_INFO_THRESHOLD}" == "" ]
then
  SLOWLOG_INFO_THRESHOLD="10ms"
  export SLOWLOG_INFO_THRESHOLD
fi

if [ "${SLOWLOG_WARN_THRESHOLD}" == "" ]
then
  SLOWLOG_WARN_THRESHOLD="100ms"
  export SLOWLOG_WARN_THRESHOLD
fi

if [ "${SLOWLOG_LEVEL}" == "" ]
then
  SLOWLOG_LEVEL="INFO"
  export SLOWLOG_LEVEL
fi


echo "Setting default config for statsd metrics"
if [ "${STATSD_HOST}" != "" ]
then
  STATSD_HOST="${STATSD_HOST}"
  echo "STATSD_HOST directly assigned from environment variables to [${STATSD_HOST}]."
else
  if [ "${SOURCE_IP_STATSD_PORT_8125_UDP_ADDR}" != "" ]
  then
    STATSD_HOST="${SOURCE_IP_STATSD_PORT_8125_UDP_ADDR}"
    echo "STATSD_HOST set based on docker-compose links to [${STATSD_HOST}]."
  else
    STATSD_HOST="localhost"
    echo "STATSD_HOST is not set, you will not receive any metrics from elastic search. Using [${STATSD_HOST}] as default host."
  fi
fi
export STATSD_HOST

if [ "${STATSD_PORT}" != "" ]
then
  STATSD_PORT="${STATSD_PORT}"
  echo "STATSD_PORT directly assigned from environment variables to [${STATSD_PORT}]."
else
  if [ "${SOURCE_IP_STATSD_PORT_8125_UDP_PORT}" != "" ]
  then
    STATSD_PORT="${SOURCE_IP_STATSD_PORT_8125_UDP_PORT}"
    echo "STATSD_PORT set based on docker-compose links to [${STATSD_PORT}]."
  else
    STATSD_PORT="8125"
    echo "STATSD_PORT is not set. Using [${STATSD_PORT}] as default host."
  fi
fi
export STATSD_PORT

if [ "${STATSD_UPDATE_EVERY}" == "" ]
then
  STATSD_UPDATE_EVERY="10s"
  export STATSD_UPDATE_EVERY
fi


elasticsearch &

echo "Waiting for elastic search..."

wait_for_server

echo "Server available"

if [ `curl -s -o /dev/null -w "%{http_code}" "http://localhost:9200/patent_listings" | grep -cim1 "404"` -ge 1 ]
then
  echo "Patent listings index not found, creating"
  curl -XPUT "http://localhost:9200/patent_listings" --upload-file /opt/data/patent_listings_mapping.json
fi

if [ `curl -s -o /dev/null -w "%{http_code}" "http://localhost:9200/_template/patents" | grep -cim1 "404"` -ge 1 ]
then
  echo "Patents template not found, creating"
  curl -XPUT "http://localhost:9200/_template/patents" --upload-file /opt/data/patent_template_mapping.json
fi

if [ `curl -s -o /dev/null -w "%{http_code}" "http://localhost:9200/_template/filings" | grep -cim1 "404"` -ge 1 ]
then
  echo "Raw filing data template not found, creating"
  curl -XPUT "http://localhost:9200/_template/filings" --upload-file /opt/data/filing_template_mapping.json
fi

if [ `curl -s -o /dev/null -w "%{http_code}" "http://localhost:9200/patents-dawn" | grep -cim1 "404"` -ge 1 ]
then
  echo "patents-dawn index not found, creating"
  curl -XPUT "http://localhost:9200/patents-dawn" # Will be based on patents template.
fi

if [ `curl -s -o /dev/null -w "%{http_code}" "http://localhost:9200/patents-recent" | grep -cim1 "404"` -ge 1 ]
then
  echo "patents-recent index not found, creating"
  curl -XPUT "http://localhost:9200/patents-recent" # Will be based on patents template.
fi

if [ `curl -s -o /dev/null -w "%{http_code}" "http://localhost:9200/patents-manual" | grep -cim1 "404"` -ge 1 ]
then
  echo "patents-manual index not found, creating"
  curl -XPUT "http://localhost:9200/patents-manual" # Will be based on patents template.
fi

if [ `curl -s -o /dev/null -w "%{http_code}" "http://localhost:9200/filings-wipo-dawn" | grep -cim1 "404"` -ge 1 ]
then
  echo "filings-wipo-dawn index not found, creating"
  curl -XPUT "http://localhost:9200/filings-wipo-dawn-v1" # Will be based on filing template.
  curl -XPOST "http://localhost:9200/_aliases" -d '{ "actions": [ { "add": { "index": "filings-wipo-dawn-v1", "alias": "filings-wipo-dawn" } } ] }'
fi

if [ `curl -s -o /dev/null -w "%{http_code}" "http://localhost:9200/filings-wipo-recent" | grep -cim1 "404"` -ge 1 ]
then
  echo "filings-wipo-recent index not found, creating"
  curl -XPUT "http://localhost:9200/filings-wipo-recent-v1" # Will be based on filing template.
  curl -XPOST "http://localhost:9200/_aliases" -d '{ "actions": [ { "add": { "index": "filings-wipo-recent-v1", "alias": "filings-wipo-recent" } } ] }'
fi

wait
