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

COOKIE_1=/var/tmp/fapolicyd-package-boot-done
COOKIE_2=/var/tmp/fapolicyd-round-two
PACKAGE="fapolicyd"
TEST_DIR="/var/fapolicyd-test-dir" #/root/bin/

rlJournalStart

    # TODO for in "dnf rpm"
    package_manager=dnf

    if [[ ! -e $COOKIE_1 && ! -e $COOKIE_2 ]]; then
        rlPhaseStartSetup
            rlAssertRpm $PACKAGE
            rlFileBackup --clean $TEST_DIR
            rlRun "mkdir -p $TEST_DIR/{,bin}"
            rlRun "set -o pipefail"
        rlPhaseEnd

        rlPhaseTestSetup "Pre-reboot round 1"

            # setup fapTestPackage
            rlRun "fapPrepareTestPackages --program-dir ${TEST_DIR}/bin"
            rlRun "fapSetup"
            rlRun "fapStart"

            # install fapTestPackage
            [[ $package_manager == "dnf" ]] && {
            # rlRun "rpm -ivh ${fapTestPackage[0]}" || rlRun "dnf install -y ${fapTestPackage[0]}"
            cat <<EOF > Containerfile
FROM images.paas.redhat.com/testingfarm/rhel-bootc:9.6
RUN dnf -y install ${fapTestPackage[0]} && dnf -y clean all
EOF
}

            [[ $package_manager == "rpm" ]] && {
            # rlRun "dnf install -y ${fapTestPackage[0]}" || rlRun "rpm -ivh ${fapTestPackage[0]}"
            cat <<EOF > Containerfile
FROM images.paas.redhat.com/testingfarm/rhel-bootc:9.6
RUN rpm -ivh ${fapTestPackage[0]}
EOF
}

            rlRun "podman build -t localhost/test_package ."
            rlRun "bootc switch --transport containers-storage localhost/test_package"

            rlRun "touch $COOKIE_1"
        rlPhaseEnd
    
        tmt-reboot

    else if [[ -e $COOKIE_1 && ! -e $COOKIE_2 ]]; then
        rlPhaseStartTest "Post-reboot round 1"

            rlRun "fapStop"
            rlRun "fapolicyd-cli -D | grep $fapTestProgram"
            rlRun "fapStart"

            # update fapTestPackage
            [[ $package_manager == "dnf" ]] && {
            # rlRun "rpm -ivh ${fapTestPackage[1]}" || rlRun "dnf install -y ${fapTestPackage[1]}"
            cat <<EOF > Containerfile
FROM images.paas.redhat.com/testingfarm/rhel-bootc:9.6
RUN dnf -y install ${fapTestPackage[1]} && dnf -y clean all
EOF
}

            [[ $package_manager == "rpm" ]] && {
            # rlRun "dnf install -y ${fapTestPackage[1]}" || rlRun "rpm -ivh ${fapTestPackage[1]}"
            cat <<EOF > Containerfile
FROM images.paas.redhat.com/testingfarm/rhel-bootc:9.6
RUN rpm -ivh ${fapTestPackage[1]}
EOF
}

            rlRun "podman build -t localhost/test_package_updated ."
            rlRun "bootc switch --transport containers-storage localhost/test_package_updated"

            rlRun "rm -f $COOKIE_1"
            rlRun "touch $COOKIE_2"
        rlPhaseEnd

    else if [[ ! -e $COOKIE_1 && -e $COOKIE_2 ]]; then
        rlPhaseStartTest "Pre-reboot round 2"

            # setup fapTestPackage2
            fapPrepareTestPackageContent
            cp ~/rpmbuild/SPECS/fapTestPackage.spec ~/rpmbuild/SPECS/fapTestPackage2.spec
            sed -i -r 's/(Name:).*/\1 fapTestPackage2/' ~/rpmbuild/SPECS/fapTestPackage2.spec

            sed -i -r 's/(Version:).*/\1 1/' ~/rpmbuild/SPECS/fapTestPackage2.spec
            rpmbuild -ba ~/rpmbuild/SPECS/fapTestPackage2.spec
            sed -i -r 's/(Version:).*/\1 2/' ~/rpmbuild/SPECS/fapTestPackage2.spec
            rpmbuild -ba ~/rpmbuild/SPECS/fapTestPackage2.spec

            mv ~/rpmbuild/RPMS/*/fapTestPackage2-* ./
            fapTestPackage2=( $(find $PWD -name 'fapTestPackage2-*.rpm' | sort) )

            rlRun "fapStart"
            
            # install fapTestPackage2
            rlRun "rpm-ostree install ${fapTestPackage2[0]} --apply-live"
            rlRun "rpm -q ${fapTestPackage2[0]}"


            rlRun "touch $COOKIE_1"
        rlPhaseEnd

        tmt-reboot

    else if [[ -e $COOKIE_1 && -e $COOKIE_2 ]]; then
        rlPhaseStartTest "Post-reboot round 2"

            rlRun "fapStop"
            rlRun "fapolicyd-cli -D | grep $fapTestProgram"
            rlRun "fapStart"

            # update fapTestPackage2
            rlRun "rpm-ostree install ${fapTestPackage2[1]} --apply-live"
            rlRun "rpm -q ${fapTestPackage2[1]}"

            rlRun "rm -f $COOKIE_1"
            rlRun "rm -f $COOKIE_2"
        rlPhaseEnd


        rlPhaseStartCleanup
            [[ $package_manager == "dnf" ]] && rlRun 'dnf remove -y fapTestPackage'
            [[ $package_manager == "rpm" ]] && rlRun 'rpm -evh fapTestPackage'
            rlRun "rm -rf $AIDE_TEST_DIR"
            rlRun "rm -rf ~/rpmbuild"
            rlRun "fapCleanup"
            rlRun "fapStop"
            rlRun "rlFileRestore"
        rlPhaseEnd
    fi
    
    rlJournalPrintText
rlJournalEnd
