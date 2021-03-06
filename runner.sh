#!/bin/bash

set -x

# SETTINGS #############################################################

# Directory where Docker secrets are stored
secrets_dir="/var/run/secrets"

# Other vars
# You shouldn't change these unless you know what you're doing
pid=0
token=""

# ENVIRONMENT CHECK ####################################################

if ! [[ ${GITLAB_SERVER} =~ ^https?:// ]]; then
    server="http://${GITLAB_SERVER}"
else
    server="${GITLAB_SERVER}"
fi

# Set default environment vars/runner options

if [[ -z ${DOCKER_IMAGE} ]]; then
    export DOCKER_IMAGE="docker:latest"
fi

if [[ -z ${DOCKER_VOLUMES} ]]; then
    export DOCKER_VOLUMES="/var/run/docker.sock:/var/run/docker.sock"
fi

if [[ -z ${RUNNER_EXECUTOR} ]]; then
    export RUNNER_EXECUTOR="docker"
fi

########################################################################
#                                                                      #
#                              FUNCTIONS                               #
#                                                                      #
########################################################################

# SIGTERM-handler
# Unregisters Gitlab on process SIGTERM
function term_handler() {
    if [[ $pid -ne 0 ]]; then
        kill -SIGTERM "$pid"
        wait "$pid"
    fi

    gitlab-runner unregister -u "${server}" -t "${token}"

    exit 143; # 128 + 15 -- SIGTERM
}

########################################################################
#                                                                      #
#                             SCRIPT START                             #
#                                                                      #
########################################################################

# Docker secrets
if [[ -r "${secrets_dir}/gitlab_registration_token" ]]; then
    REGISTRATION_TOKEN=$(<"${secrets_dir}/gitlab_registration_token")

    export REGISTRATION_TOKEN
fi

if [[ -r "${secrets_dir}/s3_access_key" ]]; then
    CACHE_S3_ACCESS_KEY=$(<"${secrets_dir}/s3_access_key")

    export CACHE_S3_ACCESS_KEY
fi

if [[ -r "${secrets_dir}/s3_secret_key" ]]; then
    CACHE_S3_SECRET_KEY=$(<"${secrets_dir}/s3_secret_key")

    export CACHE_S3_SECRET_KEY
fi

# Register runner in non-interactive mode
# All options are set via environment variables
gitlab-runner register -n -u "${server}"

# Note: /etc/gitlab-runner/config.toml is dynamically generated from the arguments specified during runner registration

# Set runner token in $token
token=$(grep token "/etc/gitlab-runner/config.toml" | awk '{print $3}' | tr -d '"')

# setup handlers
# on callback, kill the last background process, which is `tail -f /dev/null` and execute the specified handler
trap 'kill ${!}; term_handler' SIGTERM

# run multi-runner
gitlab-ci-multi-runner run --user=gitlab-runner --working-directory=/home/gitlab-runner & pid="$!"

# Wait forever
# When this process ends, send SIGTERM to stop the runner
while true; do
    tail -f /dev/null & wait ${!}
done
