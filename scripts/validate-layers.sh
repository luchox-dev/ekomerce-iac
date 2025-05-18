#!/bin/bash
# Validate all Terraform layers with detailed logging

set -e

# Colors for logging
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Log file setup
LOG_DIR="$(cd "$(dirname "$0")" && pwd)/../logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/validation_${TIMESTAMP}.log"

# Store the script's directory path
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Create log header
echo -e "${BOLD}Terraform Layer Validation Log - $(date)${NC}" | tee -a "$LOG_FILE"
echo -e "==============================================" | tee -a "$LOG_FILE"
echo -e "Working directory: $(pwd)" | tee -a "$LOG_FILE"
echo -e "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo -e "==============================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Layers to validate in order
LAYERS=(
  "01-core"
  "02-compute"
  "03-database" 
  "04-application"
  "05-environment"
)

# Summary tracking
TOTAL_LAYERS=${#LAYERS[@]}
SUCCESSFUL_LAYERS=0
LAYERS_WITH_WARNINGS=0

# Validate each layer
for layer in "${LAYERS[@]}"; do
  echo -e "${BOLD}${BLUE}==========================================${NC}" | tee -a "$LOG_FILE"
  echo -e "${BOLD}${BLUE}Validating layer: $layer${NC}" | tee -a "$LOG_FILE"
  echo -e "${BOLD}${BLUE}==========================================${NC}" | tee -a "$LOG_FILE"
  
  # Change to the layer directory
  cd "$ROOT_DIR/layers/$layer"
  
  # Log files in the layer
  echo -e "${BLUE}Files in $layer:${NC}" | tee -a "$LOG_FILE"
  ls -la | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"
  
  echo -e "${BLUE}Resources defined in $layer:${NC}" | tee -a "$LOG_FILE"
  grep -rn "resource\s\+" --include="*.tf" . | tee -a "$LOG_FILE"
  echo "" | tee -a "$LOG_FILE"
  
  # Validate Terraform configuration and capture output
  echo -e "${BLUE}Running validation for $layer...${NC}" | tee -a "$LOG_FILE"
  if VALIDATION_OUTPUT=$(terraform validate 2>&1); then
    if [[ $VALIDATION_OUTPUT == *"Warning"* ]]; then
      echo -e "${YELLOW}$VALIDATION_OUTPUT${NC}" | tee -a "$LOG_FILE"
      echo -e "${YELLOW}⚠️ Layer $layer validated successfully but with warnings.${NC}" | tee -a "$LOG_FILE"
      ((LAYERS_WITH_WARNINGS++))
    else
      echo -e "${GREEN}$VALIDATION_OUTPUT${NC}" | tee -a "$LOG_FILE"
      echo -e "${GREEN}✅ Layer $layer validated successfully.${NC}" | tee -a "$LOG_FILE"
    fi
    ((SUCCESSFUL_LAYERS++))
  else
    echo -e "${RED}$VALIDATION_OUTPUT${NC}" | tee -a "$LOG_FILE"
    echo -e "${RED}❌ Layer $layer validation failed.${NC}" | tee -a "$LOG_FILE"
    echo -e "${RED}See $LOG_FILE for details.${NC}"
    exit 1
  fi
  
  echo "" | tee -a "$LOG_FILE"
done

# Print summary
echo -e "${BOLD}${BLUE}==========================================${NC}" | tee -a "$LOG_FILE"
echo -e "${BOLD}${BLUE}Validation Summary${NC}" | tee -a "$LOG_FILE"
echo -e "${BOLD}${BLUE}==========================================${NC}" | tee -a "$LOG_FILE"
echo -e "Total layers: $TOTAL_LAYERS" | tee -a "$LOG_FILE"
echo -e "${GREEN}Successfully validated: $SUCCESSFUL_LAYERS${NC}" | tee -a "$LOG_FILE"
if [[ $LAYERS_WITH_WARNINGS -gt 0 ]]; then
  echo -e "${YELLOW}Layers with warnings: $LAYERS_WITH_WARNINGS${NC}" | tee -a "$LOG_FILE"
fi

if [[ $SUCCESSFUL_LAYERS -eq $TOTAL_LAYERS ]]; then
  echo -e "${GREEN}${BOLD}All layers validated successfully!${NC}" | tee -a "$LOG_FILE"
  echo -e "Detailed logs available at: $LOG_FILE" | tee -a "$LOG_FILE"
else
  echo -e "${RED}${BOLD}Some layers failed validation.${NC}" | tee -a "$LOG_FILE"
  exit 1
fi