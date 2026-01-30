#!/bin/bash
# Oracle ARM A1 Flex instance creation retry script
# Will keep trying every 5 minutes until successful

export SUPPRESS_LABEL_WARNING=True

COMPARTMENT="ocid1.tenancy.oc1..aaaaaaaate22jsouuzgaw65ucwvufcj3lzjxw4ithwcz3cxw6iom6ys2ldsq"
AD="bRpM:EU-MARSEILLE-1-AD-1"
IMAGE="ocid1.image.oc1.eu-marseille-1.aaaaaaaar3pm2xlih5tqkjwr7ykfgzixjytjivkacgmqrlxi66vzlf5a2wlq"
SUBNET="ocid1.subnet.oc1.eu-marseille-1.aaaaaaaapz6g4htlyisp45zplqi47t3mms4noceyqebb5huhccrlt432ugeq"
SSH_KEY="/home/diego/.ssh/id_rsa.pub"

# Config: 4 OCPU, 24GB RAM (max free tier)
OCPUS=4
MEMORY=24

attempt=1
while true; do
  echo "$(date): Attempt $attempt - Trying to create ARM instance..."

  result=$(oci compute instance launch \
    --compartment-id "$COMPARTMENT" \
    --availability-domain "$AD" \
    --shape "VM.Standard.A1.Flex" \
    --shape-config "{\"ocpus\": $OCPUS, \"memoryInGBs\": $MEMORY}" \
    --image-id "$IMAGE" \
    --subnet-id "$SUBNET" \
    --display-name "arm-server-1" \
    --assign-public-ip true \
    --ssh-authorized-keys-file "$SSH_KEY" \
    2>&1)

  if echo "$result" | grep -q '"lifecycle-state"'; then
    echo "SUCCESS! Instance created!"
    echo "$result"
    break
  else
    echo "Failed: Out of host capacity"
    echo "Waiting 5 minutes before retry..."
    attempt=$((attempt + 1))
    sleep 300
  fi
done
