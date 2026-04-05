import json
import os
import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


def handler(event, context):
    transaction_id = event["pathParameters"]["id"]

    response = table.get_item(Key={"transactionId": transaction_id})
    item = response.get("Item")

    if not item:
        return {
            "statusCode": 404,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"message": f"Transaction {transaction_id} not found"}),
        }

    # Convert Decimal types to float for JSON serialization
    if "amount" in item:
        item["amount"] = float(item["amount"])

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(item),
    }
