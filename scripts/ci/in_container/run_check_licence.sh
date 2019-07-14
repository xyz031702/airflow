#!/usr/bin/env bash

#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Script to run Pylint on all code. Can be started from any working directory
# ./scripts/ci/run_pylint.sh

set -uo pipefail

MY_DIR=$(cd "$(dirname "$0")" || exit 1; pwd)

# shellcheck source=./_in_container_utils.sh
. "${MY_DIR}/_in_container_utils.sh"

assert_in_container

output_verbose_start

pushd "${AIRFLOW_SOURCES}"  &>/dev/null || exit 1

echo
echo "Running in $(pwd)"
echo

echo
echo "Running Licence check"
echo

export TMP_DIR="${AIRFLOW_SOURCES}"/tmp
export RAT_DIR="${TMP_DIR}/rat"
export RAT_VERSION=0.12
export RAT_JAR="${RAT_DIR}/lib/apache-rat-${RAT_VERSION}.jar"


sudo mkdir -pv "${RAT_DIR}"
sudo chown -R "${AIRFLOW_USER}.${AIRFLOW_USER}" "${RAT_DIR}"
sudo chown -R "${AIRFLOW_USER}.${AIRFLOW_USER}" "${AIRFLOW_SOURCES}/logs"

function acquire_rat_jar () {

  URL="http://repo1.maven.org/maven2/org/apache/rat/apache-rat/${RAT_VERSION}/apache-rat-${RAT_VERSION}.jar"

  JAR="${RAT_JAR}"

  # Download rat launch jar if it hasn't been downloaded yet
  if [[ ! -f "${JAR}" ]]; then
    # Download
    echo "Attempting to fetch rat"
    JAR_DL="${JAR}.part"
    curl -L "${URL}" > "${JAR_DL}" && mv "${JAR_DL}" "${JAR}"
  fi

  if ! jar -tf "${JAR}"; then
    # We failed to download
    rm "${JAR}"
    echo >&2 "Our attempt to download rat locally to ${JAR} failed. Please install rat manually."
    exit 1
  fi
  echo "Done downloading."
}

mkdir -p "${RAT_DIR}/lib"

[[ -f "${RAT_JAR}" ]] || acquire_rat_jar || {
    echo >&2 "Download failed. Obtain the rat jar manually and place it at ${RAT_JAR}"
    exit 1
}

# This is the target of a symlink in airflow/www/static/docs -
# and rat exclude doesn't cope with the symlink target doesn't exist
sudo mkdir -p docs/_build/html/

echo "Running license checks. This can take a while."

if ! java -jar "${RAT_JAR}" -E "${AIRFLOW_SOURCES}"/.rat-excludes \
    -d "${AIRFLOW_SOURCES}" > "${AIRFLOW_SOURCES}/logs/rat-results.txt"; then
   echo >&2 "RAT exited abnormally"
   exit 1
fi

ERRORS=$(grep -e "??" "${AIRFLOW_SOURCES}/logs/rat-results.txt")

popd &>/dev/null || exit 1

output_verbose_end

sudo chown -R "${HOST_USER_ID}.${HOST_GROUP_ID}" "${RAT_DIR}"
sudo chown -R "${HOST_USER_ID}.${HOST_GROUP_ID}" "${AIRFLOW_SOURCES}/logs"

if test ! -z "${ERRORS}"; then
    echo >&2
    echo >&2 "Could not find Apache license headers in the following files:"
    echo >&2 "${ERRORS}"
    exit 1
    echo >&2
else
    echo "RAT checks passed."
    echo
fi
