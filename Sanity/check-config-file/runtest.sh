#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd/Sanity/check-config-file
#   Description: test if fapolicyd complains about a missing EOL in its config file
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
        rlAssertRpm fapolicyd
        rlFileBackup /etc/fapolicyd/fapolicyd.conf
    rlPhaseEnd

    rlPhaseStartTest "RHEL-65625 + RHEL-124283"
        rlRun "nl /etc/fapolicyd/fapolicyd.conf"
        rlRun "sed -i 's/^.*report_interval.*$//' /etc/fapolicyd/fapolicyd.conf"
        rlRun "echo -n 'report_interval = 0' >> /etc/fapolicyd/fapolicyd.conf"
        rlRun "nl /etc/fapolicyd/fapolicyd.conf"
        rlRun -s "fapolicyd-cli --check-config"
        rlAssertNotGrep "error|skipping|too long" $rlRun_LOG -Ei
    rlPhaseEnd

    rlPhaseStartCleanup
        rm -f $rlRun_LOG
        rlFileRestore
    rlPhaseEnd
rlJournalEnd

