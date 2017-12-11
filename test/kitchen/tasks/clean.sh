#!/usr/bin/env bash -l

if [ -z ${AZURE_CLIENT_ID+x} ]; then
  export AZURE_CLIENT_ID=$(aws ssm get-parameter --region us-east-1 --name ci.dd-agent-testing.azure_client_id --with-decryption --query "Parameter.Value" --out text)
fi
if [ -z ${AZURE_CLIENT_SECRET+x} ]; then
  export AZURE_CLIENT_SECRET=$(aws ssm get-parameter --region us-east-1 --name ci.dd-agent-testing.azure_client_secret --with-decryption --query "Parameter.Value" --out text)
fi
if [ -z ${AZURE_TENANT_ID+x} ]; then
  export AZURE_TENANT_ID=$(aws ssm get-parameter --region us-east-1 --name ci.dd-agent-testing.azure_tenant_id --with-decryption --query "Parameter.Value" --out text)
fi
if [ -z ${AZURE_SUBSCRIPTION_ID+x} ]; then
  export AZURE_SUBSCRIPTION_ID=$(aws ssm get-parameter --region us-east-1 --name ci.dd-agent-testing.azure_subscription_id --with-decryption --query "Parameter.Value" --out text)
fi

az login --service-principal -u $AZURE_CLIENT_ID -p $AZURE_CLIENT_SECRET --tenant $AZURE_TENANT_ID

groups=$(az group list -o tsv --query "[?starts_with(name, 'kitchen-dd-agent')]|[*].name")

for group in $groups; do
  echo "az group delete -n $group -y"
  ( az group delete -n $group -y || true ) &
  printf "\n\n"
done
