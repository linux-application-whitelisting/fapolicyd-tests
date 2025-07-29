#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd/Regression/RHEL-69136-crash-on-adding-non-regular-file
#   Description: Verify that fapolicyd does not crash on adding directory with non-regular files (sockets, pipes) to trust database
#   Author: Natália Bubáková <nbubakov@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2024 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/bin/rhts-environment.sh || :
. /usr/share/beakerlib/beakerlib.sh || exit 1
PACKAGE="fapolicyd"

rlJournalStart
    rlPhaseStartSetup
        rlRun "rlImport --all" 0 "Import libraries" || rlDie "cannot continue"
        rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
        CleanupRegister "rlRun 'rm -r $TmpDir' 0 'Removing tmp directory'"
        CleanupRegister 'rlRun "popd"'
        rlRun "pushd $TmpDir"
        CleanupRegister 'rlRun "fapCleanup"'
        rlRun "fapSetup"
        CleanupRegister 'rlRun "fapStop"'
        rlRun "fapStart"
        rlRun "set -o pipefail"
    rlPhaseEnd

    rlPhaseStartTest
        TEST_DIR="non_regular_files_dir"
        CleanupRegister "rlRun 'rm -rf ./${TEST_DIR}'"
        mkdir -p ./${TEST_DIR}

        CleanupRegister 'rlRun "killall -9 socat" 0-255'
        rlRun "mkfifo ./${TEST_DIR}/pipe"
        rlRun "socat UNIX-LISTEN:"./${TEST_DIR}/socket" /dev/null &"
        rlRun "sleep 3"
        rlRun "test -S ./${TEST_DIR}/socket && test -p ./${TEST_DIR}/pipe" 0 "Verify non-regular files exist"

        CleanupRegister "rlRun 'fapolicyd-cli -f delete ./${TEST_DIR}' 0-255"
        rlRun -s "fapolicyd-cli -f add ./${TEST_DIR}" 1 "Add a directory with non-regular files to trust database"
        rlAssertNotGrep "Segmentation fault[[:space:]]+\(core dumped\)" $rlRun_LOG -E
        rlRun "fapolicyd-cli --dump-db | grep ${TmpDir}/${TEST_DIR}" 1 "Verify that the directory is not in trust database"
    rlPhaseEnd

    rlPhaseStartCleanup
        CleanupDo
    rlPhaseEnd
    rlJournalPrintText
rlJournalEnd
