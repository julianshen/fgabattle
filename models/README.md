# OpenFGA Authorization Models

This directory contains various authorization models demonstrating different OpenFGA patterns and use cases.

## Models Overview

### 1. document-simple.fga
**Use Case**: Basic document permissions (Google Docs style)

**Key Features**:
- Simple hierarchical permissions: owner → editor → viewer
- Computed permissions (can_read, can_write, can_delete)
- Good starting point for learning OpenFGA

**Relations**:
- `owner`: Full control over document
- `editor`: Can modify but not delete (inherits from owner)
- `viewer`: Read-only access (inherits from editor)

**Example Scenarios**:
- Document collaboration systems
- Simple file sharing applications
- Content management systems

---

### 2. space-page-hierarchy.fga
**Use Case**: Confluence/Notion-style workspace with external access control

**Key Features**:
- **Conditional relationships**: Uses `external_condition` to control external user access
- **Hierarchical permissions**: Pages inherit permissions from parent space
- **Organization membership**: Supports org-level access control
- **Nested pages**: Pages can have page parents

**Relations**:
- **Space**: viewer, editor, admin with conditional access
- **Page**: Inherits can_view and can_edit from parent

**Condition**:
```
external_condition(external: bool, allow_external: bool)
```
- Controls whether external users can access resources
- Enables fine-grained access based on user context

**Example Scenarios**:
- Team collaboration platforms (Notion, Confluence)
- Knowledge bases with guest access
- Documentation systems with external sharing

**Test Cases**:
```bash
# Check if external user can view space
fga query check --user user:external_guest \
  --relation can_view \
  --object space:engineering \
  --context '{"external": true, "allow_external": true}'

# Check page permission inheritance
fga query check --user user:alice \
  --relation can_edit \
  --object page:sub-section-1
```

---

### 3. team-based.fga
**Use Case**: Organization → Team → Project hierarchy

**Key Features**:
- **Three-level hierarchy**: Organization > Team > Project
- **Transitive relationships**: Team members inherit org permissions
- **Role-based access**: Leads have special privileges
- **Cross-object references**: Projects reference teams, teams reference orgs

**Relations**:
- **Organization**: owner > admin > member
- **Team**: lead, member with parent_org reference
- **Project**: owner, contributor with parent_team reference

**Permission Flow**:
```
Organization Admin → Team Management
Team Lead → Project Deletion
Team Member → Project Contribution
```

**Example Scenarios**:
- Corporate project management systems
- Multi-tenant SaaS platforms
- Enterprise resource planning

**Test Cases**:
```bash
# Org admin can manage team
fga query check --user user:bob \
  --relation can_manage \
  --object team:backend

# Team member can read project
fga query check --user user:eve \
  --relation can_read \
  --object project:api-service
```

---

### 4. github-style.fga
**Use Case**: Complete GitHub-like repository permission system

**Key Features**:
- **Repository roles**: owner, admin, maintainer, writer, reader
- **Nested resources**: Issues and PRs belong to repositories
- **Permission inheritance**: Issues/PRs inherit repo permissions
- **Organization integration**: Org members can have repo access

**Relations**:

**Repository**:
- `owner`: Full control (user or organization)
- `admin`: Administrative access
- `maintainer`: Maintain releases and settings
- `writer`: Push code
- `reader`: Read-only access

**Issue/Pull Request**:
- `author`: Creator of the issue/PR
- Inherits repo permissions for view/edit/comment

**Permission Matrix**:

| Role | Read | Write | Admin | Delete |
|------|------|-------|-------|--------|
| reader | ✓ | | | |
| writer | ✓ | ✓ | | |
| maintainer | ✓ | ✓ | | |
| admin | ✓ | ✓ | ✓ | |
| owner | ✓ | ✓ | ✓ | ✓ |

**Example Scenarios**:
- Source code hosting platforms
- Code review systems
- CI/CD platforms

**Test Cases**:
```bash
# Org member as maintainer can approve PR
fga query check --user user:bob \
  --relation can_approve \
  --object pull_request:pr-456

# Issue author can edit their issue
fga query check --user user:frank \
  --relation can_edit \
  --object issue:bug-123
```

---

### 5. folder-hierarchy.fga
**Use Case**: Nested folder/file system with permission inheritance

**Key Features**:
- **Recursive hierarchy**: Folders can contain folders
- **Dual inheritance**: Files inherit from folder AND have direct permissions
- **Permission propagation**: Parent folder permissions cascade down
- **Flexible ownership**: Each file/folder has independent owner

**Relations**:

**Folder**:
- `parent`: Reference to parent folder
- `owner`, `editor`, `viewer`: Direct permissions
- `parent_viewer`: Inherited from parent
- Computed: can_read includes parent_viewer

**File**:
- `parent`: Reference to parent folder
- `owner`, `editor`, `viewer`: Direct permissions
- `parent_viewer`, `parent_editor`: Inherited from parent folder
- Computed: can_read, can_write include parent permissions

