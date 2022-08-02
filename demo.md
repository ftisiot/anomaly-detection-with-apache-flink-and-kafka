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
docker run fake-data-producer-for-apache-kafka-docker
```

If everything works correctly we should see the flow of pizza orders being generated

![Flow of orders](img/flow_orders.gif)


Create the Apache Flink® Source Table
-------------------------------------

To be able to analyze incoming pizza orders, we need to create a table on top of the Apache Kafka stream, with the following Aiven client commands.

```
KAFKA_FLINK_SI=$(avn service integration-list --json demo-kafka | jq -r '.[] | select(.dest == "demo-flink").service_integration_id')
avn service flink table create demo-flink \
    """{
        \"name\":\"pizza_orders\",
        \"integration_id\": \"$KAFKA_FLINK_SI\",
        \"kafka\": {
            \"scan_startup_mode\": \"earliest-offset\",
            \"topic\": \"pizza_stream_in\",
            \"value_fields_include\": \"ALL\",
            \"value_format\": \"json\"
        },
        \"schema_sql\":\"id INT, shop VARCHAR, name VARCHAR, phoneNumber VARCHAR, address VARCHAR, pizzas ARRAY <ROW (pizzaName VARCHAR, additionalToppings ARRAY <VARCHAR>)>, orderTimestamp TIMESTAMP(3) METADATA FROM 'timestamp', orderProctime AS PROCTIME(), WATERMARK FOR orderTimestamp AS orderTimestamp - INTERVAL '5' SECOND\"    
    }"""
```

Apply basic filtering
---------------------

The first anomaly will be to spot all occurrences of  `🍍 pineapple`, `🍓 strawberry` and `🍌 banana` and redirect them to a specific topic, we can do so by first creating the table over the target topic with:

```
avn service flink table create demo-flink \
    """{
        \"name\":\"pizza_orders_filter\",
        \"integration_id\": \"$KAFKA_FLINK_SI\",
        \"kafka\": {
            \"scan_startup_mode\": \"earliest-offset\",
            \"topic\": \"pizza_stream_out_filter\",
            \"value_fields_include\": \"ALL\",
            \"value_format\": \"json\"
        },
        \"schema_sql\":\"id INT, name VARCHAR, topping VARCHAR, orderTimestamp TIMESTAMP(3)\"    
    }"""
```

And then creating a Flink job with:

```
TABLE_IN_ID=$(avn service flink table list demo-flink --json | jq -r '.[] | select (.table_name == "pizza_orders").table_id')
TABLE_FILTER_OUT_ID=$(avn service flink table list demo-flink --json | jq -r '.[] | select (.table_name == "pizza_orders_filter").table_id')
avn service flink job create demo-flink my_first_filter \
    --table-ids $TABLE_IN_ID $TABLE_FILTER_OUT_ID \
    --statement """
        insert into pizza_orders_filter
        select
            id,
            name,
            c.topping,
            orderTimestamp
        from pizza_orders
        cross join UNNEST(pizzas) b
        cross join UNNEST(b.additionalToppings) as c(topping)
        where c.topping in ('🍍 pineapple', '🍓 strawberry','🍌 banana')
        """
```

We can verify the presence of data in the target topic using kcat (after properly setting the `kcat.config` file as per [dedicated documentation](https://developer.aiven.io/docs/products/kafka/howto/kcat.html))

```
kcat -F $PINEAPPLE_PATH/kcat.config -C -t pizza_stream_out_filter
```

Aggregating data
----------------

What if we want to flag only orders having more than 3 prohibited toppings? 
Again let's create the target Flink Table with:

```
avn service flink table create demo-flink \
    """{
        \"name\":\"pizza_orders_agg\",
        \"integration_id\": \"$KAFKA_FLINK_SI\",
        \"upsert_kafka\": {
            \"key_format\": \"json\",
            \"topic\": \"pizza_stream_out_agg\",
            \"value_fields_include\": \"ALL\",
            \"value_format\": \"json\"
        },
        \"schema_sql\":\"id INT PRIMARY KEY, name VARCHAR, nr_bad_items BIGINT, toppings VARCHAR, orderTimestamp TIMESTAMP(3)\"    
    }"""
```

And define the SQL transformation job. Check out the `GROUP BY` and `HAVING` sections.

```
TABLE_IN_ID=$(avn service flink table list demo-flink --json | jq -r '.[] | select (.table_name == "pizza_orders").table_id')
TABLE_FILTER_OUT_ID=$(avn service flink table list demo-flink --json | jq -r '.[] | select (.table_name == "pizza_orders_agg").table_id')
avn service flink job create demo-flink my_first_agg \
    --table-ids $TABLE_IN_ID $TABLE_FILTER_OUT_ID \
    --statement """
        insert into pizza_orders_agg
        select
            id,
            name,
            count(*) nr_bad_items,
            LISTAGG(c.topping) list_bad_items,
            orderTimestamp           
        from pizza_orders
        cross join UNNEST(pizzas) b
        cross join UNNEST(b.additionalToppings) as c(topping)
        where c.topping in ('🍍 pineapple', '🍓 strawberry','🍌 banana')
        group by id, name, orderTimestamp
        having count(*) > 3
        """
```

We can check the results with `kcat`

```
kcat -F $PINEAPPLE_PATH/kcat.config -C -t pizza_stream_out_agg -u | jq -c
```

Check for trends
----------------

The last anomaly is to check for particular trends, using the `MATCH_RECOGNIZE` function. Let's create the table

```
avn service flink table create demo-flink \
    """{
        \"name\":\"pizza_orders_trends\",
        \"integration_id\": \"$KAFKA_FLINK_SI\",
        \"upsert_kafka\": {
            \"key_format\": \"json\",
            \"topic\": \"pizza_stream_out_trends\",
            \"value_fields_include\": \"ALL\",
            \"value_format\": \"json\"
        },
        \"schema_sql\":\"topping VARCHAR, trend_start TIMESTAMP(3), trend_detail VARCHAR, PRIMARY KEY(topping, trend_start) NOT ENFORCED\"    
    }"""
```

And the SQL to recognize a trend where the number of orders containing a specific topping:
1. increases for one or more 5-seconds window
2. decreases for exactly two 5-seconds window

```
TABLE_FILTER_OUT_ID=$(avn service flink table list demo-flink --json | jq -r '.[] | select (.table_name == "pizza_orders_trends").table_id')
avn service flink job create demo-flink my_first_agg \
    --table-ids $TABLE_IN_ID $TABLE_FILTER_OUT_ID \
    --statement """
        insert into pizza_orders_trends
        WITH base_data as (
            SELECT window_time,
                window_start,
                window_end,
                topping,
                count(*) nr_orders
            FROM TABLE(TUMBLE(TABLE pizza_orders, DESCRIPTOR(orderTimestamp), interval '5' seconds))
                cross join UNNEST(pizzas) b
                cross join UNNEST(b.additionalToppings) as c(topping)
            where c.topping in ('🍍 pineapple', '🍓 strawberry','🍌 banana')
            group by window_time,
                topping,
                window_start,
                window_end

            )
        select * from base_data
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
            """
```



Delete services
---------------

Once done, we can delete our services with:

```
avn service terminate demo-kafka --force
avn service terminate demo-flink --force
avn service terminate demo-postgresql --force
```
