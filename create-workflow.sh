# This script creates an Aiven for Apache Kafka, an Aiven for Apache Flink and 4 pipelines for anomaly detection
# REQUIRES 
# - docker
# - An Aiven account (with a token generated)

# Load parameters (you need to create a params.conf file as copy of params.conf.sample and fill in the details)
. ./fakedatagen/params.conf

# Create Kafka
avn --auth-token $TOKEN service create demo-kafka               \
    -t kafka                                \
    --cloud google-europe-west3             \
    -p business-4                           \
    -c kafka.auto_create_topics_enable=true \
    -c kafka_connect=true                   \
    -c kafka_rest=true                      \
    -c schema_registry=true

# Create Flink
avn --auth-token $TOKEN service create demo-flink -t flink --cloud google-europe-west3 -p business-4

# Create Kafka Flink Integration
avn --auth-token $TOKEN service integration-create      \
    -t flink                        \
    -s demo-kafka                   \
    -d demo-flink

# Wait for the services to be up and running

avn --auth-token $TOKEN service wait demo-kafka 
avn --auth-token $TOKEN service wait demo-flink 


# remove folder if it exists
rm -rf fake-data-producer-for-apache-kafka-docker

# Clone repository for fake datagen
git clone https://github.com/aiven/fake-data-producer-for-apache-kafka-docker.git

# Navigate into the repository
cd fake-data-producer-for-apache-kafka-docker/
# Download the certificates
avn --auth-token $TOKEN service user-creds-download demo-kafka --username avnadmin -d certs
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

KAFKA_FLINK_SI=$(avn --auth-token $TOKEN service integration-list --json demo-kafka | jq -r '.[] | select(.dest == "demo-flink").service_integration_id')

# Create the first BasicFiltering application
avn --auth-token $TOKEN service flink create-application demo-flink \
    --project $PROJECT \
    "{\"name\":\"ex-1-BasicFiltering\"}"

APP_ID=$(avn --auth-token $TOKEN service flink list-applications demo-flink   \
    --project $PROJECT | jq -r '.applications[] | select(.name == "ex-1-BasicFiltering").id')

wait 30

mkdir -p tmp
sed "s/KAFKA_INTEGRATION_ID/$KAFKA_FLINK_SI/" 'flink-app/01-basic-filtering.json' > tmp/01-basic-filtering.json

avn --auth-token $TOKEN service flink create-application-version demo-flink   \
    --project $PROJECT                                    \
    --application-id $APP_ID                              \
    @tmp/01-basic-filtering.json 

APP_VERSION_1=$(avn --auth-token $TOKEN service flink get-application demo-flink \
    --project $PROJECT --application-id $APP_ID | jq -r '.application_versions[] | select(.version == 1).id')

avn --auth-token $TOKEN service flink create-application-deployment  demo-flink   \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  "{\"parallelism\": 1,\"restart_enabled\": true,  \"version_id\": \"$APP_VERSION_1\"}"

APP_DEPLOYMENT=$(avn --auth-token $TOKEN service flink list-application-deployments demo-flink       \
  --project $PROJECT                                                             \
  --application-id $APP_ID | jq  -r ".deployments[] | select(.version_id == \"$APP_VERSION_1\").id")


avn --auth-token $TOKEN service flink get-application-deployment demo-flink       \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  --deployment-id $APP_DEPLOYMENT | jq '.status'

# Create aggregations

avn --auth-token $TOKEN service flink create-application demo-flink \
    --project $PROJECT \
    "{\"name\":\"ex-2-Aggregating\"}"

APP_ID=$(avn --auth-token $TOKEN service flink list-applications demo-flink   \
    --project $PROJECT | jq -r '.applications[] | select(.name == "ex-2-Aggregating").id')

mkdir -p tmp
sed "s/KAFKA_INTEGRATION_ID/$KAFKA_FLINK_SI/" 'flink-app/02-aggregating.json' > tmp/02-aggregating.json

avn --auth-token $TOKEN service flink create-application-version demo-flink   \
    --project $PROJECT                                    \
    --application-id $APP_ID                              \
    @tmp/02-aggregating.json 

