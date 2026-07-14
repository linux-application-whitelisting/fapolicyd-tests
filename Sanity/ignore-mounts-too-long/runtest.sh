#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd/Sanity/ignore-mounts-too-long
#   Description: test if ignore_mounts option allows enough entries
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

ENTRY_COUNT=128

rlJournalStart
    rlPhaseStartSetup
        rlAssertRpm fapolicyd
        rlFileBackup /etc/fapolicyd/fapolicyd.conf
        rlFileBackup /etc/exports
        rlServiceStop fapolicyd
        rlServiceStart nfs-server
    rlPhaseEnd

    rlPhaseStartTest "RHEL-157947 + RHEL-170173"
        rlRun "sed -i 's/^.*ignore_mounts.*$//' /etc/fapolicyd/fapolicyd.conf"
        rlLog "add a lot of directories into ignore_mounts option"
        echo -en "\nignore_mounts = " >> /etc/fapolicyd/fapolicyd.conf
        for I in $(seq 1 $ENTRY_COUNT) ; do
            mkdir -p /mnt/source-$I /mnt/target-$I
            echo "/mnt/source-$I *(rw,no_root_squash)" >> /etc/exports
            echo -n "/mnt/target-$I," >> /etc/fapolicyd/fapolicyd.conf
        done
        rlRun "exportfs -arv"
        for I in $(seq 1 $ENTRY_COUNT) ; do
            rlRun "mount -o noexec localhost:/mnt/source-$I /mnt/target-$I"
        done
        rlRun "systemctl start fapolicyd"
        rlRun "df"
        rlRun "grep ^ignore_mounts /etc/fapolicyd/fapolicyd.conf"

        rlLog "add 1 risky entry and check"
        rlRun "cp -f /bin/ls /mnt/source-${ENTRY_COUNT}"
        rlRun -s "fapolicyd-cli --check-ignore_mounts" 1
        rlAssertGrep "total risky entries: 1" $rlRun_LOG -i
        rlAssertGrep "executable regular files: 1" $rlRun_LOG -i
        rlAssertGrep "ELF/shared objects: 1" $rlRun_LOG -i

        rlLog "remove the risky entry and check again"
        rlRun "rm -f /mnt/source-${ENTRY_COUNT}/ls"
        rlRun -s "fapolicyd-cli --check-ignore_mounts"
        rlAssertNotGrep "error|skipping|too long" $rlRun_LOG -Ei
        rlAssertEquals "summaries shown for all mount points" $(grep -ci summary $rlRun_LOG) $ENTRY_COUNT

        rlLog "check that all directories are listed"
        for I in $(seq 1 $ENTRY_COUNT) ; do
            grep -q "/mnt/target-$I:" $rlRun_LOG || rlFail "/mnt/target-$I not listed"
            rlRun "umount /mnt/target-$I"
        done
        rm -f $rlRun_LOG
        rlRun "systemctl status fapolicyd -l --no-pager"
        rlRun "systemctl stop fapolicyd"
    rlPhaseEnd

    rlPhaseStartCleanup
        for I in $(seq 1 $ENTRY_COUNT) ; do
            umount -fl /mnt/target-$I >& /dev/null
            rm -rf /mnt/source-$I /mnt/target-$I
        done
        rlFileRestore
        rlServiceRestore fapolicyd
        rlServiceRestore nfs-server
    rlPhaseEnd
rlJournalEnd

