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
TEST_DIR="/var/fapolicyd-test-dir" #/root/bin/

rlJournalStart

    # TODO: for cycle in "dnf rpm"
    package_manager=dnf

    if [[ ! -e $COOKIE_1 && ! -e $COOKIE_2 ]]; then
        rlPhaseStartSetup
            rlAssertRpm $PACKAGE
            rlFileBackup --clean $TEST_DIR
            rlRun "mkdir -p $TEST_DIR/{,bin}"
            rlRun "set -o pipefail"
        rlPhaseEnd

        rlPhaseStartTest "Pre-reboot"

            # setup fapTestPackage
            rlRun "fapPrepareTestPackages --program-dir ${TEST_DIR}/bin"
            rlRun "fapSetup"
            rlRun "fapStart"
            rlRun "bootc image copy-to-storage"

            # install fapTestPackage
            [[ $package_manager == "dnf" ]] && {
            # (TODO: copy test-dir to bootc image so it can be installed)
            cat <<EOF > Containerfile
FROM localhost/bootc:latest
RUN dnf -y install ${fapTestPackage[0]} && dnf -y clean all
EOF
}
            [[ $package_manager == "rpm" ]] && {
            cat <<EOF > Containerfile
FROM localhost/bootc:latest
RUN rpm -ivh ${fapTestPackage[0]}
EOF
}
            rlRun "podman build -t localhost/test_package ."
            rlRun "bootc switch --transport containers-storage localhost/test_package"

            rlRun "touch $COOKIE_1"
        rlPhaseEnd

        tmt-reboot

    elif [[ -e $COOKIE_1 ]]; then
        rlPhaseStartTest "Post-reboot - Verification after package installation"

            # verify package installation
            rlRun "fapStop"
            rlRun "systemctl is-active fapolicyd" 0 "Verify fapolicyd is active"
            rlRun "rpm -q $fapTestProgram" 0 "Verify package is installed"
            rlRun "fapolicyd-cli -D | grep $fapTestProgram" 0 "Verify package is trusted by fapolicyd"
            rlRun "fapStart"

            # update fapTestPackage
            [[ $package_manager == "dnf" ]] && {
            cat <<EOF > Containerfile
FROM localhost/bootc:latest
RUN dnf -y install ${fapTestPackage[1]} && dnf -y clean all
EOF
}
            [[ $package_manager == "rpm" ]] && {
            cat <<EOF > Containerfile
FROM localhost/bootc:latest
RUN rpm -ivh ${fapTestPackage[1]}
EOF
}
            rlRun "podman build -t localhost/test_package_updated ."
            rlRun "bootc switch --transport containers-storage localhost/test_package_updated"

            rlRun "mv $COOKIE_1 $COOKIE_2"
        rlPhaseEnd

        tmt-reboot

    elif [[ -e $COOKIE_2 ]]; then
        rlPhaseStartTest "Post-reboot - Verification after package update"

            # verify package update
            rlRun "fapStop"
            rlRun "systemctl is-active fapolicyd" 0 "Verify fapolicyd is active"
            rlRun "rpm -q $fapTestProgram" 0 "Verify package is installed"
            rlRun "fapolicyd-cli -D | grep $fapTestProgram" 0 "Verify package is trusted by fapolicyd"

            rlRun "rm -f $COOKIE_2"
        rlPhaseEnd

        rlPhaseStartCleanup
            [[ $package_manager == "dnf" ]] && rlRun 'dnf remove -y fapTestPackage'
            [[ $package_manager == "rpm" ]] && rlRun 'rpm -evh fapTestPackage'
            rlRun "rm -rf $TEST_DIR"
            rlRun "rm -rf ~/rpmbuild"
            rlRun "fapCleanup"
            rlRun "rlFileRestore"
        rlPhaseEnd
    fi
    
    rlJournalPrintText
rlJournalEnd