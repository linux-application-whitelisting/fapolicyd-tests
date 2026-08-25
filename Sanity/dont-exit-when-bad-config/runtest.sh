#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd/Sanity/dont-exit-when-bad-config
#   Description: test if fapolicyd stays running when config file is broken
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
        START_TIME=$(date '+%T')
        rlAssertRpm fapolicyd
        rlFileBackup /etc/fapolicyd/fapolicyd.conf
        rlServiceStart fapolicyd
    rlPhaseEnd

    rlPhaseStartTest "RHEL-189484 + RHEL-216973"
        rlRun "echo 'invalid_option = invalid_value' >> /etc/fapolicyd/fapolicyd.conf"
        rlRun "kill -HUP $(pidof fapolicyd)"
        rlRun "sleep 4s"
        rlRun -s "journalctl -u fapolicyd --since ${START_TIME}"
        rlAssertGrep "fapolicyd-rpm-loader.*unknown keyword" $rlRun_LOG -i
        rlAssertGrep "fapolicyd-rpm-loader.*bad config" $rlRun_LOG -i
        rlRun "systemctl status fapolicyd -l --no-pager"
        rlRun "ps -efZ | grep -v grep | grep ':fapolicyd_t:.*/fapolicyd'"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlFileRestore
        rlServiceRestore fapolicyd
    rlPhaseEnd
rlJournalEnd

