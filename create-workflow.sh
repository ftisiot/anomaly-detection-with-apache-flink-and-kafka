# This script creates an Aiven for Apache Kafka, an Aiven for Apache Flink and 4 pipelines for anomaly detection
# REQUIRES 
# - docker
# - An Aiven account (with a token generated)

# Load parameters (you need to create a params.conf file as copy of params.conf.sample and fill in the details)
. ./fakedatagen/params.conf

# Create Kafka
avn service create demo-kafka               \
    -t kafka                                \
    --cloud google-europe-west3             \
    -p business-4                           \
    -c kafka.auto_create_topics_enable=true \
    -c kafka_connect=true                   \
    -c kafka_rest=true                      \
    -c schema_registry=true

# Create Flink
avn service create demo-flink -t flink --cloud google-europe-west3 -p business-4

# Create Kafka Flink Integration
avn service integration-create      \
    -t flink                        \
    -s demo-kafka                   \
    -d demo-flink

# Wait for the services to be up and running

avn service wait demo-kafka 
avn service wait demo-flink 


# remove folder if it exists
rm -rf fake-data-producer-for-apache-kafka-docker

# Clone repository for fake datagen
git clone https://github.com/aiven/fake-data-producer-for-apache-kafka-docker.git

# Navigate into the repository
cd fake-data-producer-for-apache-kafka-docker/
# Download the certificates
avn service user-creds-download demo-kafka --username avnadmin -d certs
cp ../fakedatagen/env.conf ./conf/env.conf

# Replace placeholders
cd conf
sed "s/AIVEN_PROJECT/$PROJECT/" env.conf > env.conf.work
sed "s/AIVEN_EMAIL/$EMAIL/" env.conf.work > env.conf.work.1
sed "s]AIVEN_TOKEN]$TOKEN]" env.conf.work.1 > env.conf.work.2
mv env.conf.work.2 env.conf
rm env.conf.work
rm env.conf.work.1

# Go to main Docker folder

cd ..
docker build -t fake-data-producer-for-apache-kafka-docker .
docker run -d fake-data-producer-for-apache-kafka-docker

# Go to main folder
cd ..

# Retrieve the integration id

KAFKA_FLINK_SI=$(avn service integration-list --json demo-kafka | jq -r '.[] | select(.dest == "demo-flink").service_integration_id')

# Create the first BasicFiltering application
avn service flink create-application demo-flink \
    --project $PROJECT \
    "{\"name\":\"BasicFiltering\"}"

APP_ID=$(avn service flink list-applications demo-flink   \
    --project $PROJECT | jq -r '.applications[] | select(.name == "BasicFiltering").id')

wait 30

mkdir -p tmp
sed "s/KAFKA_INTEGRATION_ID/$KAFKA_FLINK_SI/" 'flink-app/01-basic-filtering.json' > tmp/01-basic-filtering.json

avn service flink create-application-version demo-flink   \
    --project $PROJECT                                    \
    --application-id $APP_ID                              \
    @tmp/01-basic-filtering.json 

APP_VERSION_1=$(avn service flink get-application demo-flink \
    --project $PROJECT --application-id $APP_ID | jq -r '.application_versions[] | select(.version == 1).id')

avn service flink create-application-deployment  demo-flink   \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  "{\"parallelism\": 1,\"restart_enabled\": true,  \"version_id\": \"$APP_VERSION_1\"}"

APP_DEPLOYMENT=$(avn service flink list-application-deployments demo-flink       \
  --project $PROJECT                                                             \
  --application-id $APP_ID | jq  -r ".deployments[] | select(.version_id == \"$APP_VERSION_1\").id")


avn service flink get-application-deployment demo-flink       \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  --deployment-id $APP_DEPLOYMENT | jq '.status'

# Create aggregations

avn service flink create-application demo-flink \
    --project $PROJECT \
    "{\"name\":\"Aggregating\"}"

