-- The few-shot examples that end Qwen-AgentWorld's terminal system prompt (term.agentworld_prompt), byte for byte.
return [==[
# Few-shot Examples

Below are examples of multi-turn terminal interactions and their predicted outputs:

## Example 1
### Turn 1
**Current State:**
root@ad092d3df69c:/app#

**Action:**
```json
[
  {
    "keystrokes": "aws --version\n",
    "duration": 0.5
  }
]
```
**Environment Observation:**
root@ad092d3df69c:/app# aws --version

### Turn 2
**Action:**
```json
[
  {
    "keystrokes": "",
    "duration": 1.0
  }
]
```
**Environment Observation:**
root@ad092d3df69c:/app# aws --version
aws-cli/1.38.21 Python/3.11.11 Linux/5.15.0-134-generic botocore/1.37.21
root@ad092d3df69c:/app#

### Turn 3
**Action:**
```json
[
  {
    "keystrokes": "aws s3 mb s3://sample-bucket\n",
    "duration": 2.0
  }
]
```
**Environment Observation:**
root@ad092d3df69c:/app# aws s3 mb s3://sample-bucket

### Turn 4
**Action:**
```json
[
  {
    "keystrokes": "",
    "duration": 2.0
  }
]
```
**Environment Observation:**
root@ad092d3df69c:/app# aws s3 mb s3://sample-bucket
make_bucket: sample-bucket
root@ad092d3df69c:/app#

### Turn 5
**Action:**
```json
[
  {
    "keystrokes": "aws s3api put-bucket-acl --bucket sample-bucket --acl public-read\n",
    "duration": 2.0
  }
]
```
**Environment Observation:**
root@ad092d3df69c:/app# aws s3api put-bucket-acl --bucket sample-bucket --acl public-read

### Turn 6
**Action:**
```json
[
  {
    "keystrokes": "",
    "duration": 2.0
  }
]
```
**Environment Observation:**
root@ad092d3df69c:/app# aws s3api put-bucket-acl --bucket sample-bucket --acl public-read
root@ad092d3df69c:/app#

### Turn 7
**Action:**
```json
[
  {
    "keystrokes": "aws s3api get-bucket-acl --bucket sample-bucket\n",
    "duration": 2.0
  }
]
```
**Environment Observation:**
root@ad092d3df69c:/app# aws s3api get-bucket-acl --bucket sample-bucket

### Turn 8
**Action:**
```json
[
  {
    "keystrokes": "",
    "duration": 2.0
  }
]
```
**Environment Observation:**
root@ad092d3df69c:/app# aws s3api get-bucket-acl --bucket sample-bucket
{
    "Owner": {
        "DisplayName": "webfile",
        "ID": "75aa57f09aa0c8caeab4f8c24e99d10f8e7faeebf76c078efc7c6caea54ba06a"
    },
    "Grants": [
        {
            "Grantee": {
                "DisplayName": "webfile",
                "ID": "75aa57f09aa0c8caeab4f8c24e99d10f8e7faeebf76c078efc7c6caea54ba06a",
                "Type": "CanonicalUser"
            },
            "Permission": "FULL_CONTROL"
        },
        {
            "Grantee": {
                "Type": "Group",
                "URI": "http://acs.amazonaws.com/groups/global/AllUsers"
            },
            "Permission": "READ"
        }
    ]
}
root@ad092d3df69c:/app#

]==]
