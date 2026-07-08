#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd/Sanity/metrics-options
#   Description: test if the metrics options work as expected
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
        rlRun "fapolicyd-cli --help | grep metrics"

        rlFileBackup /etc/fapolicyd/fapolicyd.conf
        rlRun "sed -i '/^[#[:space:]]*reset_strategy/d' /etc/fapolicyd/fapolicyd.conf"
        rlRun "echo 'reset_strategy = manual' >> /etc/fapolicyd/fapolicyd.conf"
        rlRun "grep reset_strategy /etc/fapolicyd/fapolicyd.conf"
        rlServiceStart fapolicyd
        sleep 2
    rlPhaseEnd

    rlPhaseStartTest "Test the --check-metrics option"
        # Generate some daemon activity to populate metrics
        rlRun "fapolicyd-cli --check-status"
        
        # Verify --check-metrics creates/updates the metrics file and contains expected content
        rlRun -s "fapolicyd-cli --check-metrics"
        rlAssertExists "/run/fapolicyd/fapolicyd.metrics"
        
        # Check for essential metrics blocks
        rlAssertGrep "generation" $rlRun_LOG -i
        rlAssertGrep "rule" $rlRun_LOG -i
        rlAssertGrep "object" $rlRun_LOG -i
        rlAssertGrep "subject" $rlRun_LOG -i
        rlAssertGrep "last metrics reset.*never" $rlRun_LOG -i
    rlPhaseEnd

    rlPhaseStartTest "Test the --reset-metrics option"
        # Run some commands to increment counters again
        rlRun "fapolicyd-cli --check-status"
        
        # Capture the metrics before the reset
        rlRun "fapolicyd-cli --check-metrics > before.txt"

        # Execute reset with the -y option to suppress confirmation prompts
        rlRun "fapolicyd-cli --reset-metrics -y"
        
        # Capture the metrics after the reset
        rlRun "fapolicyd-cli --check-metrics > after.txt"

        # Compare the outputs
        rlRun -s "diff before.txt after.txt" 1
        rlAssertGrep "last metrics reset" $rlRun_LOG -i
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "rm -f before.txt after.txt"
        rlFileRestore
        rlServiceRestore
    rlPhaseEnd
rlJournalEnd

