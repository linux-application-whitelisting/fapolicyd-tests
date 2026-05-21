#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd/Stress/effect-on-source-RPM-rebuild
#   Description: test how much does fapolicyd affect a source RPM rebuild
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
        rlFileBackup /etc/fapolicyd/rules.d/22-buildroot.rules
#        rlRun "cat <<EOF > /etc/fapolicyd/rules.d/22-buildroot.rules
# allow perm=any uid=root : dir=/root/rpmbuild
# allow perm=any uid=root trust=1 : all
# EOF"
    rlPhaseEnd

    rlPhaseStartTest "RHEL-2611"
        rlRun "yumdownloader --source systemd"
        rlRun "yum-builddep ./systemd-* --enablerepo '*' -y"

        rlServiceStart fapolicyd
        rlRun "systemctl status fapolicyd -l"
        sleep 1
        rlRun "fapolicyd-cli --check-status"

        rlRun "rm -rf ~/rpmbuild"
        rlRun "rpm -ivh ./systemd-*"
        rlRun "time rpmbuild -bb ~/rpmbuild/SPECS/systemd.spec >& output-with.txt"
        rlAssertNotGrep "Operation not permitted" output-with.txt -i
        rlRun "find ~/rpmbuild/RPMS/ -type f | grep 'systemd.*rpm$'"

        rlServiceStop fapolicyd

        rlRun "rm -rf ~/rpmbuild"
        rlRun "rpm -ivh ./systemd-*"
        rlRun "time rpmbuild -bb ~/rpmbuild/SPECS/systemd.spec >& output-without.txt"
        rlAssertNotGrep "Operation not permitted" output-without.txt -i
        rlRun "find ~/rpmbuild/RPMS/ -type f | grep 'systemd.*rpm$'"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "rm -f /etc/fapolicyd/rules.d/22-buildroot.rules"
        rlRun "rm -f output-with.txt output-without.txt"
        rlFileRestore
    rlPhaseEnd
rlJournalEnd