APP_ID=$(avn service flink list-applications demo-flink   \
    --project $PROJECT | jq -r '.applications[] | select(.name == "Aggregating").id')

mkdir -p tmp
sed "s/KAFKA_INTEGRATION_ID/$KAFKA_FLINK_SI/" 'flink-app/02-aggregating.json' > tmp/02-aggregating.json

avn service flink create-application-version demo-flink   \
    --project $PROJECT                                    \
    --application-id $APP_ID                              \
    @tmp/02-aggregating.json 

APP_VERSION_1=$(avn service flink get-application demo-flink \
    --project $PROJECT --application-id $APP_ID | jq -r '.application_versions[] | select(.version == 1).id')

avn service flink create-application-deployment  demo-flink   \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  "{\"parallelism\": 1,\"restart_enabled\": true,  \"version_id\": \"$APP_VERSION_1\"}"

APP_DEPLOYMENT=$(avn service flink list-application-deployments demo-flink       \
  --project $PROJECT                                                             \
  --application-id $APP_ID | jq  -r ".deployments[] | select(.version_id == \"$APP_VERSION_1\").id")

avn service flink get-application-deployment demo-flink       \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  --deployment-id $APP_DEPLOYMENT | jq '.status'

# Create windows

avn service flink create-application demo-flink \
    --project $PROJECT \
    "{\"name\":\"Windowing\"}"

APP_ID=$(avn service flink list-applications demo-flink   \
    --project $PROJECT | jq -r '.applications[] | select(.name == "Windowing").id')

mkdir -p tmp
sed "s/KAFKA_INTEGRATION_ID/$KAFKA_FLINK_SI/" 'flink-app/03-windowing.json' > tmp/03-windowing.json

avn service flink create-application-version demo-flink   \
    --project $PROJECT                                    \
    --application-id $APP_ID                              \
    @tmp/03-windowing.json 

APP_VERSION_1=$(avn service flink get-application demo-flink \
    --project $PROJECT --application-id $APP_ID | jq -r '.application_versions[] | select(.version == 1).id')

avn service flink create-application-deployment  demo-flink   \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  "{\"parallelism\": 1,\"restart_enabled\": true,  \"version_id\": \"$APP_VERSION_1\"}"

APP_DEPLOYMENT=$(avn service flink list-application-deployments demo-flink       \
  --project $PROJECT                                                             \
  --application-id $APP_ID | jq  -r ".deployments[] | select(.version_id == \"$APP_VERSION_1\").id")

avn service flink get-application-deployment demo-flink       \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  --deployment-id $APP_DEPLOYMENT | jq '.status'

# Check for trends

avn service flink create-application demo-flink \
    --project $PROJECT \
    "{\"name\":\"Trends\"}"

APP_ID=$(avn service flink list-applications demo-flink   \
    --project $PROJECT | jq -r '.applications[] | select(.name == "Trends").id')

mkdir -p tmp
sed "s/KAFKA_INTEGRATION_ID/$KAFKA_FLINK_SI/" 'flink-app/04-trends.json' > tmp/04-trends.json

avn service flink create-application-version demo-flink   \
    --project $PROJECT                                    \
    --application-id $APP_ID                              \
    @tmp/04-trends.json 

APP_VERSION_1=$(avn service flink get-application demo-flink \
    --project $PROJECT --application-id $APP_ID | jq -r '.application_versions[] | select(.version == 1).id')

avn service flink create-application-deployment  demo-flink   \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  "{\"parallelism\": 1,\"restart_enabled\": true,  \"version_id\": \"$APP_VERSION_1\"}"

APP_DEPLOYMENT=$(avn service flink list-application-deployments demo-flink       \
  --project $PROJECT                                                             \
  --application-id $APP_ID | jq  -r ".deployments[] | select(.version_id == \"$APP_VERSION_1\").id")

avn service flink get-application-deployment demo-flink       \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  --deployment-id $APP_DEPLOYMENT | jq '.status'

