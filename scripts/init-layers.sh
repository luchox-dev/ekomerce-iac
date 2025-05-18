#!/bin/bash
# Initialize all Terraform layers with proper backends

set -e

# Store the script's directory path
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Variables
BUCKET_NAME="ekomerce-terraform-state-bucket"
REGION="us-east-1"
DYNAMO_TABLE="ekomerce-terraform-locks"

# Log file setup
LOG_DIR="$ROOT_DIR/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/initialization_${TIMESTAMP}.log"

# Create log header
echo "Terraform Layer Initialization Log - $(date)" | tee -a "$LOG_FILE"
echo "=============================================" | tee -a "$LOG_FILE"
echo "Working directory: $(pwd)" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo "=============================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Layers to initialize in order
LAYERS=(
  "01-core"
  "02-compute"
  "03-database" 
  "04-application"
  "05-environment"
)

# Check if S3 backend exists, create if not
echo "Checking if S3 backend bucket exists..." | tee -a "$LOG_FILE"
if ! aws s3api head-bucket --bucket $BUCKET_NAME 2>/dev/null; then
  echo "Creating S3 bucket for Terraform state..." | tee -a "$LOG_FILE"
  if [ "$REGION" == "us-east-1" ]; then
    aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION | tee -a "$LOG_FILE"
  else
    aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION \
      --create-bucket-configuration LocationConstraint=$REGION | tee -a "$LOG_FILE"
  fi
  
  # Enable versioning on the S3 bucket
  echo "Enabling versioning on S3 bucket..." | tee -a "$LOG_FILE"
  aws s3api put-bucket-versioning --bucket $BUCKET_NAME \
    --versioning-configuration Status=Enabled | tee -a "$LOG_FILE"
  
  # Enable server-side encryption
  echo "Enabling server-side encryption on S3 bucket..." | tee -a "$LOG_FILE"
  aws s3api put-bucket-encryption --bucket $BUCKET_NAME \
    --server-side-encryption-configuration '{
      "Rules": [
        {
          "ApplyServerSideEncryptionByDefault": {
            "SSEAlgorithm": "AES256"
          }
        }
      ]
    }' | tee -a "$LOG_FILE"
  
  echo "S3 bucket created successfully." | tee -a "$LOG_FILE"
else
  echo "S3 bucket already exists." | tee -a "$LOG_FILE"
fi

# Check if DynamoDB table exists, create if not
echo "Checking if DynamoDB table exists..." | tee -a "$LOG_FILE"
if ! aws dynamodb describe-table --table-name $DYNAMO_TABLE 2>/dev/null; then
  echo "Creating DynamoDB table for state locking..." | tee -a "$LOG_FILE"
  aws dynamodb create-table \
    --table-name $DYNAMO_TABLE \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --region $REGION | tee -a "$LOG_FILE"
  
  echo "DynamoDB table created successfully." | tee -a "$LOG_FILE"
else
  echo "DynamoDB table already exists." | tee -a "$LOG_FILE"
fi

# Summary tracking
TOTAL_LAYERS=${#LAYERS[@]}
SUCCESSFUL_LAYERS=0

# Initialize each layer
for layer in "${LAYERS[@]}"; do
  echo "=========================================" | tee -a "$LOG_FILE"
  echo "Initializing layer: $layer" | tee -a "$LOG_FILE"
  echo "=========================================" | tee -a "$LOG_FILE"
  
  # Change to the layer directory using absolute path
  LAYER_DIR="$ROOT_DIR/layers/$layer"
  
  if [ ! -d "$LAYER_DIR" ]; then
    echo "ERROR: Layer directory not found: $LAYER_DIR" | tee -a "$LOG_FILE"
    echo "Make sure the layer directory exists." | tee -a "$LOG_FILE"
    continue
  fi
  
  cd "$LAYER_DIR"
  
  echo "Working in directory: $(pwd)" | tee -a "$LOG_FILE"
  
  # Initialize Terraform with backend configuration
  if terraform init \
    -backend-config="bucket=$BUCKET_NAME" \
    -backend-config="region=$REGION" \
    -backend-config="dynamodb_table=$DYNAMO_TABLE" | tee -a "$LOG_FILE"; then
    
    echo "Layer $layer initialized successfully." | tee -a "$LOG_FILE"
    ((SUCCESSFUL_LAYERS++))
  else
    echo "ERROR: Failed to initialize layer $layer" | tee -a "$LOG_FILE"
  fi
  
  echo | tee -a "$LOG_FILE"
done

# Print summary
echo "=========================================" | tee -a "$LOG_FILE"
echo "Initialization Summary" | tee -a "$LOG_FILE"
echo "=========================================" | tee -a "$LOG_FILE"
echo "Total layers: $TOTAL_LAYERS" | tee -a "$LOG_FILE"
echo "Successfully initialized: $SUCCESSFUL_LAYERS" | tee -a "$LOG_FILE"

if [ $SUCCESSFUL_LAYERS -eq $TOTAL_LAYERS ]; then
  echo "All layers initialized successfully!" | tee -a "$LOG_FILE"
  echo "Detailed logs available at: $LOG_FILE" | tee -a "$LOG_FILE"
else
  echo "WARNING: Some layers failed initialization." | tee -a "$LOG_FILE"
  echo "Check the log for details: $LOG_FILE" | tee -a "$LOG_FILE"
  exit 1
fi