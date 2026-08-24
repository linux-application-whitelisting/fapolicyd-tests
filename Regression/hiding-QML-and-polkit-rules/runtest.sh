#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd/Regression/
#   Description: test if fapolicyd accepts QML files and polkit rules
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
        rlServiceStart fapolicyd
        rlRun "systemctl status fapolicyd -l --no-pager"
    rlPhaseEnd

    rlPhaseStartTest "RHEL-239786 + RHEL-239990"
        rlLog "install a package with QML files"
        rlRun "dnf install -y plasma-lookandfeel-fedora"
        rlRun "fapolicyd-cli -D | grep -i logout.qml"

        rlLog "find packages with polkit rules and install them"
        rlRun "dnf provides '/usr/share/polkit-1/rules.d/*.rules' 2>/dev/null | grep Filename | cut -d : -f 2 | sort | uniq | tr '\n' ' ' > list.txt"
        rlRun "dnf install -y --skip-broken $(cat list.txt)"
        FS_COUNT=$(find /usr/share/polkit-1/rules.d/ -type f -name \*.rules | wc -l)
        DB_COUNT=$(fapolicyd-cli -D | grep '/usr/share/polkit-1/rules\.d/.*\.rules' | wc -l)
        rlAssertEquals "number of polkit rules files on the filesystem and in the database should be the same" ${FS_COUNT} ${DB_COUNT}
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "rm -f list.txt"
        rlServiceRestore fapolicyd
    rlPhaseEnd
rlJournalEnd

