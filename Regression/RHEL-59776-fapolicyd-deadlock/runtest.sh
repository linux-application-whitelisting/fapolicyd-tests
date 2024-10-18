#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd-tests/Regression/RHEL-59776-fapolicyd-deadlock
#   Description: The evaluator will configure fapolicyd to allow execution of executable based on path, hash and directory. The evaluator will then attempt to execute executables. The evaluator will ensure that the executables that are allowed to run has been executed and the executables that are not allowed to run will be denied.
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
    CleanupRegister 'fapCleanup'
    fapPrepareTestPackages
    CleanupRegister 'rlRun "rpm -e fapTestPackage"'
  rlPhaseEnd; }

  rlPhaseStartTest "Check properly closing FD and increasing buffer" && {
    rlRun "fapStart --debug-deny"
    rlRun "rpm -ivh ${fapTestPackage[1]}"
    rlRun "rpm -i ${fapTestPackage[1]} ; rpm -i ${fapTestPackage[1]} ; rpm -i ${fapTestPackage[1]} ; rpm -i ${fapTestPackage[1]} ; rpm -i ${fapTestPackage[1]} ;" 1
    fapStop
    rlRun -s "fapServiceOut -t"
    rlAssertGrep 'Closing FDs from buffer, size:' $rlRun_LOG 
  rlPhaseEnd; }

  rlPhaseStartCleanup && {
    CleanupDo
  rlPhaseEnd; }
  rlJournalPrintText
rlJournalEnd; }
