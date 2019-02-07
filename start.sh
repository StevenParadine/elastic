#!/bin/bash -x

function wait_for_server() {
  until [ `curl --silent --output /dev/null --write-out "%{http_code}" "http://localhost:9200" | grep -cim1 "200"` -ge 1 ]; do
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
  echo "ENVIRONMENT is not set, you should set this in elasticsearch and public-api to the same value to isolate the cluster. Using [${CLUSTER_NAME}] as default cluster name."
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
    echo "STATSD_HOST is not set, you will not receive any metrics from elasticsearch. Using [${STATSD_HOST}] as default host."
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

# Create the keystore and add the AWS credentials into it.
# The keystore must be created before starting elasticsearch, otherwise changes will not be registered until ES restarts
#echo "Creating elasticsearch keystore"
#bin/elasticsearch-keystore create

#echo "Configuring AWS credentials"
# These credentials will come in from secrets from openshift
# In the staging environment this will be readonly for restoring live backups.
# In the live environment this will be write access for creating backups.
# --force is used to ensure the value is overridden from environment.
#echo ${S3_CLIENT_ACCESS_KEY} | bin/elasticsearch-keystore add --stdin --force s3.client.s3_backup.access_key
#echo ${S3_CLIENT_SECRET_KEY} | bin/elasticsearch-keystore add --stdin --force s3.client.s3_backup.secret_key

/usr/local/bin/docker-entrypoint.sh &

echo "Waiting for elasticsearch..."

wait_for_server

echo "Server available"

# Now that the key store is setup and configured, add the s3 repository to elasticsearch.
echo "Configuring S3 repository for backups"
curl -XPUT 'http://localhost:9200/_snapshot/s3_backup' --header "Content-Type: application/json" -d '{
  "type": "s3",
  "settings": {
    "client": "s3_backup",
    "bucket": "sourceip-automated-backups",
    "base_path": "elasticsearch"
  }
}'


# Add in the elasticsearch indexes we need for the SourceIP project.
if [ `curl --silent --output /dev/null --write-out "%{http_code}" "http://localhost:9200/_template/all" | grep -cim1 "404"` -ge 1 ]
then
  echo "Global template not found, creating"
  curl --request PUT --header "Content-Type: application/json" --upload-file /opt/data/es_template_all.json "http://localhost:9200/_template/all"
fi

if [ `curl --silent --output /dev/null --write-out "%{http_code}" "http://localhost:9200/_template/patents" | grep -cim1 "404"` -ge 1 ]
then
  echo "Patents template not found, creating"
  curl --request PUT --header "Content-Type: application/json" --upload-file /opt/data/es_template_patents.json "http://localhost:9200/_template/patents"
fi

if [ `curl --silent --output /dev/null --write-out "%{http_code}" "http://localhost:9200/_template/filings" | grep -cim1 "404"` -ge 1 ]
then
  echo "Raw filing data template not found, creating"
  curl --request PUT --header "Content-Type: application/json" --upload-file /opt/data/es_template_filings.json "http://localhost:9200/_template/filings"
fi

if [ `curl --silent --output /dev/null --write-out "%{http_code}" "http://localhost:9200/patent_listings" | grep -cim1 "404"` -ge 1 ]
then
  echo "Patent listings index not found, creating"
  curl --request PUT --header "Content-Type: application/json" --upload-file /opt/data/es_index_patent_listings.json "http://localhost:9200/patent_listings"
fi

if [ `curl --silent --output /dev/null --write-out "%{http_code}" "http://localhost:9200/patent_listings_global" | grep -cim1 "404"` -ge 1 ]
then
  echo "Global patent listings index not found, creating"
  curl --request PUT --header "Content-Type: application/json" --upload-file /opt/data/es_index_patent_listings_global.json "http://localhost:9200/patent_listings_global"
fi

# A common pattern here is to create two structurally-identical indices, *-dawn and *-recent.
# This is purely to improve recovery time in case of node failure/crash.
# A heuristic is used to choose which index a filing belongs in, based on its filing ID string.
# * It creates a deterministic mapping from filing ID to index.
# * It tends to place "old" patents in the *-dawn index, and "new" patents in the *-recent index,
#   but it is not guaranteed to be that way.

# Indices for data from AusPat, IP Australia's patent database.
if [ `curl --silent --output /dev/null --write-out "%{http_code}" "http://localhost:9200/patents-dawn" | grep -cim1 "404"` -ge 1 ]
then
  echo "patents-dawn index not found, creating"
  curl --request PUT "http://localhost:9200/patents-dawn" # Will be based on patents template.
fi

if [ `curl --silent --output /dev/null --write-out "%{http_code}" "http://localhost:9200/patents-recent" | grep -cim1 "404"` -ge 1 ]
then
  echo "patents-recent index not found, creating"
  curl --request PUT "http://localhost:9200/patents-recent" # Will be based on patents template.
fi

# Index for manually-added patents, structurally identical to the AusPat indices.
if [ `curl --silent --output /dev/null --write-out "%{http_code}" "http://localhost:9200/patents-manual" | grep -cim1 "404"` -ge 1 ]
then
  echo "patents-manual index not found, creating"
  curl --request PUT "http://localhost:9200/patents-manual" # Will be based on patents template.
fi

# Indices for data from PATENTSCOPE, WIPO's patent database.
if [ `curl --silent --output /dev/null --write-out "%{http_code}" "http://localhost:9200/filings-wipo-dawn" | grep -cim1 "404"` -ge 1 ]
then
  echo "filings-wipo-dawn index not found, creating"
  curl --request PUT "http://localhost:9200/filings-wipo-dawn-v1" # Will be based on filings template.
  curl --request PUT "http://localhost:9200/filings-wipo-dawn-v1/_alias/filings-wipo-dawn"
fi

if [ `curl --silent --output /dev/null --write-out "%{http_code}" "http://localhost:9200/filings-wipo-recent" | grep -cim1 "404"` -ge 1 ]
then
  echo "filings-wipo-recent index not found, creating"
  curl --request PUT "http://localhost:9200/filings-wipo-recent-v1" # Will be based on filings template.
  curl --request PUT "http://localhost:9200/filings-wipo-recent-v1/_alias/filings-wipo-recent"
fi

# Indices for data from DOCDB, EPO's patent database.
if [ `curl --silent --output /dev/null --write-out "%{http_code}" "http://localhost:9200/filings-docdb-all" | grep -cim1 "404"` -ge 1 ]
then
  echo "filings-docdb-all index not found, creating"
  curl --request PUT "http://localhost:9200/filings-docdb-all-v1" # Will be based on filings template.
  curl --request PUT "http://localhost:9200/filings-docdb-all-v1/_alias/filings-docdb-all"
fi

wait

