terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "ecommerce-transactions"
}

# ─── DynamoDB Table ───

resource "aws_dynamodb_table" "transactions" {
  name         = "${var.project_name}-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "transactionId"

  attribute {
    name = "transactionId"
    type = "S"
  }

  tags = {
    Project = var.project_name
  }
}

# ─── IAM Role for Lambda ───

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_dynamodb" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Scan",
      "dynamodb:Query"
    ]
    resources = [aws_dynamodb_table.transactions.arn]
  }
}

resource "aws_iam_policy" "lambda_dynamodb" {
  name   = "${var.project_name}-lambda-dynamodb"
  policy = data.aws_iam_policy_document.lambda_dynamodb.json
}

resource "aws_iam_role_policy_attachment" "lambda_dynamodb" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_dynamodb.arn
}

# ─── Lambda Functions ───

data "archive_file" "get_transaction" {
  type        = "zip"
  source_file = "${path.module}/lambda/get_transaction.py"
  output_path = "${path.module}/lambda/get_transaction.zip"
}

data "archive_file" "get_total_transactions" {
  type        = "zip"
  source_file = "${path.module}/lambda/get_total_transactions.py"
  output_path = "${path.module}/lambda/get_total_transactions.zip"
}

data "archive_file" "create_transaction" {
  type        = "zip"
  source_file = "${path.module}/lambda/create_transaction.py"
  output_path = "${path.module}/lambda/create_transaction.zip"
}

resource "aws_lambda_function" "get_transaction" {
  function_name    = "${var.project_name}-get-transaction"
  role             = aws_iam_role.lambda.arn
  handler          = "get_transaction.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.get_transaction.output_path
  source_code_hash = data.archive_file.get_transaction.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.transactions.name
    }
  }

  tags = { Project = var.project_name }
}

resource "aws_lambda_function" "get_total_transactions" {
  function_name    = "${var.project_name}-get-total-transactions"
  role             = aws_iam_role.lambda.arn
  handler          = "get_total_transactions.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.get_total_transactions.output_path
  source_code_hash = data.archive_file.get_total_transactions.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.transactions.name
    }
  }

  tags = { Project = var.project_name }
}

resource "aws_lambda_function" "create_transaction" {
  function_name    = "${var.project_name}-create-transaction"
  role             = aws_iam_role.lambda.arn
  handler          = "create_transaction.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.create_transaction.output_path
  source_code_hash = data.archive_file.create_transaction.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.transactions.name
    }
  }

  tags = { Project = var.project_name }
}

# ─── API Gateway REST API (OpenAPI) ───

resource "aws_api_gateway_rest_api" "api" {
  name = "${var.project_name}-api"

  body = templatefile("${path.module}/openapi.yaml", {
    GetTransactionFunctionArn       = aws_lambda_function.get_transaction.arn
    GetTotalTransactionsFunctionArn = aws_lambda_function.get_total_transactions.arn
    CreateTransactionFunctionArn    = aws_lambda_function.create_transaction.arn
    AwsRegion                       = var.aws_region
  })

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Project = var.project_name
  }
}

# ─── Lambda Permissions for API Gateway ───

resource "aws_lambda_permission" "get_transaction" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_transaction.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "get_total_transactions" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_total_transactions.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "create_transaction" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.create_transaction.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# ─── API Gateway Deployment & Stage ───

resource "aws_api_gateway_deployment" "api" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.api.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"

  tags = {
    Project = var.project_name
  }
}

# ─── Seed Data ───

resource "aws_dynamodb_table_item" "seed" {
  for_each   = local.seed_transactions
  table_name = aws_dynamodb_table.transactions.name
  hash_key   = aws_dynamodb_table.transactions.hash_key

  item = each.value
}