**Permission Cascade Example**:
```
folder:root (alice: owner, charlie: viewer)
  └─ folder:projects (david: editor)
      └─ folder:2026-planning (eve: viewer)
          └─ file:budget.xlsx (frank: owner)
```

**Access Matrix**:
| User | budget.xlsx can_read | budget.xlsx can_write |
|------|---------------------|----------------------|
| alice | ✓ (root owner) | ✓ (root owner) |
| charlie | ✓ (root viewer) | ✗ |
| david | ✓ (projects editor) | ✓ (projects editor) |
| eve | ✓ (folder viewer) | ✗ |
| frank | ✓ (file owner) | ✓ (file owner) |

**Example Scenarios**:
- File storage systems (Dropbox, Google Drive)
- Document management systems
- Content repositories

**Test Cases**:
```bash
# Root viewer can read nested file
fga query check --user user:charlie \
  --relation can_read \
  --object file:budget.xlsx

# Folder editor can write to nested file
fga query check --user user:david \
  --relation can_write \
  --object file:budget.xlsx
```

---

### 6. aws-iam-style.fga
**Use Case**: AWS IAM-style cloud resource authorization

**Key Features**:
- **Multi-level hierarchy**: Account → Users/Groups/Roles → Resources
- **Role assumption**: Users can assume roles for temporary credentials
- **Identity-based policies**: Permissions attached to users/groups/roles
- **Resource-based policies**: Direct resource access grants
- **Service-specific permissions**: Different actions per AWS service
- **Account-level administration**: Account admins have broad access

**IAM Components**:

**Identity Management**:
- `user`: IAM users (people or applications)
- `group`: Collections of users with shared permissions
- `role`: Assumable identities with attached policies
- `policy`: Permission definitions (not fully modeled, simplified as relations)

**AWS Resources**:
- `s3_bucket`: S3 storage buckets with read/write/delete permissions
- `ec2_instance`: EC2 instances with start/stop/terminate/describe actions
- `dynamodb_table`: DynamoDB tables with read/write/admin permissions
- `lambda_function`: Lambda functions with invoke/update/delete actions

**Permission Model**:

**S3 Bucket Permissions**:
```
can_read: identity_based_read OR resource_policy_allows OR account_admin OR owner
can_write: identity_based_write OR resource_policy_allows OR account_admin OR owner
can_delete: identity_based_delete OR account_admin OR owner
```

**EC2 Instance Permissions**:
```
can_start: identity_based_start OR account_admin OR owner
can_stop: identity_based_stop OR account_admin OR owner
can_terminate: identity_based_terminate OR account_admin OR owner
can_describe: identity_based_describe OR account_admin OR owner
```

**Permission Evaluation Flow**:
1. Check identity-based permissions (user/group/role)
2. Check resource-based permissions (bucket policies, etc.)
3. Check account-level admin access
4. Check resource ownership
5. Grant access if ANY condition is met (union)

**IAM Scenarios Demonstrated**:

**Scenario 1: Group-based Access**
```
User: charlie
Group: developers (charlie is member)
Bucket: app-data-bucket (developers have read access)
Result: charlie can read app-data-bucket (via group membership)
```

**Scenario 2: Role Assumption**
```
User: bob
Role: ec2-admin-role (bob can assume)
EC2: web-server-01 (ec2-admin-role can start/stop/terminate)
Result: bob (when assuming ec2-admin-role) can manage web-server-01
```

**Scenario 3: Cross-Service Access (Lambda → DynamoDB)**
```
Lambda: api-handler
Execution Role: lambda-execution-role
DynamoDB: users-table (lambda-execution-role has write access)
Result: api-handler can write to users-table via execution role
```

**Scenario 4: Resource-Based Policy**
```
Role: s3-read-role
Bucket: app-data-bucket (resource_policy_allows s3-read-role)
Lambda: (assumes s3-read-role)
Result: Lambda can read bucket via resource-based policy
```

**Scenario 5: Account Admin Override**
```
User: alice (account admin)
Any Resource: in prod-account
Result: alice has full access to all resources in the account
```

**Example Test Cases**:
```bash
# Test 1: Group member can read S3 bucket
fga query check --user user:charlie \
  --relation can_read \
  --object s3_bucket:app-data-bucket
# Expected: ALLOWED (via group:developers#member)

# Test 2: User with assumed role can stop EC2
fga query check --user role:ec2-admin-role \
  --relation can_stop \
  --object ec2_instance:web-server-01
# Expected: ALLOWED (identity_based_stop)

# Test 3: Lambda execution role can write to DynamoDB
fga query check --user role:lambda-execution-role \
  --relation can_write \
  --object dynamodb_table:users-table
# Expected: ALLOWED (identity_based_write)

# Test 4: Account admin can access any resource
fga query check --user user:alice \
  --relation can_delete \
  --object s3_bucket:public-assets
# Expected: ALLOWED (account admin)

# Test 5: Developer can invoke Lambda function
fga query check --user user:david \
  --relation can_invoke \
  --object lambda_function:api-handler
# Expected: ALLOWED (via group:developers membership)
```

