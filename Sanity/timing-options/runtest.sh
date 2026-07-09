#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd/Sanity/timing-options
#   Description: test if the timing options work as expected
#   Author: Milos Malik <mmalik@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2026 Red Hat, Inc.
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
        rlAssertRpm fapolicyd
        rlRun "fapolicyd-cli --help | grep timing"

        rlServiceStop fapolicyd
        rlFileBackup /etc/fapolicyd/fapolicyd.conf

        rlRun "sed -i '/^[#[:space:]]*timing_collection/d' /etc/fapolicyd/fapolicyd.conf"
        rlRun "echo 'timing_collection = manual' >> /etc/fapolicyd/fapolicyd.conf"
        rlRun "grep timing_collection /etc/fapolicyd/fapolicyd.conf"

        rlServiceStart fapolicyd
        sleep 2
    rlPhaseEnd

    rlPhaseStartTest "Execute Timing Profile Run"
        # Trigger the timing engine start sequence
        rlRun -s "fapolicyd-cli --timing-start"
        rlAssertGrep "decision timing start requested" $rlRun_LOG -i
        
        # Simulate high I/O filesystem workload for fanotify interception
        rlLog "Simulating user activity and file accesses..."
        for I in `seq 1 16` ; do
            rlRun "ls /usr/bin > /dev/null"
            rlRun "uname -a > /dev/null"
        done
        rlRun "sleep 1"
        
        if [ -f /run/fapolicyd/fapolicyd.timing ] ; then
            rlRun "cat /run/fapolicyd/fapolicyd.timing"
            rlRun "rm -f /run/fapolicyd/fapolicyd.timing"
        fi

        # Stop the timing trace window
        rlRun -s "fapolicyd-cli --timing-stop"
        
        # Assert the generated file is populated with valid report keywords
        rlAssertGrep "worker" $rlRun_LOG -i
        rlAssertGrep "latency" $rlRun_LOG -i
        rlAssertGrep "decision" $rlRun_LOG -i
        rlAssertGrep "queue" $rlRun_LOG -i

        rlRun "cat /run/fapolicyd/fapolicyd.timing"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlFileRestore
        rlServiceRestore
    rlPhaseEnd
rlJournalEnd

