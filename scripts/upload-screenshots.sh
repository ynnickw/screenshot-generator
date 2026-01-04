#!/bin/bash

# Upload Screenshots to Supabase Storage
# Usage: ./upload-screenshots.sh <job_id> <bundle_id> <version> <build_number>

set -e

JOB_ID=$1
BUNDLE_ID=$2
VERSION=$3
BUILD_NUMBER=$4

if [ -z "$JOB_ID" ]; then
    echo "Error: Job ID is required"
    exit 1
fi

echo "==================================="
echo "  Uploading Screenshots to Supabase"
echo "==================================="
echo ""
echo "Job ID: $JOB_ID"
echo "Bundle ID: $BUNDLE_ID"
echo "Version: $VERSION"
echo "Build: $BUILD_NUMBER"
echo ""

# Function to upload a file and get signed URL
upload_file() {
    local file_path=$1
    local storage_path=$2
    
    # Upload file
    curl -s -X POST "$SUPABASE_URL/storage/v1/object/screenshots/$storage_path" \
        -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
        -H "Content-Type: image/png" \
        --data-binary @"$file_path"
    
    # Get signed URL (valid for 1 year)
    local signed_url=$(curl -s -X POST "$SUPABASE_URL/storage/v1/object/sign/screenshots/$storage_path" \
        -H "Authorization: Bearer $SUPABASE_SERVICE_KEY" \
        -H "Content-Type: application/json" \
        -d '{"expiresIn": 31536000}' | jq -r '.signedURL')
    
    if [ "$signed_url" != "null" ] && [ -n "$signed_url" ]; then
        echo "$SUPABASE_URL/storage/v1$signed_url"
    else
        echo ""
    fi
}

# Upload iPhone screenshots
echo "📱 Uploading iPhone screenshots..."
IPHONE_URLS="["
FIRST=true

for file in screenshots/iphone/*.png; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        storage_path="automated-screenshots/$JOB_ID/iphone/$filename"
        
        echo "  Uploading: $filename"
        url=$(upload_file "$file" "$storage_path")
        
        if [ -n "$url" ]; then
            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                IPHONE_URLS="$IPHONE_URLS,"
            fi
            IPHONE_URLS="$IPHONE_URLS\"$url\""
            echo "    ✓ Uploaded successfully"
        else
            echo "    ✗ Upload failed"
        fi
    fi
done

IPHONE_URLS="$IPHONE_URLS]"
echo "$IPHONE_URLS" > screenshots/iphone/urls.json

# Upload iPad screenshots
echo ""
echo "📱 Uploading iPad screenshots..."
IPAD_URLS="["
FIRST=true

for file in screenshots/ipad/*.png; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        storage_path="automated-screenshots/$JOB_ID/ipad/$filename"
        
        echo "  Uploading: $filename"
        url=$(upload_file "$file" "$storage_path")
        
        if [ -n "$url" ]; then
            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                IPAD_URLS="$IPAD_URLS,"
            fi
            IPAD_URLS="$IPAD_URLS\"$url\""
            echo "    ✓ Uploaded successfully"
        else
            echo "    ✗ Upload failed"
        fi
    fi
done

IPAD_URLS="$IPAD_URLS]"
echo "$IPAD_URLS" > screenshots/ipad/urls.json

echo ""
echo "==================================="
echo "  Upload Complete!"
echo "==================================="
echo ""
echo "iPhone screenshots: $(echo $IPHONE_URLS | jq length) files"
echo "iPad screenshots: $(echo $IPAD_URLS | jq length) files"

