import http from 'k6/http';
import { check } from 'k6';
import exec from 'k6/execution';

export const options = {
    //PARALLEL
    // scenarios: {
    //     constant_load: {
    //         executor: 'constant-arrival-rate',
    //         rate: 250,
    //         timeUnit: '1s',
    //         duration: '60s',
    //         preAllocatedVUs: 50,
    //         maxVUs: 100,
    //     },
    // },
    // systemTags: ['scenario', 'status', 'method', 'url'],

    //SEQUENTIAL
    scenarios: {
        constant_vus: {
            executor: 'constant-vus',
            vus: 1,
            duration: '60s',
        },
    },
    systemTags: ['scenario', 'status', 'method', 'url'],
};

export default function () {
    const defaultReplicaPorts = [2302, 2308, 2309];
    
    let activeReplicas = defaultReplicaPorts;
    try {
        if (__ENV.ACTIVE_REPLICAS) {
            activeReplicas = JSON.parse(__ENV.ACTIVE_REPLICAS);
        }
    } catch (e) {
        console.error("Error parsing active replica:", e);
    }
        
    if (activeReplicas.length === 0) {
        console.log("No active replica active");
        return;
    }
    
    const selectedPort = activeReplicas[Math.floor(Math.random() * activeReplicas.length)];
    const url = `http://localhost:${selectedPort}/api/books`;
    
    const params = {
        headers: {
            'XDN': 'bookcatalog',
        },
    };

    const response = http.get(url, params);
    
    check(response, {
        'status is 200': (r) => r.status === 200,
    });
    
    console.log(`time=${Math.floor(exec.scenario.iterationInTest / 1000)},status=${response.status},duration=${response.timings.duration}`);
}
