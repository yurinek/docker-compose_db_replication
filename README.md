# docker-compose_db_replication

This is a prove of concept for creation of Postgres Database Master-Slave-Replication in different Docker containers on the same host using docker-compose.<br>
It will build one master and one slave db image and create containers with ready to use db replication based on Postgres 12.

## How to install

Copy the contents of this repo to your target host

## How to run

```hcl 
docker-compose up -d
```

For the second run ( e.g. to implement changes)<br>
delete volumes, otherwise they have previous db files which can cause errors of pg_basebackup
```hcl
docker-compose down -v --remove-orphans --rmi all
docker-compose up -d --build
```

To create containers with different project name<br>
Edit .env to change project name <br>
If image already built, because env var of the previous project name is stored in the image, it needs to be rebuild


### To run without compose (useful for debugging)<br>
(port exposure only needed for connection from host)

```hcl
docker network create pgreplication_net

docker build -t yurinek/postgres_master:12 \
-f dockerfile_master \
--build-arg PG_VERSION_PULL=12 \
--build-arg PG_DB=mydb \
--build-arg PG_CLUSTER_NAME=rep \
--build-arg PG_PORT=5432 \
--build-arg PG_PASSWORD=mysecret .

docker run -dit --name=postgres_master \
--network=pgreplication_net \
-v master_vol:/data/postgresql/12/rep \
-p 5432:5432 \
yurinek/postgres_master:12

docker build -t yurinek/postgres_slave:12 \
-f dockerfile_slave \
--build-arg PG_VERSION_PULL=12 \
--build-arg PG_DB=mydb \
--build-arg PG_CLUSTER_NAME=rep \
--build-arg PG_PORT=5432 \
--build-arg PG_PASSWORD=mysecret .

docker run -dit --name=postgres_slave \
--network=pgreplication_net \
-v slave_vol:/data/postgresql/12/rep \
-p 5433:5432 \
yurinek/postgres_slave:12
```

To customize PG_VERSION_PULL and PG_CLUSTER_NAME the image needs to be rebuild. Its not possible to customize it on container run. <br>
Change the values in .env file and rebuild.<br><br>

To customize db, password (needs to be the same in master and slave) and master host name

```hcl
export RUNTIME_ENV_PG_DB=yourdb
export POSTGRES_PASSWORD=yoursecret
export RUNTIME_ENV_MASTER_HOST=postgres_test

docker run -dit --name=$RUNTIME_ENV_MASTER_HOST \
-e RUNTIME_ENV_PG_DB=$RUNTIME_ENV_PG_DB \
-e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
--network=pgreplication_net \
-v master_vol:/data/postgresql/12/rep \
-p 5432:5432 \
yurinek/postgres_master:12

docker run -dit --name=postgres_slave \
-e RUNTIME_ENV_PG_DB=$RUNTIME_ENV_PG_DB \
-e RUNTIME_ENV_MASTER_HOST=$RUNTIME_ENV_MASTER_HOST \
-e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
--network=pgreplication_net \
-v slave_vol:/data/postgresql/12/rep \
-p 5433:5432 \
yurinek/postgres_slave:12
```

### To connect from host
```hcl
psql -h localhost -p 5432 -U postgres $RUNTIME_ENV_PG_DB -W
```



