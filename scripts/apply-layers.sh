#!/bin/bash
# Apply all Terraform layers in sequence

set -e

# Store the script's directory path
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Default environment is dev
ENVIRONMENT=${1:-dev}

# Add options for auto-approve and plan-only
AUTO_APPROVE=0
PLAN_ONLY=0

# Parse command-line options
DESTROY=0
while [[ $# -gt 0 ]]; do
  case $1 in
    -a|--auto-approve)
      AUTO_APPROVE=1
      shift
      ;;
    -p|--plan-only)
      PLAN_ONLY=1
      shift
      ;;
    -e|--environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    -d|--destroy)
      DESTROY=1
      shift
      ;;
    *)
      # Skip unknown option
      shift
      ;;
  esac
done

# Log file setup
LOG_DIR="$ROOT_DIR/logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/apply_${ENVIRONMENT}_${TIMESTAMP}.log"

# Layers to apply in order
LAYERS=(
  "01-core"
  "02-compute"
  "03-database" 
  "04-application"
  "05-environment"
)

# Create log header
echo "Terraform Layer Apply Log - $(date)" | tee -a "$LOG_FILE"
echo "Environment: $ENVIRONMENT" | tee -a "$LOG_FILE"
echo "=============================================" | tee -a "$LOG_FILE"
echo "Working directory: $(pwd)" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
if [ $PLAN_ONLY -eq 1 ]; then
  echo "Mode: Plan only (no apply)" | tee -a "$LOG_FILE"
elif [ $AUTO_APPROVE -eq 1 ]; then
  echo "Mode: Auto-approve (no confirmation)" | tee -a "$LOG_FILE"
else
  echo "Mode: Interactive (requires confirmation)" | tee -a "$LOG_FILE"
