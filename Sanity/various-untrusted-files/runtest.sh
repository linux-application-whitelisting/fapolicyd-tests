#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd/Sanity/selinux-policy-files-trusted
#   Description: test if fapolicyd trusts files brought by various packages
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
        rlRun "rpm -qa | grep selinux-policy"
        rlRun "rpm -qa | grep redhat-rpm-config"
        rlServiceStop fapolicyd
    rlPhaseEnd

    rlPhaseStartTest "RHEL-94661 + RHEL-94786"
        rlRun "systemctl start fapolicyd"
        rlRun "systemctl status fapolicyd -l --no-pager"
        sleep 1

        rlRun -s "fapolicyd-cli --check-trustdb"
        rlAssertNotGrep "selinux.*miscompares" $rlRun_LOG -Ei
        rlAssertNotGrep "annobin.*miscompares" $rlRun_LOG -Ei
        rm -f $rlRun_LOG

        rlRun "yum -y reinstall selinux-policy*"

        rlRun -s "fapolicyd-cli --check-trustdb"
        rlAssertNotGrep "selinux.*miscompares" $rlRun_LOG -Ei
        rlAssertNotGrep "annobin.*miscompares" $rlRun_LOG -Ei
        rm -f $rlRun_LOG
    rlPhaseEnd

    rlPhaseStartCleanup
        rlServiceStop fapolicyd
        rlServiceRestore fapolicyd
    rlPhaseEnd
rlJournalEnd

