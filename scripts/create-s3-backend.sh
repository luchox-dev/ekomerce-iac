#!/bin/bash
# Variables - Update these as needed
REGION="us-east-1"                              # Select an AWS region that meets your requirements
BUCKET_NAME="ekomerce-terraform-state-bucket"         # Ensure this bucket name is globally unique
DYNAMODB_TABLE="ekomerce-terraform-locks"             # Name for the DynamoDB table for state locking

# Create the S3 bucket.
# For regions other than us-east-1, specify the LocationConstraint.
if [ "$REGION" == "us-east-1" ]; then
    aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION
else
    aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION \
      --create-bucket-configuration LocationConstraint=$REGION
fi

# Enable versioning on the S3 bucket.
aws s3api put-bucket-versioning --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# Enable server-side encryption (SSE-S3) on the S3 bucket.
aws s3api put-bucket-encryption --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }'

# Create a DynamoDB table for Terraform state locking.
aws dynamodb create-table \
  --table-name $DYNAMODB_TABLE \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region $REGION

echo "S3 bucket '$BUCKET_NAME' created in region '$REGION' with versioning and encryption enabled."
echo "DynamoDB table '$DYNAMODB_TABLE' created for state locking."
