#!/bin/bash

MASTER=-1
MASTER_IP=
NUM_REGISTERED_WORKERS=0

# starts the Spark/Shark master container
function start_master() {
    echo "starting master container"
    if [ "$DEBUG" -gt 0 ]; then
        echo sudo docker run -i -t -d -dns $NAMESERVER_IP -h master${DOMAINNAME} $VOLUME_MAP $1:$2
    fi
    MASTER=$(sudo docker run -i -t -d -dns $NAMESERVER_IP -h master${DOMAINNAME} $VOLUME_MAP $1:$2)
    echo "started master container:      $MASTER"
    sleep 3
    MASTER_IP=$(sudo docker logs $MASTER 2>&1 | egrep '^MASTER_IP=' | awk -F= '{print $2}' | tr -d -c "[:digit:] .")
    echo "MASTER_IP:                     $MASTER_IP"
    echo "address=\"/master/$MASTER_IP\"" >> $DNSFILE
}

# starts a number of Spark/Shark workers
function start_workers() {
    for i in `seq 1 $NUM_WORKERS`; do
        echo "starting worker container"
	hostname="worker${i}${DOMAINNAME}"
        if [ "$DEBUG" -gt 0 ]; then
	    echo sudo docker run -d -dns $NAMESERVER_IP -h $hostname $VOLUME_MAP $1:$2 ${MASTER_IP}
        fi
	WORKER=$(sudo docker run -d -dns $NAMESERVER_IP -h $hostname $VOLUME_MAP $1:$2 ${MASTER_IP})
	echo "started worker container:  $WORKER"
	sleep 3
	WORKER_IP=$(sudo docker logs $WORKER 2>&1 | egrep '^WORKER_IP=' | awk -F= '{print $2}' | tr -d -c "[:digit:] .")
	echo "address=\"/$hostname/$WORKER_IP\"" >> $DNSFILE
    done
}

# prints out information on the cluster
function print_cluster_info() {
    BASEDIR=$(cd $(dirname $0); pwd)"/.."
    echo ""
    echo "***********************************************************************"
    echo "connect to via:             $1"
    echo ""
    echo "visit Spark WebUI at:       http://$MASTER_IP:8080/"
    echo "visit Hadoop Namenode at:   http://$MASTER_IP:50070"
    echo "ssh into master via:        ssh -i $BASEDIR/apache-hadoop-hdfs-precise/files/id_rsa -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no root@${MASTER_IP}"
    echo ""
    echo "/data mapped:               $VOLUME_MAP"
    echo ""
    echo "kill cluster via:           sudo docker kill $MASTER"
    echo "***********************************************************************"
    echo ""
    echo "to enable cluster name resolution add the following line to _the top_ of your host's /etc/resolv.conf:"
    echo "nameserver $NAMESERVER_IP"
}

function get_num_registered_workers() {
    if [[ "$SPARK_VERSION" == "0.7.3" ]]  || [[ "$image_type" == "shark" ]]; then 
        DATA=$( curl -s http://$MASTER_IP:8080/?format=json | tr -d '\n' | sed s/\"/\\\\\"/g)
    else
        DATA=$( wget -q -O - http://$MASTER_IP:8080/json | tr -d '\n' | sed s/\"/\\\\\"/g)
    fi
    NUM_REGISTERED_WORKERS=$(python -c "import json; data = \"$DATA\"; value = json.loads(data); print len(value['workers'])")
}

function wait_for_master {
    if [[ "$SPARK_VERSION" == "0.7.3" ]] || [[ "$image_type" == "shark" ]]; then
        query_string="INFO HttpServer: akka://sparkMaster/user/HttpServer started"
    else
        query_string="ui.MasterWebUI: Started Master web UI"
    fi
    echo -n "waiting for master "
    sudo docker logs $MASTER | grep "$query_string" > /dev/null
    until [ "$?" -eq 0 ]; do
	echo -n "."
	sleep 1
	sudo docker logs $MASTER | grep "$query_string" > /dev/null;
    done
    echo ""
    echo -n "waiting for nameserver to find master "
    dig master @${NAMESERVER_IP} | grep ANSWER -A1 | grep $MASTER_IP > /dev/null
    until [ "$?" -eq 0 ]; do
        echo -n "."
        sleep 1
        dig master @${NAMESERVER_IP} | grep ANSWER -A1 | grep $MASTER_IP > /dev/null;
    done
    echo ""
    sleep 3
}
