#!/bin/bash

if [ ! -z "$RUNTIME_ENV_MASTER_HOST" ]; then
    echo "RUNTIME_ENV_MASTER_HOST: $RUNTIME_ENV_MASTER_HOST - is set"
else
    echo "RUNTIME_ENV_MASTER_HOST: $RUNTIME_ENV_MASTER_HOST - not set, setting default value..."
    RUNTIME_ENV_MASTER_HOST=postgres_master
fi

# for connections from host
echo "host all         postgres   samenet md5" >> /etc/postgresql/$RUNTIME_ENV_PG_VERSION_PULL/$RUNTIME_ENV_PG_CLUSTER_NAME/pg_hba.conf
# in case slave becomes master
echo "host replication replicator samenet md5" >> /etc/postgresql/$RUNTIME_ENV_PG_VERSION_PULL/$RUNTIME_ENV_PG_CLUSTER_NAME/pg_hba.conf
chown postgres. /etc/postgresql/$RUNTIME_ENV_PG_VERSION_PULL/$RUNTIME_ENV_PG_CLUSTER_NAME/pg_hba.conf

# dont use "su -" to keep roots env
su postgres -c 'echo "*:*:*:*:${POSTGRES_PASSWORD}" >> ~/.pgpass'
su postgres -c 'chmod go-rw ~/.pgpass'

echo "########## Waiting for Master container to be up ..."
su postgres -c "until pg_isready -h $RUNTIME_ENV_MASTER_HOST -p $RUNTIME_ENV_PG_PORT; do echo 'Waiting for $RUNTIME_ENV_PG_VERSION_PULL db server startup at: $RUNTIME_ENV_PG_PORT' sleep 5; done"

echo "########## Waiting for Master DB configuration to be ready ..."
# otherwise error: db user replicator doesnt exist - because master and slave containers start simultaniously and configure_master.sh is not done yet
cat > /tmp/test_query.sh <<- EOT1
psql -h $RUNTIME_ENV_MASTER_HOST -p $RUNTIME_ENV_PG_PORT $RUNTIME_ENV_PG_DB -c 'select id from test;'
EOT1
chown postgres. /tmp/test_query.sh
chmod +x /tmp/test_query.sh

while true; do
    su postgres -c "/tmp/test_query.sh"
    # if stderr equals zero, exit loop
    if [ $? -eq 0 ]; then
        break
    fi
    sleep 1
done


echo "########## Starting Replication from Master Database ..."

if [ "$RUNTIME_ENV_PG_VERSION_PULL" -le 11 ]; then

    su postgres -c "pg_basebackup -h $RUNTIME_ENV_MASTER_HOST -U replicator -p $RUNTIME_ENV_PG_PORT -D /data/postgresql/$RUNTIME_ENV_PG_VERSION_PULL/$RUNTIME_ENV_PG_CLUSTER_NAME -v -P -X fetch"
    su postgres -c "cat > /data/postgresql/$RUNTIME_ENV_PG_VERSION_PULL/$RUNTIME_ENV_PG_CLUSTER_NAME/recovery.conf <<- EOT1
  standby_mode = 'on'
  primary_conninfo = 'host=$RUNTIME_ENV_MASTER_HOST port=$RUNTIME_ENV_PG_PORT user=replicator'
  trigger_file = '/tmp/postgresql.trigger'
EOT1"

    chown postgres. /data/postgresql/$RUNTIME_ENV_PG_VERSION_PULL/$RUNTIME_ENV_PG_CLUSTER_NAME/recovery.conf
    ls -l /data/postgresql/$RUNTIME_ENV_PG_VERSION_PULL/$RUNTIME_ENV_PG_CLUSTER_NAME/recovery.conf

else

    # for Postgres >= 12 Replication we need -R parameter and no recovery.conf file
    su postgres -c "pg_basebackup -h $RUNTIME_ENV_MASTER_HOST -U replicator -p $RUNTIME_ENV_PG_PORT -D /data/postgresql/$RUNTIME_ENV_PG_VERSION_PULL/$RUNTIME_ENV_PG_CLUSTER_NAME -v -P -R -X fetch"
    ls -l /data/postgresql/$RUNTIME_ENV_PG_VERSION_PULL/$RUNTIME_ENV_PG_CLUSTER_NAME/standby.signal
    ls -l /data/postgresql/$RUNTIME_ENV_PG_VERSION_PULL/$RUNTIME_ENV_PG_CLUSTER_NAME/postgresql.auto.conf
    cat   /data/postgresql/$RUNTIME_ENV_PG_VERSION_PULL/$RUNTIME_ENV_PG_CLUSTER_NAME/postgresql.auto.conf

fi


echo "########## Starting Postgres Cluster $RUNTIME_ENV_PG_VERSION_PULL $RUNTIME_ENV_PG_CLUSTER_NAME ..." 
/usr/bin/pg_ctlcluster $RUNTIME_ENV_PG_VERSION_PULL $RUNTIME_ENV_PG_CLUSTER_NAME start

su postgres -c "psql -p $RUNTIME_ENV_PG_PORT $RUNTIME_ENV_PG_DB -c 'select id as replication_test_query from test;'"

# let this process run so container keeps running
# for "docker run" and "docker-compose" /bin/bash would be fine, but for "docker swarm" process needs to run in foreground, otherwise container will exit and would be recreated in endless loop
sleep infinity

