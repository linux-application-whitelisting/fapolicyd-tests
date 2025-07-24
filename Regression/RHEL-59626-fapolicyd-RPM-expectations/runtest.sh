#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd-tests/Regression/RHEL-59626-fapolicyd-RPM-expectations
#   Description: Verify that file /run/fapolicyd does not differ from RPM expectations
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
        rlRun "pushd $TmpDir"
    rlPhaseEnd

    rlPhaseStartTest
        rlRun "systemctl enable --now fapolicyd"
        rlRun -s "rpm -V fapolicyd" 0 "Verify the file /run/fapolicyd does not differ from RPM expectations"
        rlAssertNotGrep '\.M\.\.\.\.G\.\..*/run/fapolicyd' $rlRun_LOG
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "popd"
        rlRun "rm -r $TmpDir" 0 "Remove tmp directory"
    rlPhaseEnd
    rlJournalPrintText
rlJournalEnd
