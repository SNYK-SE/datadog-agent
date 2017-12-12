#!/bin/bash -l
# http://redsymbol.net/articles/unofficial-bash-strict-mode/
IFS=$'\n\t'
set -euxo pipefail

# These should not be printed out
set +x
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
if [ -z ${CI_PIPELINE_ID+x} ]; then
  export CI_PIPELINE_ID='none'
fi

az login --service-principal -u $AZURE_CLIENT_ID -p $AZURE_CLIENT_SECRET --tenant $AZURE_TENANT_ID > /dev/null
set -x

groups=$(az group list -o tsv --query "[?starts_with(name, 'kitchen')]|[?ends_with(name, 'pl$CI_PIPELINE_ID')].[name]")

for group in $groups; do
  echo "az group delete -n $group -y"
  ( az group delete -n $group -y || true ) &
  printf "\n\n"
done

vms=$(az vm list --query "[?starts_with(name, 'dd-agent-testing')]|[?tags.pipeline_id=='$CI_PIPELINE_ID']|[*].[id]" -o tsv)

if [ -n $vms ]; then
  echo $vms
  echo "az vm delete --ids $vms -y"
  (az vm delete --ids $vms -y || true) &
fi
