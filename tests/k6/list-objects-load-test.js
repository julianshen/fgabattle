import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const listErrorRate = new Rate('list_errors');
const listDuration = new Trend('list_duration');
const objectsFound = new Counter('objects_found');

// Test configuration
export const options = {
  stages: [
    { duration: '30s', target: 5 },    // Ramp up slowly (list-objects is heavier)
    { duration: '1m', target: 20 },    // Stay at 20 users
    { duration: '30s', target: 50 },   // Spike to 50
    { duration: '1m', target: 50 },    // Hold at 50
    { duration: '30s', target: 0 },    // Ramp down
  ],
  thresholds: {
    'http_req_duration': ['p(95)<2000', 'p(99)<5000'],  // List-objects is slower
    'list_errors': ['rate<0.01'],
    'http_req_failed': ['rate<0.01'],
  },
};

// Environment variables
const BASE_URL = __ENV.OPENFGA_URL || 'http://localhost:8080';
const STORE_ID = __ENV.STORE_ID;
const MODEL_ID = __ENV.MODEL_ID;

// Test data
const users = [
  'user:user-0000-00001',
  'user:user-0000-00042',
  'user:user-0000-00123',
  'user:user-0001-00001',
  'group:group-0000-000#member',
  'role:role-0000-0001',
];

const objectTypes = [
  's3_bucket',
  'ec2_instance',
  'dynamodb_table',
  'lambda_function',
];

const relationsByType = {
  s3_bucket: ['can_read', 'can_write', 'can_delete'],
  ec2_instance: ['can_start', 'can_stop', 'can_describe'],
  dynamodb_table: ['can_read', 'can_write'],
  lambda_function: ['can_invoke', 'can_update'],
};

function getRandomItem(array) {
  return array[Math.floor(Math.random() * array.length)];
}

export function setup() {
  if (!STORE_ID || !MODEL_ID) {
    throw new Error('STORE_ID and MODEL_ID environment variables are required');
  }

  console.log(`Testing list-objects against store: ${STORE_ID}`);
  console.log(`Using model: ${MODEL_ID}`);

  return { storeId: STORE_ID, modelId: MODEL_ID };
}

export default function (data) {
  const objectType = getRandomItem(objectTypes);
  const user = getRandomItem(users);
  const relation = getRandomItem(relationsByType[objectType]);

  const payload = JSON.stringify({
    authorization_model_id: data.modelId,
    type: objectType,
    relation: relation,
    user: user,
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
    tags: {
      object_type: objectType,
      relation: relation,
    },
  };

  const startTime = new Date().getTime();
  const response = http.post(
    `${BASE_URL}/stores/${data.storeId}/list-objects`,
    payload,
    params
  );
  const duration = new Date().getTime() - startTime;

  // Record metrics
  listDuration.add(duration);

  // Check response
  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'response has objects array': (r) => {
      try {
        const body = JSON.parse(r.body);
        return Array.isArray(body.objects);
      } catch (e) {
        return false;
      }
    },
    'response time < 5000ms': (r) => r.timings.duration < 5000,
  });

  // Count objects found
  try {
    const body = JSON.parse(response.body);
    if (body.objects) {
      objectsFound.add(body.objects.length);

      // Log if many objects found (interesting case)
      if (body.objects.length > 50) {
        console.log(`Found ${body.objects.length} objects for ${user} ${relation} ${objectType}`);
      }
    }
  } catch (e) {
    // Ignore parse errors
  }

  listErrorRate.add(!success);

  // Log slow requests
  if (duration > 2000) {
    console.log(`Slow list-objects (${duration}ms): ${user} ${relation} ${objectType}`);
  }

  sleep(0.5); // Longer delay for list-objects
}

export function teardown(data) {
  console.log('List-objects test completed');
}
