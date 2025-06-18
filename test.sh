#!/bin/bash

# Run the playbook in a Debian container with ansible installed on the fly
docker run --rm -v "$(pwd):/ansible" debian:bookworm-slim bash -c "
    apt-get update && \
    apt-get install -y ansible && \
    cd /ansible && \
    ansible-playbook -i localhost, \
    -e 'root_password=testroot' \
    -e 'centroid_password=testcentroid' \
    ansible-playbook.yml
"
