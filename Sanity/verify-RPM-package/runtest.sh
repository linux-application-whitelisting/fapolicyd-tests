#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd/Sanity/verify-RPM-package
#   Description: test if anything is missing from the package
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
        rlServiceStop fapolicyd
    rlPhaseEnd

    rlPhaseStartTest "RHEL-186528 + RHEL-186534"
        # 1 is OK because the configuration file might be modified
        rlRun -s "rpm -Va fapolicyd\*" 0,1
        rlAssertNotGrep "missing.*/run/fapolicyd" $rlRun_LOG -i
        rlRun "systemctl start fapolicyd"
        rlRun -s "rpm -Va fapolicyd\*" 0,1
        rlAssertNotGrep "missing.*/run/fapolicyd" $rlRun_LOG -i
        rlRun "systemctl stop fapolicyd"
        rlRun -s "rpm -Va fapolicyd\*" 0,1
        rlAssertNotGrep "missing.*/run/fapolicyd" $rlRun_LOG -i
    rlPhaseEnd

    rlPhaseStartCleanup
        rlServiceRestore fapolicyd
    rlPhaseEnd
rlJournalEnd

