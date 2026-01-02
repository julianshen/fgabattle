import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const batchErrorRate = new Rate('batch_errors');
const batchDuration = new Trend('batch_duration');
const checksPerBatch = new Trend('checks_per_batch');
const totalChecks = new Counter('total_checks');

// Test configuration
export const options = {
  stages: [
    { duration: '30s', target: 5 },    // Gentle start
    { duration: '1m', target: 15 },    // Moderate load
    { duration: '30s', target: 30 },   // Peak load
    { duration: '1m', target: 15 },    // Back down
    { duration: '30s', target: 0 },    // Ramp down
  ],
  thresholds: {
    'http_req_duration': ['p(95)<1000', 'p(99)<2000'],
    'batch_errors': ['rate<0.01'],
    'http_req_failed': ['rate<0.01'],
  },
};

// Environment variables
const BASE_URL = __ENV.OPENFGA_URL || 'http://localhost:8080';
const STORE_ID = __ENV.STORE_ID;
const MODEL_ID = __ENV.MODEL_ID;
const MAX_BATCH_SIZE = parseInt(__ENV.MAX_BATCH_SIZE || '10');

// Test data
const users = [
  'user:user-0000-00001',
  'user:user-0000-00042',
  'user:user-0000-00123',
  'user:user-0001-00001',
];

const testCases = [
  { resource: 's3_bucket:bucket-0000-00001', relation: 'can_read' },
  { resource: 's3_bucket:bucket-0000-00005', relation: 'can_write' },
  { resource: 'ec2_instance:instance-0000-00001', relation: 'can_start' },
  { resource: 'ec2_instance:instance-0000-00042', relation: 'can_stop' },
  { resource: 'dynamodb_table:table-0000-00001', relation: 'can_read' },
  { resource: 'dynamodb_table:table-0000-00005', relation: 'can_write' },
  { resource: 'lambda_function:function-0000-00001', relation: 'can_invoke' },
  { resource: 'lambda_function:function-0000-00042', relation: 'can_update' },
];

function getRandomItem(array) {
  return array[Math.floor(Math.random() * array.length)];
}

function getRandomInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

export function setup() {
  if (!STORE_ID || !MODEL_ID) {
    throw new Error('STORE_ID and MODEL_ID environment variables are required');
  }

  console.log(`Testing batch check against store: ${STORE_ID}`);
  console.log(`Max batch size: ${MAX_BATCH_SIZE}`);

  return { storeId: STORE_ID, modelId: MODEL_ID };
}

export default function (data) {
  // Generate a batch of checks
  const batchSize = getRandomInt(2, MAX_BATCH_SIZE);
  const checks = [];

  for (let i = 0; i < batchSize; i++) {
    const user = getRandomItem(users);
    const testCase = getRandomItem(testCases);

    checks.push({
      tuple_key: {
        user: user,
        relation: testCase.relation,
        object: testCase.resource,
      },
      authorization_model_id: data.modelId,
    });
  }

  const payload = JSON.stringify({
    checks: checks,
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
    tags: {
      batch_size: batchSize,
    },
  };

  const startTime = new Date().getTime();
  const response = http.post(
    `${BASE_URL}/stores/${data.storeId}/batch-check`,
    payload,
    params
  );
  const duration = new Date().getTime() - startTime;

  // Record metrics
  batchDuration.add(duration);
  checksPerBatch.add(batchSize);
  totalChecks.add(batchSize);

  // Check response
  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'response has results': (r) => {
      try {
        const body = JSON.parse(r.body);
        return Array.isArray(body.result) && body.result.length === batchSize;
      } catch (e) {
        return false;
      }
    },
    'all checks completed': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.result.every(result => result.hasOwnProperty('allowed'));
      } catch (e) {
        return false;
      }
    },
    'response time reasonable': (r) => {
      // Allow ~100ms per check in batch
      return r.timings.duration < (batchSize * 100);
    },
  });

  batchErrorRate.add(!success);

  // Log performance metrics
  if (success) {
    try {
      const avgTimePerCheck = duration / batchSize;
      if (avgTimePerCheck > 100) {
        console.log(`Slow batch (${avgTimePerCheck.toFixed(2)}ms per check): ${batchSize} checks in ${duration}ms`);
      }
    } catch (e) {
      // Ignore
    }
  }

  sleep(0.2);
}

export function teardown(data) {
  console.log('Batch check test completed');
}
