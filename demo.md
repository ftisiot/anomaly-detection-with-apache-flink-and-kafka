# Streaming Anomaly Detection with Apache Flink® and Apache Kafka®

Finding anomalies can be tricky, with Apache Kafka® and Apache Flink® we can find out in streaming mode

Create services
---------------

The first step is to create an Aiven for Apache Kafka® and an Aiven for Apache Flink® services. You are free to use any Apache Kafka® or Apache Flink® service out there. The anomaly detection SQL queries will work over any Apache Flink® 1.14+ version, the table definition might require some minor tweaks.

The following commands will create the Aiven for Apache Kafka® and an Aiven for Apache Flink® services, and the integration between them. 

```
avn service create demo-kafka               \
    -t kafka                                \
    --cloud google-europe-west3             \
    -p business-4                           \
    -c kafka.auto_create_topics_enable=true \
    -c kafka_connect=true                   \
    -c kafka_rest=true                      \
    -c schema_registry=true
avn service create demo-flink -t flink --cloud google-europe-west3 -p business-4
avn service integration-create      \
    -t flink                        \
    -s demo-kafka                   \
    -d demo-flink
```

To be able to push the data to Aiven for Apache Kafka® we need the SSL certificates, which can be downloaded in the `certs` folder with the following

```
avn service user-creds-download demo-kafka --username avnadmin -d certs
```


Start streaming pizzas
----------------------

Now it's time to clone the [Fake pizza generator on Docker](https://github.com/aiven/fake-data-producer-for-apache-kafka-docker) and start creating pizza orders.

```
rm -rf fake-data-producer-for-apache-kafka-docker
git clone https://github.com/aiven/fake-data-producer-for-apache-kafka-docker.git
```

You need to copy the `env.conf.sample` within the `fake-data-producer-for-apache-kafka-docker/conf/` folder to `env.conf` and include all the required parameters. Then we can build the container and run it. 

```
cd fake-data-producer-for-apache-kafka-docker/
docker build -t fake-data-producer-for-apache-kafka-docker .
docker run -it fake-data-producer-for-apache-kafka-docker
```

If everything works correctly we should see the flow of pizza orders being generated

![Flow of orders](img/flow_orders.gif)


Retrieve the Flink-Kafka integration ID
---------------------------------------

To be able to define flink pipelines we need to retrieve the ID of the integration between Apache Kafka and Apache Flink with:

```bash
KAFKA_FLINK_SI=$(avn service integration-list --json demo-kafka | jq -r '.[] | select(.dest == "demo-flink").service_integration_id')
```

To make the following calls easier to run, assign to the variable `PROJECT` the name of your project with:

```bash
PROJECT=my_aiven_project_name
```

Apply basic filtering
---------------------

The first anomaly will be to spot all occurrences of  `🍍 pineapple`, `🍓 strawberry` and `🍌 banana` and redirect them to a specific topic, we can do so by:

1. Creating an application named `BasicFiltering` with

```bash
avn service flink create-application demo-flink \
    --project $PROJECT \
    "{\"name\":\"BasicFiltering\"}"
```
2. Retrieve the application id with:

```bash
APP_ID=$(avn service flink list-applications demo-flink   \
    --project $PROJECT | jq -r '.applications[] | select(.name == "BasicFiltering").id')
```

3. Replace the integration ids in the Application definition file named `01-basic-filtering.json`


```bash
mkdir -p tmp
sed "s/KAFKA_INTEGRATION_ID/$KAFKA_FLINK_SI/" 'flink-app/01-basic-filtering.json' > tmp/01-basic-filtering.json
```
4. Creating the Apache Flink application filtering the data with:

```bash
avn service flink create-application-version demo-flink   \
    --project $PROJECT                                    \
    --application-id $APP_ID                              \
    @tmp/01-basic-filtering.json 
```

The `flink-app/01-basic-filtering.json` contains:

* A source table definition, pointing to the `pizzas` topic:

```sql
CREATE TABLE pizza_source (
    id INT, 
    shop VARCHAR, 
    name VARCHAR, 
    phoneNumber VARCHAR, 
    address VARCHAR, 
    pizzas ARRAY <ROW (pizzaName VARCHAR, additionalToppings ARRAY <VARCHAR>)>, orderTimestamp TIMESTAMP(3) METADATA FROM 'timestamp', orderProctime AS PROCTIME(), WATERMARK FOR orderTimestamp AS orderTimestamp - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'properties.bootstrap.servers' = '',
    'scan.startup.mode' = 'earliest-offset',
    'topic' = 'pizzas',
    'value.format' = 'json'
)
```

