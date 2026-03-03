#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd/Regression/invalid-checksum-when-probed
#   Description: test if fapolicyd computes valid checksum of probed file
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
        rlRun "rpm -qa | grep kernel | sort"
        if ! rpm -q kernel-devel-`uname -r` ; then
            rlRun "yum -y install kernel-devel-`uname -r`"
        fi
        if ! rpm -qa | grep -q bash-debug ; then
            rlRun "debuginfo-install -y bash"
        fi
        rlServiceStop fapolicyd
    rlPhaseEnd

    rlPhaseStartTest "RHEL-142948 + RHEL-144373"
        rlLog "starting the systemtap probe"
        stap -v -e 'probe process("/usr/bin/bash").function("readline").return { printf("hooked\n") }' >& output.txt &
        PROBE_PID=$!

        rlLog "waiting for the systemtap probe to activate (max. 60 seconds)"
        for ((i=0; i < 60; i++)) ; do
            echo -n .
            sleep 1s
            if grep -q 'starting run' output.txt ; then
                break
            fi
        done
        echo
        if (( i >= 60 )); then
            rlFail "the systemtap probe failed to start"
        fi
        rlRun "cat output.txt"

        rlServiceStart fapolicyd
        sleep 1
        rlRun -s "fapolicyd-cli --check-trustdb"
        rlAssertNotGrep 'bash miscompares' $rlRun_LOG
        rm -f $rlRun_LOG

        if pgrep stap >& /dev/null ; then
            rlLog "terminating the systemtap probe"
            rlRun "kill ${PROBE_PID}" 0,1
            sleep 1
            rlRun "kill -9 ${PROBE_PID}" 0,1
        fi

        rlServiceStop fapolicyd
    rlPhaseEnd

    rlPhaseStartCleanup
        rm -f output.txt
        rlServiceRestore fapolicyd
    rlPhaseEnd
rlJournalEnd

