#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd/Regression/RHEL-69136-crash-on-adding-non-regular-file
#   Description: Verify that fapolicyd does not crash on adding directory with sockets to trust database
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

rlJournalStart
    rlPhaseStartSetup
        rlRun "rlImport --all" 0 "Import libraries" || rlDie "cannot continue"
        CleanupRegister "rlRun 'rm -r $TmpDir' 0 'Removing tmp directory'"
        rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
        CleanupRegister 'rlRun "popd"'
        rlRun "pushd $TmpDir"
        CleanupRegister 'rlRun "fapCleanup"'
        rlRun "fapSetup"
        CleanupRegister 'rlRun "fapStop"'
        rlRun "fapStart"
        rlRun "set -o pipefail"
    rlPhaseEnd

    rlPhaseStartTest
        CleanupRegister 'rlRun "rm -rf ./socket_dir"'
        mkdir -p ./socket_dir

        CleanupRegister 'rlRun "killall -9 socat" 0-255'
        rlRun "socat UNIX-LISTEN:"./socket_dir/socket" /dev/null &"
        rlRun "sleep 3"
        CleanupRegister 'rlRun "fapolicyd-cli -f delete ./socket_dir" 0-255'
        rlRun -s "fapolicyd-cli -f add ./socket_dir" 0 "Add a directory with a socket to trust database"
        rlAssertNotGrep "Segmentation fault[[:space:]]+\(core dumped\)" $rlRun_LOG -E
        rlRun "fapolicyd-cli --dump-db | grep ${TmpDir}/socket_dir" 0 "Verify that the socket directory is in trust database"
    rlPhaseEnd

    rlPhaseStartCleanup
        CleanupDo
    rlPhaseEnd
rlJournalEnd