* A target table application, pointing to a new Kafka topic named `pizza_stream_out_filter`:

```bash
CREATE TABLE pizza_filtered (
    id INT, 
    name VARCHAR, 
    topping VARCHAR, 
    orderTimestamp TIMESTAMP(3)
) WITH (
    'connector' = 'kafka',
    'properties.bootstrap.servers' = '',
    'scan.startup.mode' = 'earliest-offset',
    'topic' = 'pizza_stream_out_filter',
    'value.format' = 'json'
)
```

* The Filtering transformation logic:

```
insert into pizza_filtered
select
    id,
    name,
    c.topping,
    orderTimestamp
from pizza_source
cross join UNNEST(pizzas) b
cross join UNNEST(b.additionalToppings) as c(topping)
where c.topping in ('🍍 pineapple', '🍓 strawberry','🍌 banana')
```

**Run the application**

We can run the application by following the steps below:

1. Retrieve the Application version id you want to run, e.g. for the version `1`` of the `BasicFiltering` application:

```bash
APP_VERSION_1=$(avn service flink get-application demo-flink \
    --project $PROJECT --application-id $APP_ID | jq -r '.application_versions[] | select(.version == 1).id')
```
2. Create a deployment and store its id in the `DEPLOYMENT_ID` variable

```bash
avn service flink create-application-deployment  demo-flink   \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  "{\"parallelism\": 1,\"restart_enabled\": true,  \"version_id\": \"$APP_VERSION_1\"}"
```

3. Retrieve the deployment id with:

```bash
APP_DEPLOYMENT=$(avn service flink list-application-deployments demo-flink       \
  --project $PROJECT                                                             \
  --application-id $APP_ID | jq  -r ".deployments[] | select(.version_id == \"$APP_VERSION_1\").id")
```

4. Retrieve the deployment status

```bash
avn service flink get-application-deployment demo-flink       \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  --deployment-id $APP_DEPLOYMENT | jq '.status'
```

The app should be in `RUNNING` state

We can verify the presence of data in the target `pizza_stream_out_filter` topic using kcat (after properly setting the `kcat.config` file as per [dedicated documentation](https://developer.aiven.io/docs/products/kafka/howto/kcat.html))

```bash
kcat -F $PINEAPPLE_PATH/kcat.config -C -t pizza_stream_out_filter
```

Aggregating data
----------------

What if we want to flag only orders having more than 3 prohibited toppings? 


1. Creating an application named `Aggregating` with

```bash
avn service flink create-application demo-flink \
    --project $PROJECT \
    "{\"name\":\"Aggregating\"}"
```
2. Retrieve the application id with:

```bash
APP_ID=$(avn service flink list-applications demo-flink   \
    --project $PROJECT | jq -r '.applications[] | select(.name == "Aggregating").id')
```

3. Replace the integration ids in the Application definition file named `02-aggregating.json`


```bash
mkdir -p tmp
sed "s/KAFKA_INTEGRATION_ID/$KAFKA_FLINK_SI/" 'flink-app/02-aggregating.json' > tmp/02-aggregating.json
```
4. Creating the Apache Flink application filtering the data with:

```bash
avn service flink create-application-version demo-flink   \
    --project $PROJECT                                    \
    --application-id $APP_ID                              \
    @tmp/02-aggregating.json 