locals {
  seed_transactions = {
    txn1 = jsonencode({
      transactionId = { S = "TXN-00001" }
      amount        = { N = "49.99" }
      currency      = { S = "USD" }
      status        = { S = "completed" }
      date          = { S = "2026-03-01" }
      itemName      = { S = "Wireless Mouse" }
    })
    txn2 = jsonencode({
      transactionId = { S = "TXN-00002" }
      amount        = { N = "129.50" }
      currency      = { S = "USD" }
      status        = { S = "completed" }
      date          = { S = "2026-03-05" }
      itemName      = { S = "Mechanical Keyboard" }
    })
    txn3 = jsonencode({
      transactionId = { S = "TXN-00003" }
      amount        = { N = "89.99" }
      currency      = { S = "USD" }
      status        = { S = "pending" }
      date          = { S = "2026-03-10" }
      itemName      = { S = "USB-C Hub" }
    })
    txn4 = jsonencode({
      transactionId = { S = "TXN-00004" }
      amount        = { N = "299.00" }
      currency      = { S = "USD" }
      status        = { S = "completed" }
      date          = { S = "2026-03-12" }
      itemName      = { S = "27-inch Monitor" }
    })
    txn5 = jsonencode({
      transactionId = { S = "TXN-00005" }
      amount        = { N = "15.99" }
      currency      = { S = "USD" }
      status        = { S = "refunded" }
      date          = { S = "2026-03-15" }
      itemName      = { S = "Phone Case" }
    })
    txn6 = jsonencode({
      transactionId = { S = "TXN-00006" }
      amount        = { N = "74.50" }
      currency      = { S = "USD" }
      status        = { S = "completed" }
      date          = { S = "2026-03-16" }
      itemName      = { S = "Webcam HD 1080p" }
    })
    txn7 = jsonencode({
      transactionId = { S = "TXN-00007" }
      amount        = { N = "199.99" }
      currency      = { S = "USD" }
      status        = { S = "completed" }
      date          = { S = "2026-03-17" }
      itemName      = { S = "Noise-Cancelling Headphones" }
    })
    txn8 = jsonencode({
      transactionId = { S = "TXN-00008" }
      amount        = { N = "34.99" }
      currency      = { S = "USD" }
      status        = { S = "pending" }
      date          = { S = "2026-03-18" }
      itemName      = { S = "Mouse Pad XL" }
    })
    txn9 = jsonencode({
      transactionId = { S = "TXN-00009" }
      amount        = { N = "549.00" }
      currency      = { S = "USD" }
      status        = { S = "completed" }
      date          = { S = "2026-03-19" }
      itemName      = { S = "Graphics Card RTX 4060" }
    })
    txn10 = jsonencode({
      transactionId = { S = "TXN-00010" }
      amount        = { N = "22.49" }
      currency      = { S = "USD" }
      status        = { S = "refunded" }
      date          = { S = "2026-03-20" }
      itemName      = { S = "HDMI Cable 6ft" }
    })
    txn11 = jsonencode({
      transactionId = { S = "TXN-00011" }
      amount        = { N = "159.99" }
      currency      = { S = "USD" }
      status        = { S = "completed" }
      date          = { S = "2026-03-21" }
      itemName      = { S = "Ergonomic Chair Cushion" }
    })
    txn12 = jsonencode({
      transactionId = { S = "TXN-00012" }
      amount        = { N = "89.00" }
      currency      = { S = "USD" }
      status        = { S = "completed" }
      date          = { S = "2026-03-22" }
      itemName      = { S = "Portable SSD 500GB" }
    })
    txn13 = jsonencode({
      transactionId = { S = "TXN-00013" }
      amount        = { N = "42.75" }
      currency      = { S = "USD" }
      status        = { S = "pending" }
      date          = { S = "2026-03-23" }
      itemName      = { S = "Laptop Stand Adjustable" }
    })
    txn14 = jsonencode({
      transactionId = { S = "TXN-00014" }
      amount        = { N = "349.99" }
      currency      = { S = "USD" }
      status        = { S = "completed" }
      date          = { S = "2026-03-24" }
      itemName      = { S = "Mechanical Keyboard Premium" }
    })
    txn15 = jsonencode({
      transactionId = { S = "TXN-00015" }
      amount        = { N = "18.99" }
      currency      = { S = "USD" }
      status        = { S = "refunded" }
      date          = { S = "2026-03-25" }
      itemName      = { S = "USB-A to USB-C Adapter" }
    })
    txn16 = jsonencode({
      transactionId = { S = "TXN-00016" }
      amount        = { N = "124.99" }
      currency      = { S = "USD" }
      status        = { S = "completed" }
      date          = { S = "2026-03-26" }
      itemName      = { S = "Wireless Charging Pad" }
    })
    txn17 = jsonencode({
      transactionId = { S = "TXN-00017" }
      amount        = { N = "67.50" }
      currency      = { S = "USD" }
      status        = { S = "completed" }
      date          = { S = "2026-03-27" }
      itemName      = { S = "Bluetooth Speaker" }
    })
    txn18 = jsonencode({
      transactionId = { S = "TXN-00018" }
      amount        = { N = "449.00" }
      currency      = { S = "USD" }
      status        = { S = "pending" }
      date          = { S = "2026-03-28" }
      itemName      = { S = "Tablet 10-inch" }
    })
    txn19 = jsonencode({
      transactionId = { S = "TXN-00019" }
      amount        = { N = "29.99" }
      currency      = { S = "USD" }
      status        = { S = "completed" }
      date          = { S = "2026-03-29" }
      itemName      = { S = "Screen Cleaning Kit" }
    })
    txn20 = jsonencode({
      transactionId = { S = "TXN-00020" }
      amount        = { N = "799.99" }
      currency      = { S = "USD" }
      status        = { S = "completed" }
      date          = { S = "2026-03-30" }
      itemName      = { S = "Curved Gaming Monitor 32-inch" }
    })
  }
}

# ─── Outputs ───

output "api_url" {
  description = "Base URL of the deployed API"
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "api_id" {
  description = "REST API ID"
  value       = aws_api_gateway_rest_api.api.id
}

output "stage_name" {
  description = "API Gateway stage name"
  value       = aws_api_gateway_stage.prod.stage_name
}

output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = aws_dynamodb_table.transactions.name
}
