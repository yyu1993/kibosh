#!/usr/bin/env bash

#
# Copyright 2017 Confluent Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

TARGET=""
MIRROR=""
KIBOSH_PID=""
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TEST_RESULT=""

usage() {
    local exit_status="${1}"
    cat <<EOF
systest.sh: test the kibosh filesystem.

usage:
    systest.sh [--help/-h] [test-name]

flags:
    --help/-h: This help message

available tests:
    all: run all tests.  This is the default if no argument is given.
    simple: test that we can start kibosh and mount the FS.
    fs_test: start kibosh and run fs_test.
EOF
    exit "${exit_status}"
}

die() {
    echo "${@}"
    exit 1
}

bg_do() {
    echo "${@}"
    "${@}" &
}

start_kibosh() {
    # Locate the kibosh binary.  It should be in our current test script
    # directory, because CMake puts it there.
    KIBOSH_BIN="${SCRIPT_DIR}/kibosh"
    [[ -x "${KIBOSH_BIN}" ]] || die "failed to find kibosh binary at ${KIBOSH_BIN}."

    # Initialize constants
    local NEW_TARGET="/dev/shm/underfs.$RANDOM.$RANDOM"
    mkdir "${NEW_TARGET}" || die "failed to mkdir ${NEW_TARGET}"
    TARGET="${NEW_TARGET}"

    local NEW_MIRROR="/dev/shm/overfs.$RANDOM.$RANDOM"
    mkdir "${NEW_MIRROR}" || die "failed to mkdir ${NEW_MIRROR}"
    MIRROR="${NEW_MIRROR}"

    bg_do "${KIBOSH_BIN}" --control-mode 666 --target ${TARGET} -f "${MIRROR}"
    KIBOSH_PID=$!

    CONTROL_FILE="${MIRROR}/kibosh_control"
    while [[ ! -f "${CONTROL_FILE}" ]]; do
        sleep 0.01
        [[ -d "/proc/${KIBOSH_PID}" ]] || die "kibosh proces exited."
    done
}

simple_test() {
    TEST_RESULT="FAILURE"
    echo "*** RUNNING simple_test..."
    start_kibosh
    touch "${MIRROR}/hi"
    TEST_RESULT="SUCCESS"
}

fs_test() {
    TEST_RESULT="FAILURE"
    echo "*** RUNNING fs_test..."
    FS_TEST_BIN="${SCRIPT_DIR}/fs_test"
    [[ -x "${FS_TEST_BIN}" ]] || die "failed to find fs_test binary at ${FS_TEST_BIN}"
    start_kibosh
    "${FS_TEST_BIN}" "${MIRROR}" || die "${FS_TEST_BIN} failed"
    TEST_RESULT="SUCCESS"
}

invoke_self() {
    local arg="${1}"
    echo "***************** ${BASH_SOURCE[0]}" "${arg}"
    "${BASH_SOURCE[0]}" "${arg}" || die "** $arg failed."
}

test_all() {
    invoke_self simple
    invoke_self fs_test
}

cleanup() {
    echo "************ CLEANUP *****************"
    if [[ "${KIBOSH_PID}" != "" ]]; then
        echo "*** kill ${KIBOSH_PID}"
        kill -- "${KIBOSH_PID}"
        wait
    fi
    if [[ "${TARGET}" != "" ]]; then
        echo "*** rm -rf -- ${TARGET}"
        rm -rf -- "${TARGET}"
    fi
    if [[ "${MIRROR}" != "" ]]; then
        echo "*** fusermount -u -- ${MIRROR}"
        fusermount -u -- "${MIRROR}"
        echo "*** rm -rf -- ${MIRROR}"
        rm -rf -- "${MIRROR}"
    fi
    if [[ "${TEST_RESULT}" != "" ]]; then
        echo "*** ${TEST_RESULT}"
    fi
}

trap cleanup EXIT
if [[ $# -lt 1 ]]; then
    TEST_NAME="all"
else
    TEST_NAME="$1"
fi
shift
case "${TEST_NAME}" in
    -h) usage 0;;
    --help) usage 0;;
    all) test_all;;
    simple) simple_test;;
    fs_test) fs_test;;
    *)  echo "Unknown test ${TEST_NAME}"
        echo
        usage 1;;
esac
exit 0
