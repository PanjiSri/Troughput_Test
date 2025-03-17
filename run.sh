#!/bin/bash

TEST_DURATION=60  
CRASH_TIME=20     
OUTPUT_DIR="serial_test_1"
K6_OUTPUT_FILE="k6_metrics.csv"
REPLICA_PORTS=(2302 2308 2309)
CRASH_PORT=2302   
WARMUP_REQUESTS=200  

if [ ! -f "xdn_load_test.js" ]; then
    echo "ERROR: xdn_load_test.js not found."
    exit 1
fi

sed -i "s/const CRASH_TIME_SECONDS = [0-9]*;/const CRASH_TIME_SECONDS = $CRASH_TIME;/" xdn_load_test.js
echo "K6 script crash : $CRASH_TIME seconds"

mkdir -p $OUTPUT_DIR

ACTIVE_REPLICAS=()

for port in "${REPLICA_PORTS[@]}"; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/api/books" -H "XDN: bookcatalog")
    if [ $? -eq 0 ] && [ "$HTTP_CODE" = "200" ]; then
        echo "Replica on port $port is active"
        ACTIVE_REPLICAS+=($port)
    else
        echo "Problem on port $port (HTTP status: $HTTP_CODE)"
    fi
done

if [ ${#ACTIVE_REPLICAS[@]} -eq 0 ]; then
    echo "ERROR: No active replicas found. Exiting."
    exit 1
fi

if [[ ! " ${ACTIVE_REPLICAS[*]} " =~ " ${CRASH_PORT} " ]]; then
    # echo "The port scheduled for crash ($CRASH_PORT) is not active"
    exit 1
fi

export ACTIVE_REPLICAS="[${ACTIVE_REPLICAS[*]}]"
echo "Active replicas: $ACTIVE_REPLICAS"

echo -e "\n=== Starting Warm-up Phase ==="
for port in "${ACTIVE_REPLICAS[@]}"; do
    echo "Warming up replica on port $port..."
    
    start_time=$(date +%s.%N)
    
    for ((i=1; i<=$WARMUP_REQUESTS; i++)); do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port/api/books" -H "XDN: bookcatalog")
        
        if [ $((i % 100)) -eq 0 ]; then
            echo "  Progress: $i/$WARMUP_REQUESTS requests completed"
        fi
    done
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)
    rps=$(echo "$WARMUP_REQUESTS / $duration" | bc)
    
    echo " Replica $port: warm-up completed ($WARMUP_REQUESTS requests in $(printf "%.2f" $duration) seconds, $(printf "%.2f" $rps) req/sec)"
done

sleep 2
echo -e "=== Warm-up Phase Completed ===\n"

crash_replica() {
    local port=$1
    
    echo "$(date +%H:%M:%S) Crashing replica on port: $port"
    
    fuser -k $port/tcp
    
    if [ $? -eq 0 ]; then
        echo "$(date +%H:%M:%S) Successfully crashed replica on port $port"
    else
        echo "$(date +%H:%M:%S) Failed to crash replica on port $port"
    fi
}

echo $CRASH_TIME > $OUTPUT_DIR/crash_times.txt

echo -e "=== Starting Load Test (Duration: ${TEST_DURATION}s) ===\n"

k6 run --out csv=$OUTPUT_DIR/$K6_OUTPUT_FILE xdn_load_test.js &
K6_PID=$!
TEST_START_TIME=$(date +%s)

(
    echo "Scheduling crash of port $CRASH_PORT at $CRASH_TIME seconds from now"
    
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - TEST_START_TIME))
    SLEEP_TIME=$((CRASH_TIME - ELAPSED))
    
    if [ $SLEEP_TIME -lt 0 ]; then
        SLEEP_TIME=0
    fi
    
    echo "Will crash port in $SLEEP_TIME seconds"
    sleep $SLEEP_TIME
    
    CRASH_EXACT_TIME=$(date +%s)
    CRASH_ELAPSED=$((CRASH_EXACT_TIME - TEST_START_TIME))
    echo "Actual crash time is $CRASH_ELAPSED seconds into the test"
    
    crash_replica $CRASH_PORT
) &

echo "Test is running..."
wait $K6_PID
echo -e "\n=== Load Test Completed ===\n"

echo "Generating throughput visualization"
python3 visualize_results.py --k6-output $OUTPUT_DIR/$K6_OUTPUT_FILE --crash-times $OUTPUT_DIR/crash_times.txt --output $OUTPUT_DIR/throughput.png

echo -e "\n=== Test completed successfully! ==="
