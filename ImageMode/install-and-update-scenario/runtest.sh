#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd-tests/ImageMode/install-and-update-scenario
#   Description: Test scenario with bootc upgrade and rpm ostree for package update while fapolicyd is active
#   Author: Natália Bubáková <nbubakov@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2025 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh || exit 1

COOKIE_1=/var/tmp/fapolicyd-install-package-boot
COOKIE_2=/var/tmp/fapolicyd-update-package-boot
PACKAGE="fapolicyd"
PACKAGE_MANAGER="dnf" # or "rpm"
TEST_PROGRAM_DIR="/var/fapolicyd-test-dir/bin"

rlJournalStart

    if [[ ! -e $COOKIE_1 && ! -e $COOKIE_2 ]]; then
        rlPhaseStartSetup
            rlRun "rlImport --all" 0 "Import libraries" || rlDie "cannot continue"
            rlAssertRpm $PACKAGE
            rlFileBackup --clean $TEST_PROGRAM_DIR
            rlRun "mkdir -p $TEST_PROGRAM_DIR"
            rlRun "set -o pipefail"
        rlPhaseEnd

        rlPhaseStartTest "Pre-reboot ($PACKAGE_MANAGER)"
            # setup fapTestPackage
            rlRun "fapPrepareTestPackages --program-dir ${TEST_PROGRAM_DIR}"
            rlRun "fapSetup"
            rlRun "fapStart"

            fapTestPackage1=$(ls -1 | grep fap | sed -n '1p')
            rlRun "bootc image copy-to-storage"

            # install fapTestPackage
            [[ $PACKAGE_MANAGER == "dnf" ]] && install_cmd="dnf -y install ${fapTestPackage1} && dnf -y clean all"
            [[ $PACKAGE_MANAGER == "rpm" ]] && install_cmd="rpm -ivh ${fapTestPackage1}"
            cat <<EOF > Containerfile
FROM localhost/bootc:latest
COPY ${fapTestPackage1} .
RUN ${install_cmd}
EOF

            rlRun "cat Containerfile"
            rlRun "podman build -t localhost/test_package ."
            rlRun "bootc switch --transport containers-storage localhost/test_package"

            rlRun "touch $COOKIE_1"
        rlPhaseEnd

        tmt-reboot

    elif [[ -e $COOKIE_1 ]]; then
        rlPhaseStartTest "Post-reboot 1 - Verification after package installation ($PACKAGE_MANAGER)"
            rlRun "rlImport --all" 0 "Import libraries" || rlDie "cannot continue"
            rlRun "fapStart"

            # verify package installation
            fapTestPackage1=$(ls -1 | grep fap | sed -n '1p')
            rlRun "systemctl is-active fapolicyd" 0 "Verify fapolicyd is active"
            rlRun "rpm -q $fapTestPackage1" 0 "Verify package is installed"
            rlRun "fapStop"
            rlRun "fapolicyd-cli -D | grep fapTestProgram" 0 "Verify package is trusted by fapolicyd"

            fapTestPackage2=$(ls -1 | grep fap | sed -n '2p')
            rlRun "bootc image copy-to-storage"

            # update fapTestPackage
            [[ $PACKAGE_MANAGER == "dnf" ]] && install_cmd="dnf -y install ${fapTestPackage2} && dnf -y clean all"
            [[ $PACKAGE_MANAGER == "rpm" ]] && install_cmd="rpm -Uvh ${fapTestPackage2}"
            cat <<EOF > Containerfile
FROM localhost/bootc:latest
COPY ${fapTestPackage2} .
RUN ${install_cmd}
EOF
            rlRun "cat Containerfile"
            rlRun "podman build -t localhost/test_package_updated ."
            rlRun "bootc switch --transport containers-storage localhost/test_package_updated"

            rlRun "mv $COOKIE_1 $COOKIE_2"
        rlPhaseEnd

        tmt-reboot

    elif [[ -e $COOKIE_2 ]]; then
        rlPhaseStartTest "Post-reboot 2 - Verification after package update ($PACKAGE_MANAGER)"
            rlRun "rlImport --all" 0 "Import libraries" || rlDie "cannot continue"
            rlRun "fapStart"

            # Verify package update
            fapTestPackage2=$(ls -1 | grep fap | sed -n '2p')
            rlRun "systemctl is-active fapolicyd" 0 "Verify fapolicyd is active"
            rlRun "rpm -q $fapTestPackage2" 0 "Verify package is installed"
            rlRun "fapStop"
            rlRun "fapolicyd-cli -D | grep fapTestProgram" 0 "Verify package is trusted by fapolicyd"

            rlRun "rm -f $COOKIE_2"
        rlPhaseEnd

        rlPhaseStartCleanup
            # There must be a proper cleanup via container if both package managers are run
            # [[ $PACKAGE_MANAGER == "dnf" ]] && rlRun 'dnf remove -y fapTestPackage'
            # [[ $PACKAGE_MANAGER == "rpm" ]] && rlRun 'rpm -evh fapTestPackage'
            rlRun "rm -rf $TEST_PROGRAM_DIR"
            rlRun "rm -rf ~/rpmbuild"
            rlRun "fapCleanup"
            rlRun "rlFileRestore"
        rlPhaseEnd
    fi
    
    rlJournalPrintText
rlJournalEnd