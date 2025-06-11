#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd-tests/Regression/RHEL-59776-fapolicyd-deadlock
#   Description: The evaluator will configure fapolicyd to allow execution
#                 of executable based on path, hash and directory.
#                 The evaluator will then attempt to execute executables.
#                 The evaluator will ensure that the executables
#                 that are allowed to run has been executed and the executables
#                 that are not allowed to run will be denied.
#                 Test also covers verification of rpm-locking mechanism for
#                 database during fapolicyd update.
#   Author: Patrik Koncity <dpkoncity@redhat.com>
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


rlJournalStart && {
  rlPhaseStartSetup && {
    rlRun "rlImport --all" 0 "Import libraries" || rlDie "cannot continue"
    rlRun 'TmpDir=$(mktemp -d)' 0 'Creating tmp directory'
    CleanupRegister "rlRun 'rm -r $TmpDir' 0 'Removing tmp directory'"
    CleanupRegister 'rlRun "popd"'
    rlRun "pushd $TmpDir"
    CleanupRegister 'rlRun "rm -rf /root/rpmbuild"'
    CleanupRegister 'rlRun "rpm -e fapTestPackage"'
    fapPrepareTestPackages
    CleanupRegister 'rlRun "fapCleanup"'
    rlRun "fapSetup"
    CleanupRegister 'rlRun "fapStop"'
    rlRun "fapStart"
  rlPhaseEnd; }

  rlPhaseStartTest "Verify rpm locking mechanism during update" && {
    CleanupRegister --mark 'rlRun "rm -rf ~/rpmbuild"'

    fapPrepareTestPackageContent
    rlRun "sed -i -r 's/(Version:).*/\1 3/' ~/rpmbuild/SPECS/fapTestPackage.spec"
    rlRun "sed -i -r 's/fapTestProgram/\03/' ~/rpmbuild/SOURCES/fapTestProgram.c"
    rlRun "sed -i -r 's/#scriptlet/%post\necho \"wait 10s\"; sleep 10; echo \"done\"/' ~/rpmbuild/SPECS/fapTestPackage.spec"
    rlRun "rpmbuild -ba ~/rpmbuild/SPECS/fapTestPackage.spec"
    pkg=$(ls -1 ~/rpmbuild/RPMS/*/fapTestPackage-*)

    CleanupRegister "rlRun 'rpm -evh fapTestPackage'"
    rlRun "yum install -y $pkg 1>/dev/null  &"
    rlRun "sleep 1" 0 "Wait for installation to commence."
    rlRun "fapolicyd-cli --update"
    rlRun "sleep 10" 0 "Wait for installation to finish"

    journalctl -b -u fapolicyd | tail -n 10

    rlRun -s "fapServiceOut"
    rlAssertGrep "fapolicyd-rpm-loader spawned with pid: [0-9]+" $rlRun_LOG -Eq

    CleanupDo --mark
  rlPhaseEnd; }

  # Rethink the test phase for change in implementation 
  rlPhaseStartTest "Verify there is no deadlock" && {
    rlRun "fapStart --debug-deny"
    rlRun "rpm -ivh ${fapTestPackage[1]}"
    rlRun "rpm -i ${fapTestPackage[1]} ; rpm -i ${fapTestPackage[1]} ; rpm -i ${fapTestPackage[1]} ; rpm -i ${fapTestPackage[1]} ; rpm -i ${fapTestPackage[1]} ;" 1
    fapStop
    rlRun -s "fapServiceOut -t"
    # rlAssertGrep 'Closing FDs from buffer, size:' $rlRun_LOG
  rlPhaseEnd; }

  rlPhaseStartCleanup && {
    CleanupDo
  rlPhaseEnd; }
  rlJournalPrintText
rlJournalEnd; }
