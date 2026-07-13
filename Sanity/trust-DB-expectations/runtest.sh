#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd/Sanity/trust-DB-expectations
#   Description: test if trust DB has correct user/group/mode etc.
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
        rlAssertRpm fapolicyd-selinux
        rlServiceStop fapolicyd
        rlFileBackup --missing-ok /var/lib/fapolicyd/data.mdb
        rlFileBackup --missing-ok /var/lib/fapolicyd/lock.mdb
    rlPhaseEnd

    rlPhaseStartTest "RHEL-186511 + RHEL-186512"
        rlRun "ls -al /var/lib/fapolicyd"
        rlRun "fapolicyd-cli --delete-db"
        rlRun "ls -al /var/lib/fapolicyd"
        rlRun "fapolicyd-cli --check-trustdb"
        rlRun "ls -al /var/lib/fapolicyd"
        rlRun -s "rpm -V fapolicyd" 0-255
        rlAssertNotGrep '/var/lib/fapolicyd/data.mdb' $rlRun_LOG
        rlAssertNotGrep '/var/lib/fapolicyd/lock.mdb' $rlRun_LOG
    rlPhaseEnd

    rlPhaseStartCleanup
        rlFileRestore
        rlServiceRestore fapolicyd
    rlPhaseEnd
rlJournalEnd

