#!/bin/bash
#
# test_apns_push.sh — Send a test VoIP push directly to APNs
#
# This bypasses Vonage entirely and tests whether:
#   1. Your VoIP certificate is valid
#   2. Your device token is correct
#   3. APNs can deliver to your device
#
# If this push arrives (you see "[VonageVoice-Push] *** didReceiveIncomingPush ***"
# in Xcode console), then your cert + token + device are fine and the problem
# is on Vonage's side.
#
# If this push FAILS, the problem is your APNs configuration (cert or token).
#
# USAGE:
#   1. Export your VoIP .p12 cert+key to PEM files (instructions below)
#   2. Fill in DEVICE_TOKEN_HEX from Xcode log: "VoIP token ... hex=<THIS>"
#   3. Run: bash test_apns_push.sh
#
# PREPARATION — Convert .p12 to PEM (run once):
#   # If your .p12 has NO password, just press Enter when prompted:
#   /usr/bin/openssl pkcs12 -legacy -in VoipCert.p12 -out voip_combined.pem -nodes
#
#   # Or split into cert + key:
#   /usr/bin/openssl pkcs12 -legacy -in VoipCert.p12 -out voip_cert.pem -clcerts -nokeys
#   /usr/bin/openssl pkcs12 -legacy -in VoipCert.p12 -out voip_key.pem -nocerts -nodes

set -e

# ─── CONFIGURE THESE ───────────────────────────────────────────────────
DEVICE_TOKEN_HEX="30cb555fcc98c8a27d3f86939224f3aa94d2948f5b34203c8ea64728769faa1e"
BUNDLE_ID="com.iocod.vonage.vonageVoiceExampl"
PEM_FILE="voip_combined.pem"          # Combined cert+key PEM file
# Or use separate cert/key:
# CERT_FILE="voip_cert.pem"
# KEY_FILE="voip_key.pem"

# Use sandbox for development builds (installed via Xcode)
# Use production for TestFlight/App Store builds
APNS_HOST="api.sandbox.push.apple.com"
# APNS_HOST="api.push.apple.com"       # Uncomment for production
# ───────────────────────────────────────────────────────────────────────

echo "=== APNs VoIP Push Test ==="
echo "Target: ${APNS_HOST}"
echo "Bundle: ${BUNDLE_ID}.voip"
echo "Token:  ${DEVICE_TOKEN_HEX:0:20}..."
echo ""

# The VoIP push topic MUST be bundleId + ".voip"
APNS_TOPIC="${BUNDLE_ID}.voip"

if [[ -n "${CERT_FILE:-}" && -n "${KEY_FILE:-}" ]]; then
    CERT_ARGS="--cert ${CERT_FILE} --key ${KEY_FILE}"
else
    CERT_ARGS="--cert ${PEM_FILE}"
fi

# Send a minimal VoIP push
# The payload doesn't matter for testing — PushKit will deliver any valid VoIP push
HTTP_RESPONSE=$(curl -v \
    ${CERT_ARGS} \
    -H "apns-topic: ${APNS_TOPIC}" \
    -H "apns-push-type: voip" \
    -H "apns-priority: 10" \
    -H "apns-expiration: 0" \
    -d '{"aps":{},"test":"apns-diagnostic-ping"}' \
    --http2 \
    "https://${APNS_HOST}/3/device/${DEVICE_TOKEN_HEX}" \
    2>&1)

echo ""
echo "=== Response ==="
echo "${HTTP_RESPONSE}" | grep -E "< HTTP|< apns-id|{" || echo "(no JSON body — likely success)"
echo ""

# Parse result
if echo "${HTTP_RESPONSE}" | grep -q "< HTTP/2 200"; then
    echo "✅ SUCCESS — Push accepted by APNs!"
    echo ""
    echo "If you see '[VonageVoice-Push] *** didReceiveIncomingPush ***' in Xcode,"
    echo "your cert + token are CORRECT. The problem is Vonage's push delivery."
    echo ""
    echo "Check: Vonage Dashboard → Your App → Capabilities → Voice → Push Certificates"
    echo "Make sure the .p12 is uploaded and the sandbox/production setting matches."
elif echo "${HTTP_RESPONSE}" | grep -q "BadDeviceToken"; then
    echo "❌ FAILED — BadDeviceToken"
    echo ""
    echo "The device token is invalid for this APNs environment."
    echo "Possible causes:"
    echo "  1. Token is from a different APNs environment (sandbox vs production)"
    echo "  2. App was reinstalled — token changed but old one was used"
    echo "  3. Token hex was copied incorrectly"
elif echo "${HTTP_RESPONSE}" | grep -q "TopicDisallowed"; then
    echo "❌ FAILED — TopicDisallowed"
    echo ""
    echo "Your certificate does not cover this bundle ID."
    echo "Expected topic: ${APNS_TOPIC}"
    echo "Check: Your VoIP cert must be for bundle ID '${BUNDLE_ID}'"
elif echo "${HTTP_RESPONSE}" | grep -q "Unregistered"; then
    echo "❌ FAILED — Unregistered"
    echo ""
    echo "This token is no longer valid (app was uninstalled or token expired)."
    echo "Reinstall the app and use the NEW hex token from Xcode logs."
elif echo "${HTTP_RESPONSE}" | grep -q "InvalidProviderToken\|Forbidden"; then
    echo "❌ FAILED — Certificate rejected"
    echo ""
    echo "APNs rejected your certificate. Check:"
    echo "  1. .p12 includes the private key"
    echo "  2. Certificate is VoIP Services type (not regular APNs)"
    echo "  3. Certificate is not expired"
else
    echo "⚠️  Unexpected response — check the full output above"
fi
