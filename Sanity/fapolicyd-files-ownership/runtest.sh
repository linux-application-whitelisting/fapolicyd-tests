#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Author: Natália Bubáková <nbubakov@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2025 Red Hat, Inc.
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

TESTDIR=`pwd`

function checkFile() {
    MUSTEXIST=false
    if [ "$1" == "-e" ]; then
        MUSTEXIST=true
        shift
    fi
    FILEPATH=$1
    OWNER=$2
    GROUP=$3
    if "$MUSTEXIST" || [ -e "$FILEPATH" ]; then
        ls -ld $FILEPATH
        rlRun "ls -ld $FILEPATH | grep -qE '$OWNER[ ]*$GROUP'" 0 "Check ownership of $FILEPATH ($OWNER:$GROUP)"
    fi
}

rlJournalStart

    rlPhaseStartTest
        rlServiceStart fapolicyd
        rlRun "rlServiceStatus fapolicyd" 0 "Confirm that fapolicyd is running"

        rlRun -s "id fapolicyd"
        PATTERN="[0-9]+\(fapolicyd\)"
        rlRun "grep -E 'uid=$PATTERN.*gid=$PATTERN.*groups=$PATTERN' $rlRun_LOG" 0 "Verify user account"

        # check /etc files
        checkFile -e /etc/fapolicyd root fapolicyd
        checkFile -e /etc/fapolicyd/fapolicyd.conf root fapolicyd
        checkFile -e /etc/fapolicyd/fapolicyd.trust root fapolicyd
        checkFile -e /etc/fapolicyd/rules.d/ root fapolicyd
        checkFile -e /etc/fapolicyd/trust.d root fapolicyd

        # check /var files
        checkFile -e /var/lib/fapolicyd root fapolicyd
        checkFile -e /var/lib/fapolicyd/data.mdb fapolicyd fapolicyd
        checkFile -e /var/lib/fapolicyd/lock.mdb fapolicyd fapolicyd
        checkFile /var/log/fapolicyd-access.log fapolicyd fapolicyd

        # check /run files
        ( ! rlIsRHEL "<9.7" && ! rlIsRHEL "10.0" && ! rlIsFedora ) && checkFile -e /run/fapolicyd root fapolicyd
        checkFile -e /run/fapolicyd/fapolicyd.fifo root fapolicyd

        # check /usr files
        checkFile -e /usr/share/fapolicyd root fapolicyd
        checkFile -e /usr/lib/systemd/system/fapolicyd.service root root
        checkFile -e /usr/sbin/fagenrules root root
        checkFile -e /usr/sbin/fapolicyd root root

        rlServiceStop fapolicyd
    rlPhaseEnd

rlJournalPrintText
rlJournalEnd