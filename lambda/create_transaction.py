import json
import os
import uuid
from datetime import date

import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


def handler(event, context):
    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"message": "Invalid JSON in request body"}),
        }

    required_fields = ["amount", "itemName", "status"]
    missing = [f for f in required_fields if f not in body]
    if missing:
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"message": f"Missing required fields: {', '.join(missing)}"}),
        }

    from decimal import Decimal

    transaction = {
        "transactionId": f"TXN-{uuid.uuid4().hex[:5].upper()}",
        "amount": Decimal(str(body["amount"])),
        "currency": body.get("currency", "USD"),
        "status": body["status"],
        "date": date.today().isoformat(),
        "itemName": body["itemName"],
    }

    table.put_item(Item=transaction)

    # Convert Decimal for JSON response
    transaction["amount"] = float(transaction["amount"])

    return {
        "statusCode": 201,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": "Transaction created", "transaction": transaction}),
    }
