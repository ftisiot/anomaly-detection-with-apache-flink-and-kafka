# Load parameters (you need to create a params.conf file as copy of params.conf.sample and fill in the details)
. ./fakedatagen/params.conf

avn --auth-token $TOKEN service terminate demo-kafka --force
avn --auth-token $TOKEN service terminate demo-flink --force
docker stop $(docker ps -a -q --filter ancestor=fake-data-producer-for-apache-kafka-docker --format="{{.ID}}")