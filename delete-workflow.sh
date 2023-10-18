avn service terminate demo-kafka --force
avn service terminate demo-flink --force
docker stop $(docker ps -a -q --filter ancestor=fake-data-producer-for-apache-kafka-docker --format="{{.ID}}")