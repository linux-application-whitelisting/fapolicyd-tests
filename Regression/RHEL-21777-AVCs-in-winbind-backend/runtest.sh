#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd-tests/Regression/RHEL-21777-AVCs-in-winbind-backend
#   Description: Verify fapolicyd rules do not show AVCs for winbind backend.
#                Test simplifies reproduction of fapolicyd rule:
#                `allow perm=any uid=satellite-automation : ftype=text/x-python trust=0`
#                by making fapolicyd access the winbind via its prioritization in /etc/nsswitch.conf
#   Author: Natália Bubáková <nbubakov@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2024 Red Hat, Inc.
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
        rlRun "rlImport --all" 0 "Import libraries" || rlDie "cannot continue"
        rlRun 'TmpDir=$(mktemp -d)' 0 'Creating tmp directory'
        rlRun "pushd $TmpDir"
        rlFileBackup /etc/nsswitch.conf
        rlRun "set -o pipefail"
        rlRun -s "authselect current" 0 "Save current authselect profile"
        ORIG_AUTHSELECT_PROFILE=$(cat $rlRun_LOG | awk -F ': ' '/Profile ID/ {print $2}')
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "authselect select winbind"
        rlRun "sudo sed -i -E 's/^(passwd|group):[[:space:]]*(.*)winbind(.*)$/\1: winbind \2\3/' /etc/nsswitch.conf"
        rlRun "grep -E '^(passwd|group):[[:space:]]*winbind' /etc/nsswitch.conf" 0 "Check winbind is the first in order"
        rlRun "systemctl start winbind"
        rlRun "systemctl restart fapolicyd"
        rlRun -s "ausearch -m AVC -c fapolicyd -i" 1 "Check there is no match for fapolicyd AVCs"
        rlAssertGrep "<no matches>" $rlRun_LOG
        rlAssertNotGrep "type=AVC.*denied.*comm=fapolicyd.*path=/run/samba/winbindd/pipe.*" $rlRun_LOG
    rlPhaseEnd

    rlPhaseStartCleanup
        rlFileRestore
        rlRun "authselect select $ORIG_AUTHSELECT_PROFILE"
        rlRun "systemctl daemon-reload"
        rlRun "systemctl stop winbind"
        rlRun "systemctl restart fapolicyd"
        rlRun "popd"
        rlRun "rm -rf $TmpDir" 0 "Remove tmp directory"
    rlPhaseEnd
rlJournalEnd
