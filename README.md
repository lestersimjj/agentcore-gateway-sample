# Ecommerce Transactions API — Terraform Deployment

This Terraform project deploys a serverless REST API for managing ecommerce transactions using API Gateway, Lambda, and DynamoDB.

## What Gets Deployed

- **DynamoDB Table** — Stores transactions with `transactionId` as the primary key
- **3 Lambda Functions** (Python 3.12):
  - `get_transaction` — Retrieve a transaction by ID
  - `get_total_transactions` — Get total transaction count
  - `create_transaction` — Create a new transaction (requires `amount`, `itemName`, `status`)
- **API Gateway REST API** — Regional endpoint defined via OpenAPI spec
- **20 Seed Records** — Sample transaction data pre-loaded into DynamoDB

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- AWS CLI configured with valid credentials
- An AWS account with permissions for DynamoDB, Lambda, API Gateway, and IAM

## Deployment

1. Initialize Terraform:

```bash
terraform init
```

2. Preview the changes:

```bash
terraform plan
```

3. Deploy:

```bash
terraform apply
```

4. Note the outputs:

```
api_url             = "https://<api-id>.execute-api.<region>.amazonaws.com/prod"
api_id              = "<api-id>"
stage_name          = "prod"
dynamodb_table_name = "ecommerce-transactions-table"
```

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/transactions/{id}` | Get a transaction by ID (e.g., `TXN-00001`) |
| GET | `/total-transactions` | Get total number of transactions |
| POST | `/new-transaction` | Create a new transaction |

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region to deploy resources |
| `project_name` | `ecommerce-transactions` | Project name used for resource naming |

Override defaults:

```bash
terraform apply -var="aws_region=ap-southeast-1" -var="project_name=my-transactions"
```

## Cleanup

```bash
terraform destroy
```
