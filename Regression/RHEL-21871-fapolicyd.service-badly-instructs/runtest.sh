#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd-tests/Regression/RHEL-21871-fapolicyd.service-badly-instructs
#   Description: Syntactical verification of fapolicyd.service dependancy on nss-user-lookup.target by drop-in
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
PACKAGE="fapolicyd"

rlJournalStart
    rlPhaseStartSetup
        rlRun "rlImport --all" 0 "Import libraries" || rlDie "cannot continue"
        rlRun 'TmpDir=$(mktemp -d)' 0 'Creating tmp directory'
        CleanupRegister "rlRun 'rm -r $TmpDir' 0 'Removing tmp directory'"
        CleanupRegister 'rlRun "popd"'
        rlRun "pushd $TmpDir"
        CleanupRegister 'rlRun "fapCleanup"'
        rlRun "fapSetup"
        rlRun "set -o pipefail"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun -s "systemctl cat fapolicyd.service | sed -n '/^\[Service\]/,/^\[.*\]/p'" 0 "Verify the [Service] section"
        rlAssertNotGrep "After=nss-user-lookup.target" $rlRun_LOG
        rlRun -s "systemctl cat fapolicyd.service | sed -n '/^\[Unit\]/,/^\[Service\]/p'" 0 "Verify the [Unit] section"
        rlAssertGrep "After=local-fs.target systemd-tmpfiles-setup.service" $rlRun_LOG

        CleanupRegister 'rlRun "rm -rf /etc/systemd/system/fapolicyd.service.d/nss-user-lookup.conf"'
        rlRun "mkdir -p /etc/systemd/system/fapolicyd.service.d"
        rlRun "echo -e "[Unit]\nAfter=nss-user-lookup.target" > /etc/systemd/system/fapolicyd.service.d/nss-user-lookup.conf"
        rlRun "systemctl daemon-reload"

        CleanupRegister 'rlRun "fapStop"'
        rlRun "fapStart"
        rlRun "systemctl status fapolicyd | grep -A1 "Drop-In" | grep nss-user-lookup.conf" 0 "Verify that fapolicyd.service has included nss-user-lookup"
    rlPhaseEnd

    rlPhaseStartCleanup
        CleanupDo
    rlPhaseEnd
rlJournalEnd
