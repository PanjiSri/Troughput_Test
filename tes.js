import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';

const getLatency = new Trend('get_latency');
const postLatency = new Trend('post_latency');
const deleteLatency = new Trend('delete_latency');

const SERVICE = __ENV.SERVICE || 'webkv';
const CONSISTENCY = __ENV.CONSISTENCY || 'LINEARIZABILITY';
const BASE_URL = __ENV.BASE_URL || 'http://localhost:2302/api/kv';
const VUS = parseInt(__ENV.VUS || '1');
const DURATION = __ENV.DURATION || '30s';
const WARMUP_ITERATIONS = parseInt(__ENV.WARMUP_ITERATIONS || '25');

export const options = {
  scenarios: {
    test: {
      executor: 'constant-vus',
      vus: VUS,
      duration: DURATION,
    },
  },
};

export function setup() {
  console.log(`Starting warm-up with ${WARMUP_ITERATIONS} iterations`);
  
  const headers = {
    'XDN': SERVICE,
    'Content-Type': 'application/json',
  };
  
  for (let i = 0; i < WARMUP_ITERATIONS; i++) {
    console.log(`Warm-up progress: ${i}/${WARMUP_ITERATIONS}`);
    
    const key = `warmup_key_${i}_${Date.now()}`;
    const value = `warmup_value_${i}`;
    
    const postResult = http.post(
      `${BASE_URL}/${key}`,
      JSON.stringify({ key: key, value: value }),
      { headers: headers }
    );
    
    check(postResult, {
      'Warm-up POST status is 200': (r) => r.status === 200,
    });
    
    sleep(0.1);
    
    const getResult = http.get(
      `${BASE_URL}/${key}`,
      { headers: headers }
    );
    
    check(getResult, {
      'Warm-up GET status is 200': (r) => r.status === 200,
    });
    
    sleep(0.1);
    
    const deleteResult = http.del(
      `${BASE_URL}/${key}`,
      null,
      { headers: headers }
    );
    
    check(deleteResult, {
      'Warm-up DELETE status is 200': (r) => r.status === 200,
    });
    
    sleep(0.1);
  }
  
  console.log('Warm-up complete. Starting actual test.');
  return {};
}

export default function () {
  const key = `key_${__VU}_${__ITER}_${Date.now()}`;
  const value = `value_${__VU}_${__ITER}`;

  const headers = {
    'XDN': SERVICE,
    'Content-Type': 'application/json',
  };

  const postStartTime = new Date();
  const postResponse = http.post(
    `${BASE_URL}/${key}`,
    JSON.stringify({ key: key, value: value }),
    { headers: headers }
  );
  postLatency.add(new Date() - postStartTime);
  
  check(postResponse, {
    'POST status is 200': (r) => r.status === 200,
  });
  
  sleep(0.1);

  const getStartTime = new Date();
  const getResponse = http.get(
    `${BASE_URL}/${key}`,
    { headers: headers }
  );
  getLatency.add(new Date() - getStartTime);
  
  check(getResponse, {
    'GET status is 200': (r) => r.status === 200,
  });
  
  sleep(0.1);

  const deleteStartTime = new Date();
  const deleteResponse = http.del(
    `${BASE_URL}/${key}`,
    null,
    { headers: headers }
  );
  deleteLatency.add(new Date() - deleteStartTime);
  
  check(deleteResponse, {
    'DELETE status is 200': (r) => r.status === 200,
  });
  
  sleep(0.1);
}

export function handleSummary(data) {
  let avgGetLatency = 0;
  let avgPostLatency = 0;
  let avgDeleteLatency = 0;
  
  if (data.metrics.get_latency && data.metrics.get_latency.values) {
    avgGetLatency = data.metrics.get_latency.values.avg;
  } else {
    console.log("Warning: GET latency metrics not available");
  }
  
  if (data.metrics.post_latency && data.metrics.post_latency.values) {
    avgPostLatency = data.metrics.post_latency.values.avg;
  } else {
    console.log("Warning: POST latency metrics not available");
  }
  
  if (data.metrics.delete_latency && data.metrics.delete_latency.values) {
    avgDeleteLatency = data.metrics.delete_latency.values.avg;
  } else {
    console.log("Warning: DELETE latency metrics not available");
  }
  
  const overallLatency = (avgGetLatency + avgPostLatency + avgDeleteLatency) / 3;
  
  const csvHeader = "consistency,get_latency,post_latency,delete_latency,overall_latency\n";
  const csvRow = `${CONSISTENCY},${avgGetLatency.toFixed(2)},${avgPostLatency.toFixed(2)},${avgDeleteLatency.toFixed(2)},${overallLatency.toFixed(2)}\n`;
  
  console.log(`\n=== Results for ${CONSISTENCY} ===`);
  console.log(`GET avg: ${avgGetLatency.toFixed(2)}ms`);
  console.log(`POST avg: ${avgPostLatency.toFixed(2)}ms`);
  console.log(`DELETE avg: ${avgDeleteLatency.toFixed(2)}ms`);
  console.log(`Overall: ${overallLatency.toFixed(2)}ms`);
  
  const filename = `xdn_results_${CONSISTENCY.toLowerCase()}.csv`;
  
  return {
    'stdout': `Benchmark complete for ${CONSISTENCY}`,
    [filename]: csvHeader + csvRow,
  };
}