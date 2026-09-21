#!/bin/bash

# <xbar.title>AWS Cost</xbar.title>
# <xbar.version>v1.3.0</xbar.version>
# <xbar.author>Sean Luce</xbar.author>
# <xbar.desc>Show the current months AWS costs.</xbar.desc>

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin${PATH:+:$PATH}"
export AWS_PROFILE="${AWS_PROFILE:-developer}"
AWS_BIN="${AWS_BIN:-aws}"
JQ_BIN="${JQ_BIN:-jq}"

resolve_command() {
    local name=$1
    if [[ "$name" == */* ]]; then
        [[ -x "$name" ]] || return 1
        printf '%s\n' "$name"
    else
        command -v "$name"
    fi
}

if ! AWS_BIN=$(resolve_command "$AWS_BIN"); then
    echo "AWS: !"
    echo "---"
    echo "⚠️ AWS CLI not found | color=red"
    echo "Install: brew install awscli | color=gray size=11"
    exit 0
fi
if ! JQ_BIN=$(resolve_command "$JQ_BIN"); then
    echo "AWS: !"
    echo "---"
    echo "⚠️ jq not found | color=red"
    echo "Install: brew install jq | color=gray size=11"
    exit 0
fi

# Calculate month boundaries with error handling
if ! start=$(date -v1d +%Y-%m-%d 2>/dev/null); then
    echo "AWS: ?"
    echo "---"
    echo "⚠️ Date calculation error | color=red"
    exit 0
fi

if ! end=$(date -v+1m -v1d -v-1d +%Y-%m-%d 2>/dev/null); then
    echo "AWS: ?"
    echo "---"
    echo "⚠️ Date calculation error | color=red"
    exit 0
fi

# Credentials and profile configuration are read by AWS CLI at runtime from the
# user's environment and home directory; they are never embedded in this file.
result=$("$AWS_BIN" ce get-cost-and-usage --output json --time-period Start="$start",End="$end" --granularity MONTHLY --metrics BlendedCost 2>&1)
exit_code=$?

# Check for permission errors
if echo "$result" | grep -q "AccessDeniedException"; then
    echo "AWS: --"
    echo "---"
    echo "⚠️ No billing permission | color=red"
    echo "Add ce:GetCostAndUsage to IAM user | color=gray size=11"
    exit 0
fi

# Check for credential errors
if echo "$result" | grep -q "Unable to locate credentials\|UnrecognizedClientException\|InvalidAccessKeyId"; then
    echo "AWS: ⚠️"
    echo "---"
    echo "⚠️ Invalid AWS credentials | color=red"
    echo "Run: aws configure | color=gray size=11"
    exit 0
fi

# Check for other AWS errors
if echo "$result" | grep -q "An error occurred"; then
    echo "AWS: ?"
    echo "---"
    echo "⚠️ AWS API error | color=red"
    echo "Check AWS CLI configuration | color=gray size=11"
    exit 0
fi

# Check for command failure
if [ $exit_code -ne 0 ]; then
    echo "AWS: ?"
    echo "---"
    echo "⚠️ AWS CLI command failed | color=red"
    echo "Check AWS configuration | color=gray size=11"
    exit 0
fi

# Parse cost and currency from JSON.
prefix=$(printf '%s' "$result" | "$JQ_BIN" -r '.ResultsByTime[0].Total.BlendedCost.Unit // empty' 2>/dev/null)
cost_raw=$(printf '%s' "$result" | "$JQ_BIN" -r '.ResultsByTime[0].Total.BlendedCost.Amount // empty' 2>/dev/null)

# Validate and format cost
if [ -n "$cost_raw" ] && [[ "$cost_raw" =~ ^[0-9]+\.?[0-9]*$ ]]; then
    cost=$(printf "%.2f" "$cost_raw" 2>/dev/null)
else
    cost=""
fi

# Set default currency if missing
if [ -z "$prefix" ]; then
    prefix="USD"
fi

# Display result
if [ -z "$cost" ]; then
    echo "AWS: ?"
    echo "---"
    echo "⚠️ Unable to parse cost data | color=red"
    echo "Check AWS Cost Explorer access | color=gray size=11"
else
    # Display as "AWS $cost" format
    printf "\$%.0f" "$cost_raw"
fi