**IAM Concepts Modeled**:
- ✅ Users, Groups, Roles
- ✅ Group membership
- ✅ Role assumption (assumable_by)
- ✅ Identity-based permissions
- ✅ Resource-based permissions (bucket policies)
- ✅ Account-level administration
- ✅ Service-specific actions
- ✅ Lambda execution roles
- ✅ Cross-service access
- ⚠️ Policy documents (simplified - not JSON policies)
- ⚠️ Explicit deny (not modeled - OpenFGA uses allow-only)
- ⚠️ Permission boundaries (not modeled)
- ⚠️ Conditions (partially - could add with OpenFGA conditions)

**Limitations vs Real AWS IAM**:
1. **No Explicit Deny**: OpenFGA doesn't have a deny concept - it's allow-only
2. **Simplified Policies**: Real IAM uses JSON policy documents with complex evaluation logic
3. **No SCPs**: Service Control Policies for Organizations not modeled
4. **No Permission Boundaries**: Not implemented in this model
5. **Limited Conditions**: Could add more contextual conditions (IP, time, MFA)
6. **No Principal Wildcards**: Can't express "all users in account"

**Example Scenarios**:
- Multi-tenant cloud platforms
- Internal cloud resource management
- DevOps automation with role-based access
- Microservices accessing cloud resources
- CI/CD pipelines with temporary credentials

**Real-World Applications**:
- Cloud infrastructure platforms
- Platform-as-a-Service (PaaS) authorization
- Multi-account AWS organization management
- DevOps tooling with cloud provider integration
- Kubernetes IRSA (IAM Roles for Service Accounts) style access

---

## Testing Models

### Quick Test with HTTP API

1. **Create a store**:
```bash
curl -X POST http://localhost:8080/stores \
  -H "Content-Type: application/json" \
  -d '{"name": "test-store"}' | jq .
```

2. **Upload a model** (requires JSON format):
```bash
# Convert .fga to JSON first, then upload
curl -X POST "http://localhost:8080/stores/{STORE_ID}/authorization-models" \
  -H "Content-Type: application/json" \
  -d @models/MODEL_NAME.json
```

3. **Write tuples**:
```bash
curl -X POST "http://localhost:8080/stores/{STORE_ID}/write" \
  -H "Content-Type: application/json" \
  -d @tuples/MODEL_NAME/tuples.json
```

4. **Check authorization**:
```bash
curl -X POST "http://localhost:8080/stores/{STORE_ID}/check" \
  -H "Content-Type: application/json" \
  -d '{
    "tuple_key": {
      "user": "user:alice",
      "relation": "can_read",
      "object": "document:planning-doc"
    },
    "authorization_model_id": "{MODEL_ID}"
  }'
```

### Using FGA CLI

```bash
# Create store
fga store create --name="test-store"

# Write model
fga model write --file=models/MODEL_NAME.fga

# Write tuples
fga tuple write --file=tuples/MODEL_NAME/tuples.json

# Check permission
fga query check --user=user:alice \
  --relation=can_read \
  --object=document:planning-doc

# List accessible objects
fga query list-objects --type=document \
  --relation=can_read \
  --user=user:alice
```

## Model Design Patterns

### Pattern 1: Direct Assignment
```
define viewer: [user]
```
Users are directly assigned the viewer role.

### Pattern 2: Union (OR)
```
define can_read: viewer or editor
```
Permission granted if user is viewer OR editor.

### Pattern 3: Computed Userset
```
define can_read: viewer
```
Permission computed from another relation.

### Pattern 4: Tuple-to-Userset (Inheritance)
```
define parent: [folder]
define can_read: viewer from parent
```
Inherit permissions from parent object.

### Pattern 5: Conditional Relationships
```
define viewer: [user with external_condition]

condition external_condition(external: bool, allow_external: bool) {
  !external || allow_external
}
```
Permissions granted based on runtime context.

### Pattern 6: Hierarchical References
```
type org
  relations
    define member: [user, org#member]
```
Support recursive organizational hierarchies.

## Best Practices

1. **Start Simple**: Begin with document-simple.fga and add complexity as needed
2. **Test Incrementally**: Verify each relation works before adding the next
3. **Use Descriptive Names**: Make relations self-documenting (can_read vs read)
4. **Document Edge Cases**: Note special permission combinations
5. **Performance Considerations**: Deep hierarchies can impact check latency
6. **Validate Models**: Test both positive and negative cases

## Common Pitfalls

1. **Circular References**: Avoid A → B → A permission cycles
2. **Missing Direct Relations**: Ensure bracket definitions for tuple-to-userset
3. **Condition Syntax**: Context conditions require specific parameter types
4. **Type Safety**: Ensure user/object types match relation definitions

## Next Steps

- Create K6 load tests for each model
- Add more complex conditional scenarios
- Test with multiple OpenFGA implementations
- Document performance characteristics
- Create migration guides between models
