#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd/Sanity/compact-trustdb-option
#   Description: test if the --compact-trustdb option works as expected
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
        rlRun "fapolicyd-cli --help | grep compact-trustdb"
        rlServiceStart fapolicyd
        sleep 2
    rlPhaseEnd

    rlPhaseStartTest "Test the --compact-trustdb option"
        # Capture the status before compaction
        rlRun "fapolicyd-cli --check-status > before.txt"
        rlRun "ls -ail /var/lib/fapolicyd/"

        # Initiate the compaction and wait until it finishes
        rlRun "fapolicyd-cli --compact-trustdb"
        rlRun -s "systemctl status fapolicyd -l --no-pager"
        rlAssertGrep "requested trust DB.*compaction" $rlRun_LOG -i
        for I in `seq 1 15` ; do
            systemctl status fapolicyd -l --no-pager | grep -qi "trust DB compaction request completed" && break
            sleep 1
        done
        rlRun -s "systemctl status fapolicyd -l --no-pager"
        rlAssertGrep "trust DB compaction request completed" $rlRun_LOG -i

        # Capture the status after compaction
        rlRun "fapolicyd-cli --check-status > after.txt"
        rlRun "ls -ail /var/lib/fapolicyd/"

        # Find the differences in captured outputs
        rlRun -s "diff before.txt after.txt" 1

        # Assert the effects of the compaction
        rlAssertGrep "trust database generation" $rlRun_LOG -i
        rlAssertGrep "LMDB environment generation" $rlRun_LOG -i
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "rm -f before.txt after.txt"
        rlServiceRestore fapolicyd
    rlPhaseEnd
rlJournalEnd

