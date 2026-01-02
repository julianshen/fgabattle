import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

// Custom metrics
const checkErrorRate = new Rate('check_errors');
const checkDuration = new Trend('check_duration');

// Test configuration
export const options = {
  stages: [
    { duration: '30s', target: 10 },   // Ramp up to 10 users
    { duration: '1m', target: 50 },    // Stay at 50 users for 1 minute
    { duration: '30s', target: 100 },  // Spike to 100 users
    { duration: '1m', target: 100 },   // Hold at 100 users
    { duration: '30s', target: 0 },    // Ramp down
  ],
  thresholds: {
    'http_req_duration': ['p(95)<200', 'p(99)<500'],  // 95% under 200ms, 99% under 500ms
    'check_errors': ['rate<0.01'],                     // Error rate below 1%
    'http_req_failed': ['rate<0.01'],                  // HTTP failure rate below 1%
  },
};

// Environment variables
const BASE_URL = __ENV.OPENFGA_URL || 'http://localhost:8080';
const STORE_ID = __ENV.STORE_ID;
const MODEL_ID = __ENV.MODEL_ID;

// Test data - will be randomized during execution
const users = [
  'user:user-0000-00001',
  'user:user-0000-00042',
  'user:user-0000-00123',
  'user:user-0000-00456',
  'user:user-0001-00001',
];

const resources = {
  s3_bucket: [
    'bucket-0000-00001',
    'bucket-0000-00005',
    'bucket-0000-00010',
    'bucket-0001-00001',
  ],
  ec2_instance: [
    'instance-0000-00001',
    'instance-0000-00042',
    'instance-0001-00001',
  ],
  dynamodb_table: [
    'table-0000-00001',
    'table-0000-00005',
  ],
  lambda_function: [
    'function-0000-00001',
    'function-0000-00042',
  ],
};

const relations = {
  s3_bucket: ['can_read', 'can_write', 'can_delete'],
  ec2_instance: ['can_start', 'can_stop', 'can_describe', 'can_terminate'],
  dynamodb_table: ['can_read', 'can_write', 'can_admin'],
  lambda_function: ['can_invoke', 'can_update', 'can_delete'],
};

function getRandomItem(array) {
  return array[Math.floor(Math.random() * array.length)];
}

export function setup() {
  // Validate environment variables
  if (!STORE_ID || !MODEL_ID) {
    throw new Error('STORE_ID and MODEL_ID environment variables are required');
  }

  console.log(`Testing against store: ${STORE_ID}`);
  console.log(`Using model: ${MODEL_ID}`);
  console.log(`Base URL: ${BASE_URL}`);

  return { storeId: STORE_ID, modelId: MODEL_ID };
}

export default function (data) {
  // Pick random resource type
  const resourceTypes = Object.keys(resources);
  const resourceType = getRandomItem(resourceTypes);

  // Pick random user, resource, and relation
  const user = getRandomItem(users);
  const resourceId = getRandomItem(resources[resourceType]);
  const resource = `${resourceType}:${resourceId}`;
  const relation = getRandomItem(relations[resourceType]);

  const payload = JSON.stringify({
    tuple_key: {
      user: user,
      relation: relation,
      object: resource,
    },
    authorization_model_id: data.modelId,
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
    tags: {
      resource_type: resourceType,
      relation: relation,
    },
  };

  const startTime = new Date().getTime();
  const response = http.post(
    `${BASE_URL}/stores/${data.storeId}/check`,
    payload,
    params
  );
  const duration = new Date().getTime() - startTime;

  // Record metrics
  checkDuration.add(duration);

  // Check response
  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'response has allowed field': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.hasOwnProperty('allowed');
      } catch (e) {
        return false;
      }
    },
    'response time < 500ms': (r) => r.timings.duration < 500,
  });

  checkErrorRate.add(!success);

  // Log slow requests
  if (duration > 500) {
    console.log(`Slow request (${duration}ms): ${user} ${relation} ${resource}`);
  }

  sleep(0.1); // Small delay between requests
}

export function teardown(data) {
  console.log('Test completed');
  console.log(`Store ID: ${data.storeId}`);
  console.log(`Model ID: ${data.modelId}`);
}
