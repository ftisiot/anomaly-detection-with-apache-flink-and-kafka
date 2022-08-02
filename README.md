Streaming Anomaly Detection with Apache Flink® and Apache Kafka®
================================================================

This is demo repository showing how to create a streaming anomaly detection system using Apache Kafka® and Apache Flink®.


Overview
========

The repository shows a silly pizza example, based on a python [Fake data producer](https://github.com/aiven/fake-data-producer-for-apache-kafka-docker)

Features
============

The example demonstrates how:

* Create an Aiven for Apache Kafka® and Aiven for Apache Flink® services. This step is strictly not necessary you can use any Apache Kafka and Apache Flink instance. The anomaly detection SQL queries will work over any Apache Flink® 1.14+ version.
* Create a Fake Pizza streaming data generator using docker
* Create an Apache Flink SQL job for basic filtering
* Create an Apache Flink SQL job for basic aggregation
* Create an Apache Flink SQL job for window aggregation
* Create an Apache Flink SQL job to recognise patterns

Setup
============

To be able to run the scripts you need:

* The [Aiven CLI](https://developer.aiven.io/docs/tools/cli.html) installed and an [Aiven valid login token](https://console.aiven.io/signup)
* Docker installed

The complete set of steps is available in the [demo.md](demo-md) file.

License
============
Streaming Anomaly Detection with Apache Flink® and Apache Kafka® is licensed under the Apache license, version 2.0. Full license text is available in the [LICENSE](LICENSE) file.

Please note that the project explicitly does not require a CLA (Contributor License Agreement) from its contributors.

Contact
============
Bug reports and patches are very welcome, please post them as GitHub issues and pull requests at https://github.com/aiven/{{PROJECT_NAME}} . 
To report any possible vulnerabilities or other serious issues please see our [security](SECURITY.md) policy.
