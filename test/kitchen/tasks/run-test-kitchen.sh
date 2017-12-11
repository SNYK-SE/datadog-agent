#!/bin/bash -l
# http://redsymbol.net/articles/unofficial-bash-strict-mode/
IFS=$'\n\t'
set -euxo pipefail

rm -rf .kitchen

if [ -f $(pwd)/ssh-key ]; then
  rm ssh-key
fi

ssh-keygen -f $(pwd)/ssh-key -P "" -t rsa -b 2048

export AZURE_SSH_KEY_PATH="$(pwd)/ssh-key"

eval "$(chef shell-init bash)"

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

if [ ! -f /root/.azure/credentials ]; then
  mkdir -p /root/.azure
  touch /root/.azure/credentials
fi

(echo "<% subscription_id=\"$AZURE_SUBSCRIPTION_ID\"; client_id=\"$AZURE_CLIENT_ID\"; client_secret=\"$AZURE_CLIENT_SECRET\"; tenant_id=\"$AZURE_TENANT_ID\"; %>" && cat azure-creds.erb) | erb > /root/.azure/credentials

echo $(pwd)/ssh-key
echo $AZURE_SSH_KEY_PATH

eval $(ssh-agent -s)

ssh-add "$AZURE_SSH_KEY_PATH"

bundle install
cp .kitchen-azure.yml .kitchen.yml
# unset DIGITALOCEAN_SSH_KEY_PATH
kitchen diagnose --no-instances --loader

# in docker we cannot interact to do this so we must disable it
mkdir -p ~/.ssh
[[ -f /.dockerenv ]] && echo -e "Host *\n\tStrictHostKeyChecking no\n\n" > ~/.ssh/config

rake dd-agent-azurerm-parallel[20]
