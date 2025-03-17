#!/bin/bash

TEST_DURATION=60  
CRASH_TIMES=(20 40)  
OUTPUT_DIR="Serial_test_1"
K6_OUTPUT_FILE="k6_metrics.csv"
REPLICA_PORTS=(2302 2308 2309)
REPLICA_PATTERNS=(
    "c0.e0.bookcatalog.ar2.xdn.io"
    "c0.e0.bookcatalog.ar8.xdn.io"
    "c0.e0.bookcatalog.ar9.xdn.io"
)

mkdir -p $OUTPUT_DIR

ACTIVE_REPLICAS=()

for port in "${REPLICA_PORTS[@]}"; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/api/books" -H "XDN: bookcatalog")
    if [ $? -eq 0 ] && [ "$HTTP_CODE" = "200" ]; then
        echo "Replica on port $port"
        ACTIVE_REPLICAS+=($port)
    else
        echo "Problem on port $port (HTTP status: $HTTP_CODE)"
    fi
done

if [ ${#ACTIVE_REPLICAS[@]} -eq 0 ]; then
    echo "Exit, No Replica Found"
    exit 1
fi

export ACTIVE_REPLICAS="[${ACTIVE_REPLICAS[*]}]"
echo "Active replicas: $ACTIVE_REPLICAS"

echo "Warm-up phase"
for port in "${ACTIVE_REPLICAS[@]}"; do
  echo "Warming up replica on port $port"
  for ((i=1; i<=500; i++)); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/api/books" -H "XDN: bookcatalog")
    
    if [ $((i % 25)) -eq 0 ]; then
      echo "  Replica $port: $i/500 requests completed"
    fi
  done
  echo "  Replica $port: warm-up completed"
done
echo "Warm-up phase completed"
echo

crash_replica() {
    local pattern=$1
    local timestamp=$2
    
    echo "[$timestamp] Stopping container : $pattern"
    
    container_id=$(docker ps | grep bookcatalog | grep $pattern | awk '{print $1}')
    
    if [ -z "$container_id" ]; then
        echo "[$timestamp] WARNING: No container : $pattern"
        return 1
    fi
    
    docker stop $container_id
    
    if [ $? -eq 0 ]; then
        echo "[$timestamp] Successfully stopped container $container_id"
    else
        echo "[$timestamp] ERROR: Failed to stop container $container_id"
    fi
}

echo "Load test for $TEST_DURATION seconds"
k6 run --out csv=$OUTPUT_DIR/$K6_OUTPUT_FILE xdn_load_test.js &
K6_PID=$!

> $OUTPUT_DIR/crash_times.txt

for i in ${!CRASH_TIMES[@]}; do
    (
        crash_time=${CRASH_TIMES[$i]}
        pattern=${REPLICA_PATTERNS[$i]}
        
        echo "Scheduling server crash at $crash_time seconds"
        sleep $crash_time
        
        echo "$crash_time" >> $OUTPUT_DIR/crash_times.txt
        
        crash_replica $pattern $crash_time
    ) &
done

echo "Test running..."
wait $K6_PID
echo "Test completed"

echo "Generate Visualization"
python3 visualize_results.py --k6-output $OUTPUT_DIR/$K6_OUTPUT_FILE --crash-times $OUTPUT_DIR/crash_times.txt --output $OUTPUT_DIR/throughput.png

echo "Visualization completed!"
