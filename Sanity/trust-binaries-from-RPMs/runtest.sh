#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd/Sanity/trust-binaries-from-RPMs
#   Description: test if binaries from RPMs are trusted by default
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
        rlAssertExists /etc/fapolicyd/fapolicyd-filter.conf
        rlAssertRpm environment-modules
        rlAssertExists /usr/share/Modules/bin/mkroot
        rlServiceStart fapolicyd
        rlRun "fapolicyd-cli --check-status"
    rlPhaseEnd

    rlPhaseStartTest "RHEL-131723 + RHEL-141670"
        rlRun "grep bin /etc/fapolicyd/fapolicyd-filter.conf"
        rlRun -s "fapolicyd-cli --test-filter /usr/share/Modules/bin/mkroot"
        rlAssertGrep "decision include" $rlRun_LOG -i
        rm -f $rlRun_LOG
        rlRun -s "fapolicyd-cli -D | grep -E '/usr/share/.*/bin/'"
        rlAssertGrep "/usr/share/Modules/bin/mkroot" $rlRun_LOG
        rm -f $rlRun_LOG
    rlPhaseEnd

    rlPhaseStartCleanup
        rlServiceStop fapolicyd
    rlPhaseEnd
rlJournalEnd