```

The `flink-app/02-aggregating.json` contains:

* A source table definition, pointing to the `pizzas` topic:

```sql
CREATE TABLE pizza_source (
    id INT, 
    shop VARCHAR, 
    name VARCHAR, 
    phoneNumber VARCHAR, 
    address VARCHAR, 
    pizzas ARRAY <ROW (pizzaName VARCHAR, additionalToppings ARRAY <VARCHAR>)>, orderTimestamp TIMESTAMP(3) METADATA FROM 'timestamp', orderProctime AS PROCTIME(), WATERMARK FOR orderTimestamp AS orderTimestamp - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'properties.bootstrap.servers' = '',
    'scan.startup.mode' = 'earliest-offset',
    'topic' = 'pizzas',
    'value.format' = 'json'
)
```

* A target table application, pointing to a new Kafka topic named `pizza_stream_out_agg` with the upsert mode and the order `id` being the primary key:

```bash
CREATE TABLE pizzas_aggs (
    id INT PRIMARY KEY, 
    name VARCHAR, 
    nr_bad_items BIGINT, 
    toppings VARCHAR, 
    orderTimestamp TIMESTAMP(3)
) WITH (
   'connector' = 'upsert-kafka',
   'properties.bootstrap.servers' = '',
   'topic' = 'pizza_stream_out_agg',
   'value.format' = 'json',
   'key.format' = 'json'
)
```

* The aggregating transformation logic:

```
insert into pizzas_aggs
        select
            id,
            name,
            count(*) nr_bad_items,
            LISTAGG(c.topping) list_bad_items,
            orderTimestamp           
        from pizza_source
        cross join UNNEST(pizzas) b
        cross join UNNEST(b.additionalToppings) as c(topping)
        where c.topping in ('🍍 pineapple', '🍓 strawberry','🍌 banana')
        group by id, name, orderTimestamp
        having count(*) > 3
```

**Run the application**

We can run the application by following the steps below:

1. Retrieve the Application version id you want to run, e.g. for the version `1`` of the `BasicFiltering` application:

```bash
APP_VERSION_1=$(avn service flink get-application demo-flink \
    --project $PROJECT --application-id $APP_ID | jq -r '.application_versions[] | select(.version == 1).id')
```
2. Create a deployment and store its id in the `DEPLOYMENT_ID` variable

```bash
avn service flink create-application-deployment  demo-flink   \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  "{\"parallelism\": 1,\"restart_enabled\": true,  \"version_id\": \"$APP_VERSION_1\"}"
```

3. Retrieve the deployment id with:

```bash
APP_DEPLOYMENT=$(avn service flink list-application-deployments demo-flink       \
  --project $PROJECT                                                             \
  --application-id $APP_ID | jq  -r ".deployments[] | select(.version_id == \"$APP_VERSION_1\").id")
```

4. Retrieve the deployment status

```bash
avn service flink get-application-deployment demo-flink       \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  --deployment-id $APP_DEPLOYMENT | jq '.status'
```

The app should be in `RUNNING` state

