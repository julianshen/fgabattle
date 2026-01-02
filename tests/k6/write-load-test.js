import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const writeErrorRate = new Rate('write_errors');
const writeDuration = new Trend('write_duration');
const tuplesWritten = new Counter('tuples_written');

// Test configuration
export const options = {
  stages: [
    { duration: '20s', target: 5 },    // Gentle ramp up (writes are heavy)
    { duration: '40s', target: 10 },   // Stay at 10 writers
    { duration: '20s', target: 20 },   // Brief spike
    { duration: '40s', target: 10 },   // Back down
    { duration: '20s', target: 0 },    // Ramp down
  ],
  thresholds: {
    'http_req_duration': ['p(95)<500', 'p(99)<1000'],
    'write_errors': ['rate<0.01'],
    'http_req_failed': ['rate<0.01'],
  },
};

// Environment variables
const BASE_URL = __ENV.OPENFGA_URL || 'http://localhost:8080';
const STORE_ID = __ENV.STORE_ID;
const MODEL_ID = __ENV.MODEL_ID;
const CLEANUP = __ENV.CLEANUP === 'true'; // Whether to delete after writing

let writeCounter = 0;

function getRandomItem(array) {
  return array[Math.floor(Math.random() * array.length)];
}

function getTestId() {
  return `test-${Date.now()}-${Math.floor(Math.random() * 10000)}`;
}

export function setup() {
  if (!STORE_ID) {
    throw new Error('STORE_ID environment variable is required');
  }

  console.log(`Testing writes against store: ${STORE_ID}`);
  console.log(`Cleanup enabled: ${CLEANUP}`);

  return { storeId: STORE_ID, modelId: MODEL_ID };
}

export default function (data) {
  const testId = getTestId();
  const userId = writeCounter++;

  // Generate test tuples to write
  const relations = ['identity_based_read', 'identity_based_write'];
  const relation = getRandomItem(relations);

  const tuples = [
    {
      user: `user:test-user-${userId}`,
      relation: relation,
      object: `s3_bucket:test-bucket-${testId}`,
    },
  ];

  // Add a second tuple sometimes (test batch writes)
  if (Math.random() > 0.5) {
    tuples.push({
      user: `user:test-user-${userId}`,
      relation: 'identity_based_describe',
      object: `ec2_instance:test-instance-${testId}`,
    });
  }

  const payload = JSON.stringify({
    writes: {
      tuple_keys: tuples,
    },
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
    tags: {
      tuple_count: tuples.length,
    },
  };

  const startTime = new Date().getTime();
  const response = http.post(
    `${BASE_URL}/stores/${data.storeId}/write`,
    payload,
    params
  );
  const duration = new Date().getTime() - startTime;

  // Record metrics
  writeDuration.add(duration);
  tuplesWritten.add(tuples.length);

  // Check response
  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'write succeeded': (r) => {
      try {
        const body = JSON.parse(r.body);
        // OpenFGA returns empty object on success
        return r.status === 200;
      } catch (e) {
        return false;
      }
    },
    'response time < 1000ms': (r) => r.timings.duration < 1000,
  });

  writeErrorRate.add(!success);

  // Cleanup: delete the tuples we just wrote
  if (CLEANUP && success) {
    const deletePayload = JSON.stringify({
      deletes: {
        tuple_keys: tuples,
      },
    });

    http.post(
      `${BASE_URL}/stores/${data.storeId}/write`,
      deletePayload,
      params
    );
  }

  // Log slow writes
  if (duration > 500) {
    console.log(`Slow write (${duration}ms): ${tuples.length} tuples`);
  }

  sleep(0.3); // Moderate delay for writes
}

export function teardown(data) {
  console.log('Write test completed');
  if (!CLEANUP) {
    console.log('Warning: Test tuples were not cleaned up. You may want to clean the store.');
  }
}
