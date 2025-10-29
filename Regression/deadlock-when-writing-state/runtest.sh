#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd/Regression/deadlock-when-writing-state
#   Description: test if fapolicyd deadlocks when writing its state file
#   Author: Milos Malik <mmalik@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2025 Red Hat, Inc.
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
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        rlRun "rlImport --all" || rlDie 'cannot continue'
        rlFileBackup /etc/fapolicyd/fapolicyd.conf
        fapSetConfigOption 'allow_filesystem_mark' '1'
    rlPhaseEnd

    rlPhaseStartTest "RHEL-120827 + RHEL-122158"
        rlRun "fapServiceStart"
        sleep 2
        rlRun "ip netns add test-ns"
        rlRun "ip netns list"
        rlRun "rlServiceStatus fapolicyd"
        rlRun "ls -l /run/fapolicyd/fapolicyd.state"
        sleep 2
        rlRun "pkill -USR1 fapolicyd"
        rlRun "rlServiceStatus fapolicyd"
        rlRun "ls -l /run/fapolicyd/fapolicyd.state"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "ip netns del test-ns"
        rlRun "ip netns list"
        rlRun "fapServiceStop"
        rlFileRestore
    rlPhaseEnd
rlJournalEnd