We can verify the presence of data in the target `pizza_stream_out_agg` topic using kcat (after properly setting the `kcat.config` file as per [dedicated documentation](https://developer.aiven.io/docs/products/kafka/howto/kcat.html))

```bash
kcat -F $PINEAPPLE_PATH/kcat.config -C -t pizza_stream_out_agg
```

Create windows
--------------

We might want to check orders over time and flag only if certain thresholds have been met over a precise time window.


1. Creating an application named `Windowing` with

```bash
avn service flink create-application demo-flink \
    --project $PROJECT \
    "{\"name\":\"Windowing\"}"
```
2. Retrieve the application id with:

```bash
APP_ID=$(avn service flink list-applications demo-flink   \
    --project $PROJECT | jq -r '.applications[] | select(.name == "Windowing").id')
```

3. Replace the integration ids in the Application definition file named `03-windowing.json`


```bash
mkdir -p tmp
sed "s/KAFKA_INTEGRATION_ID/$KAFKA_FLINK_SI/" 'flink-app/03-windowing.json' > tmp/03-windowing.json
```
4. Creating the Apache Flink application filtering the data with:

```bash
avn service flink create-application-version demo-flink   \
    --project $PROJECT                                    \
    --application-id $APP_ID                              \
    @tmp/03-windowing.json 
```

The `flink-app/03-windowing.json` contains:

* A source table definition, pointing to the `pizzas` topic:

```sql
CREATE TABLE pizza_source (
    id INT, 
    shop VARCHAR, 
    name VARCHAR, 
    phoneNumber VARCHAR, 
    address VARCHAR, 
    pizzas ARRAY <ROW (pizzaName VARCHAR, additionalToppings ARRAY <VARCHAR>)>, orderTimestamp TIMESTAMP(3) METADATA FROM 'timestamp', orderProctime AS PROCTIME(), WATERMARK FOR orderTimestamp AS orderTimestamp - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'properties.bootstrap.servers' = '',
    'scan.startup.mode' = 'earliest-offset',
    'topic' = 'pizzas',
    'value.format' = 'json'
)
```

* A target table application, pointing to a new Kafka topic named `pizza_stream_out_agg_windows` with the upsert mode and the order `topping`, `window_start`, and `window_end` being the primary key:

```bash
CREATE TABLE pizza_windows (
    window_time TIMESTAMP(3), 
    window_start TIMESTAMP(3), 
    window_end TIMESTAMP(3), 
    topping VARCHAR, 
    nr_orders BIGINT, 
    PRIMARY KEY(topping, window_start, window_end) NOT ENFORCED
) WITH (
   'connector' = 'upsert-kafka',
   'properties.bootstrap.servers' = '',
   'topic' = 'pizza_stream_out_agg_windows',
   'value.format' = 'json',
   'key.format' = 'json'
)
```

* The aggregating transformation logic:

```
insert into pizza_windows
        with raw_data as (
            select orderTimestamp,
                id,
                c.topping
            from pizza_source
                cross join UNNEST(pizzas) b
                cross join UNNEST(b.additionalToppings) as c(topping)
            )
        SELECT window_time,
            window_start,
            window_end,
            topping,
            count(*) nr_orders
        FROM TABLE(TUMBLE(TABLE raw_data, DESCRIPTOR(orderTimestamp), interval '5' seconds))
        where topping in ('🍍 pineapple', '🍓 strawberry','🍌 banana')
        group by window_time,
            topping,
            window_start,
            window_end
        having count(*) > 10
```

**Run the application**

We can run the application by following the steps below:

1. Retrieve the Application version id you want to run, e.g. for the version `1`` of the `BasicFiltering` application:

```bash
APP_VERSION_1=$(avn service flink get-application demo-flink \
    --project $PROJECT --application-id $APP_ID | jq -r '.application_versions[] | select(.version == 1).id')
```
2. Create a deployment and store its id in the `DEPLOYMENT_ID` variable

```bash
avn service flink create-application-deployment  demo-flink   \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  "{\"parallelism\": 1,\"restart_enabled\": true,  \"version_id\": \"$APP_VERSION_1\"}"
```

3. Retrieve the deployment id with:

```bash
APP_DEPLOYMENT=$(avn service flink list-application-deployments demo-flink       \
  --project $PROJECT                                                             \
  --application-id $APP_ID | jq  -r ".deployments[] | select(.version_id == \"$APP_VERSION_1\").id")
```

4. Retrieve the deployment status

```bash
avn service flink get-application-deployment demo-flink       \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  --deployment-id $APP_DEPLOYMENT | jq '.status'
```

The app should be in `RUNNING` state

We can verify the presence of data in the target `pizza_stream_out_agg_windows` topic using kcat (after properly setting the `kcat.config` file as per [dedicated documentation](https://developer.aiven.io/docs/products/kafka/howto/kcat.html))

```bash
kcat -F $PINEAPPLE_PATH/kcat.config -C -t pizza_stream_out_agg_windows -u | jq -c
```


Check for trends
----------------

The last anomaly is to check for particular trends, using the `MATCH_RECOGNIZE` function. Let's create the table.


1. Creating an application named `Trends` with

```bash
avn service flink create-application demo-flink \
    --project $PROJECT \
    "{\"name\":\"Trends\"}"
```
2. Retrieve the application id with:

```bash
APP_ID=$(avn service flink list-applications demo-flink   \
    --project $PROJECT | jq -r '.applications[] | select(.name == "Trends").id')
```

3. Replace the integration ids in the Application definition file named `04-trends.json`


```bash
mkdir -p tmp
sed "s/KAFKA_INTEGRATION_ID/$KAFKA_FLINK_SI/" 'flink-app/04-trends.json' > tmp/04-trends.json
```
4. Creating the Apache Flink application filtering the data with:

```bash
avn service flink create-application-version demo-flink   \
    --project $PROJECT                                    \
    --application-id $APP_ID                              \
    @tmp/04-trends.json 
```

The `flink-app/04-trends.json` contains:

* A source table definition, pointing to the `pizzas` topic:

```sql
CREATE TABLE pizza_source (
    id INT, 
    shop VARCHAR, 
    name VARCHAR, 
    phoneNumber VARCHAR, 
    address VARCHAR, 
    pizzas ARRAY <ROW (pizzaName VARCHAR, additionalToppings ARRAY <VARCHAR>)>, orderTimestamp TIMESTAMP(3) METADATA FROM 'timestamp', orderProctime AS PROCTIME(), WATERMARK FOR orderTimestamp AS orderTimestamp - INTERVAL '5' SECOND
) WITH (
    'connector' = 'kafka',
    'properties.bootstrap.servers' = '',
    'scan.startup.mode' = 'earliest-offset',
    'topic' = 'pizzas',
    'value.format' = 'json'
)
```

* A target table application, pointing to a new Kafka topic named `pizza_stream_out_trends` with the upsert mode and the order `topping` and `trend_start` being the primary key:

```bash
CREATE TABLE pizza_orders_trend (
    topping VARCHAR, 
    trend_start TIMESTAMP(3), 
    trend_detail VARCHAR, 
    PRIMARY KEY(topping, trend_start) NOT ENFORCED
) WITH (
   'connector' = 'upsert-kafka',
   'properties.bootstrap.servers' = 'pizza_stream_out_trends',
   'topic' = 'pizza_stream_out_trends',
   'value.format' = 'json',
   'key.format' = 'json'
)
```

* The aggregating transformation logic using Apache Flink `MATCH_RECOGNIZE` function:

```sql
insert into pizza_orders_trend
        with raw_data as (
            select orderTimestamp,
                id,
                c.topping
            from pizza_source
                cross join UNNEST(pizzas) b
                cross join UNNEST(b.additionalToppings) as c(topping)
            )
        , windowing as
            (SELECT window_time,
                window_start,
                window_end,
                topping,
                count(*) nr_orders
            FROM TABLE(TUMBLE(TABLE raw_data, DESCRIPTOR(orderTimestamp), interval '5' seconds))
            where topping in ('🍍 pineapple', '🍓 strawberry','🍌 banana')
            group by window_time,
                topping,
                window_start,
                window_end)
        select * from windowing
        MATCH_RECOGNIZE (
            PARTITION BY topping
            ORDER BY window_time
            MEASURES
                START_ROW.window_time as start_tstamp,
                LISTAGG(cast(nr_orders as string)) as various_nr_orders
            ONE ROW PER MATCH
            AFTER MATCH SKIP PAST LAST ROW
            PATTERN (START_ROW NR_UP+ NR_DOWN{2})
            DEFINE
                NR_UP AS
                    (LAST(NR_UP.nr_orders, 1) IS NULL AND NR_UP.nr_orders > START_ROW.nr_orders OR
                    NR_UP.nr_orders > LAST(NR_UP.nr_orders, 1)),
                NR_DOWN AS
                    (LAST(NR_DOWN.nr_orders, 1) IS NULL AND NR_DOWN.nr_orders < LAST(NR_UP.nr_orders, 1)) OR
                    NR_DOWN.nr_orders < LAST(NR_DOWN.nr_orders, 1)

            )
```

**Run the application**

We can run the application by following the steps below:

1. Retrieve the Application version id you want to run, e.g. for the version `1`` of the `BasicFiltering` application:

```bash
APP_VERSION_1=$(avn service flink get-application demo-flink \
    --project $PROJECT --application-id $APP_ID | jq -r '.application_versions[] | select(.version == 1).id')
```
2. Create a deployment and store its id in the `DEPLOYMENT_ID` variable

```bash
avn service flink create-application-deployment  demo-flink   \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  "{\"parallelism\": 1,\"restart_enabled\": true,  \"version_id\": \"$APP_VERSION_1\"}"
```

3. Retrieve the deployment id with:

```bash
APP_DEPLOYMENT=$(avn service flink list-application-deployments demo-flink       \
  --project $PROJECT                                                             \
  --application-id $APP_ID | jq  -r ".deployments[] | select(.version_id == \"$APP_VERSION_1\").id")
```

4. Retrieve the deployment status

```bash
avn service flink get-application-deployment demo-flink       \
  --project $PROJECT                                          \
  --application-id $APP_ID                                    \
  --deployment-id $APP_DEPLOYMENT | jq '.status'
```

The app should be in `RUNNING` state

We can verify the presence of data in the target `pizza_stream_out_trends` topic using kcat (after properly setting the `kcat.config` file as per [dedicated documentation](https://developer.aiven.io/docs/products/kafka/howto/kcat.html))

```bash
kcat -F $PINEAPPLE_PATH/kcat.config -C -t pizza_stream_out_trends -u | jq -c
```


Delete services
---------------

Once done, we can delete our services with:

```
avn service terminate demo-kafka --force
avn service terminate demo-flink --force
avn service terminate demo-postgresql --force
```