APP_VERSION_1=$(avn --auth-token $TOKEN service flink get-application demo-flink \
    --project $PROJECT --application-id $APP_ID | jq -r '.application_versions[] | select(.version == 1).id')

avn --auth-token $TOKEN service flink create-application-deployment  demo-flink   \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  "{\"parallelism\": 1,\"restart_enabled\": true,  \"version_id\": \"$APP_VERSION_1\"}"

APP_DEPLOYMENT=$(avn --auth-token $TOKEN service flink list-application-deployments demo-flink       \
  --project $PROJECT                                                             \
  --application-id $APP_ID | jq  -r ".deployments[] | select(.version_id == \"$APP_VERSION_1\").id")

avn --auth-token $TOKEN service flink get-application-deployment demo-flink       \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  --deployment-id $APP_DEPLOYMENT | jq '.status'

# Create windows

avn --auth-token $TOKEN service flink create-application demo-flink \
    --project $PROJECT \
    "{\"name\":\"ex-3-Windowing\"}"

APP_ID=$(avn --auth-token $TOKEN service flink list-applications demo-flink   \
    --project $PROJECT | jq -r '.applications[] | select(.name == "ex-3-Windowing").id')

mkdir -p tmp
sed "s/KAFKA_INTEGRATION_ID/$KAFKA_FLINK_SI/" 'flink-app/03-windowing.json' > tmp/03-windowing.json

avn --auth-token $TOKEN service flink create-application-version demo-flink   \
    --project $PROJECT                                    \
    --application-id $APP_ID                              \
    @tmp/03-windowing.json 

APP_VERSION_1=$(avn --auth-token $TOKEN service flink get-application demo-flink \
    --project $PROJECT --application-id $APP_ID | jq -r '.application_versions[] | select(.version == 1).id')

avn --auth-token $TOKEN service flink create-application-deployment  demo-flink   \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  "{\"parallelism\": 1,\"restart_enabled\": true,  \"version_id\": \"$APP_VERSION_1\"}"

APP_DEPLOYMENT=$(avn --auth-token $TOKEN service flink list-application-deployments demo-flink       \
  --project $PROJECT                                                             \
  --application-id $APP_ID | jq  -r ".deployments[] | select(.version_id == \"$APP_VERSION_1\").id")

avn --auth-token $TOKEN service flink get-application-deployment demo-flink       \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  --deployment-id $APP_DEPLOYMENT | jq '.status'

# Check for trends

avn --auth-token $TOKEN service flink create-application demo-flink \
    --project $PROJECT \
    "{\"name\":\"ex-4-Trends\"}"

APP_ID=$(avn --auth-token $TOKEN service flink list-applications demo-flink   \
    --project $PROJECT | jq -r '.applications[] | select(.name == "ex-4-Trends").id')

mkdir -p tmp
sed "s/KAFKA_INTEGRATION_ID/$KAFKA_FLINK_SI/" 'flink-app/04-trends.json' > tmp/04-trends.json

avn --auth-token $TOKEN service flink create-application-version demo-flink   \
    --project $PROJECT                                    \
    --application-id $APP_ID                              \
    @tmp/04-trends.json 

APP_VERSION_1=$(avn --auth-token $TOKEN service flink get-application demo-flink \
    --project $PROJECT --application-id $APP_ID | jq -r '.application_versions[] | select(.version == 1).id')

avn --auth-token $TOKEN service flink create-application-deployment  demo-flink   \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  "{\"parallelism\": 1,\"restart_enabled\": true,  \"version_id\": \"$APP_VERSION_1\"}"

APP_DEPLOYMENT=$(avn --auth-token $TOKEN service flink list-application-deployments demo-flink       \
  --project $PROJECT                                                             \
  --application-id $APP_ID | jq  -r ".deployments[] | select(.version_id == \"$APP_VERSION_1\").id")

avn --auth-token $TOKEN service flink get-application-deployment demo-flink       \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  --deployment-id $APP_DEPLOYMENT | jq '.status'