fi
echo "=============================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "Applying layers for environment: $ENVIRONMENT" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Summary tracking
TOTAL_LAYERS=${#LAYERS[@]}
SUCCESSFUL_LAYERS=0

# Get layers in correct order (reverse order for destroy)
if [ $DESTROY -eq 1 ]; then
  # Reverse the order of layers for destroy
  REVERSED_LAYERS=()
  for (( i=${#LAYERS[@]}-1; i>=0; i-- )); do
    REVERSED_LAYERS+=("${LAYERS[$i]}")
  done
  LAYERS=("${REVERSED_LAYERS[@]}")
  echo "Destroy mode: Layers will be processed in reverse order" | tee -a "$LOG_FILE"
fi

# Apply or destroy each layer
for layer in "${LAYERS[@]}"; do
  if [ $DESTROY -eq 1 ]; then
    echo "=========================================" | tee -a "$LOG_FILE"
    echo "Destroying layer: $layer for environment $ENVIRONMENT" | tee -a "$LOG_FILE"
    echo "=========================================" | tee -a "$LOG_FILE"
  else
    echo "=========================================" | tee -a "$LOG_FILE"
    echo "Applying layer: $layer for environment $ENVIRONMENT" | tee -a "$LOG_FILE"
    echo "=========================================" | tee -a "$LOG_FILE"
  fi
  
  # Change to the layer directory using absolute path
  LAYER_DIR="$ROOT_DIR/layers/$layer"
  
  if [ ! -d "$LAYER_DIR" ]; then
    echo "ERROR: Layer directory not found: $LAYER_DIR" | tee -a "$LOG_FILE"
    echo "Make sure the layer directory exists." | tee -a "$LOG_FILE"
    continue
  fi
  
  cd "$LAYER_DIR"
  
  echo "Working in directory: $(pwd)" | tee -a "$LOG_FILE"
  
  # Select workspace for environment
  if terraform workspace select $ENVIRONMENT 2>/dev/null || terraform workspace new $ENVIRONMENT; then
    echo "Using workspace: $ENVIRONMENT" | tee -a "$LOG_FILE"
  else
    echo "ERROR: Failed to select or create workspace $ENVIRONMENT" | tee -a "$LOG_FILE"
    continue
  fi
  
  # Use environment-specific tfvars file if available
  TFVARS_FILE="terraform.tfvars"
  if [ -f "terraform.tfvars.${ENVIRONMENT}" ]; then
    TFVARS_FILE="terraform.tfvars.${ENVIRONMENT}"
    echo "Using environment-specific variables file: $TFVARS_FILE" | tee -a "$LOG_FILE"
  fi

  if [ $DESTROY -eq 1 ]; then
    # Destroy infrastructure
    echo "Planning destruction for layer $layer..." | tee -a "$LOG_FILE"
    
    if [ $AUTO_APPROVE -eq 1 ]; then
      # Auto-approve mode
      if terraform destroy -auto-approve -var="environment=$ENVIRONMENT" -var-file="$TFVARS_FILE" | tee -a "$LOG_FILE"; then
        echo "Layer $layer destroyed successfully." | tee -a "$LOG_FILE"
        ((SUCCESSFUL_LAYERS++))
      else
        echo "ERROR: Failed to destroy layer $layer" | tee -a "$LOG_FILE"
      fi
    else
      # Interactive mode
      if terraform destroy -var="environment=$ENVIRONMENT" -var-file="$TFVARS_FILE" | tee -a "$LOG_FILE"; then
        echo "Layer $layer destroyed successfully." | tee -a "$LOG_FILE"
        ((SUCCESSFUL_LAYERS++))
      else
        echo "ERROR: Failed to destroy layer $layer" | tee -a "$LOG_FILE"
      fi
    fi
  else
    # First run a plan
    echo "Planning changes for layer $layer..." | tee -a "$LOG_FILE"
    if terraform plan -var="environment=$ENVIRONMENT" -var-file="$TFVARS_FILE" -out=tfplan | tee -a "$LOG_FILE"; then
      echo "Planning completed successfully for layer $layer." | tee -a "$LOG_FILE"
      
      # If plan-only mode, skip apply
      if [ $PLAN_ONLY -eq 1 ]; then
        echo "Plan-only mode, skipping apply for layer $layer" | tee -a "$LOG_FILE"
        ((SUCCESSFUL_LAYERS++))
        continue
      fi
      
      # Apply Terraform configuration using the tfplan file
      echo "Applying changes for layer $layer..." | tee -a "$LOG_FILE"
      
      if terraform apply tfplan | tee -a "$LOG_FILE"; then
        echo "Layer $layer applied successfully." | tee -a "$LOG_FILE"
        ((SUCCESSFUL_LAYERS++))
      else
        echo "ERROR: Failed to apply layer $layer" | tee -a "$LOG_FILE"
      fi
    else
      echo "ERROR: Planning failed for layer $layer" | tee -a "$LOG_FILE"
    fi
  fi
  
  echo "" | tee -a "$LOG_FILE"
done

# Print summary
echo "=========================================" | tee -a "$LOG_FILE"
if [ $DESTROY -eq 1 ]; then
  echo "Destroy Summary" | tee -a "$LOG_FILE"
else
  echo "Apply Summary" | tee -a "$LOG_FILE"
fi
echo "=========================================" | tee -a "$LOG_FILE"
echo "Environment: $ENVIRONMENT" | tee -a "$LOG_FILE"
echo "Total layers: $TOTAL_LAYERS" | tee -a "$LOG_FILE"
echo "Successfully processed: $SUCCESSFUL_LAYERS" | tee -a "$LOG_FILE"

if [ $SUCCESSFUL_LAYERS -eq $TOTAL_LAYERS ]; then
  if [ $DESTROY -eq 1 ]; then
    echo "All layers destroyed successfully for environment: $ENVIRONMENT!" | tee -a "$LOG_FILE"
  else
    echo "All layers processed successfully for environment: $ENVIRONMENT!" | tee -a "$LOG_FILE"
  fi
  echo "Detailed logs available at: $LOG_FILE" | tee -a "$LOG_FILE"
else
  echo "WARNING: Some layers failed processing." | tee -a "$LOG_FILE"
  echo "Check the log for details: $LOG_FILE" | tee -a "$LOG_FILE"
  exit 1
fi