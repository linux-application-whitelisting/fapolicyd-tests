#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /fapolicyd/Sanity/check-rules-option
#   Description: test if the --check-rules option works as expected
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

TESTING_RULES="./testing-${RANDOM}.rules"

rlJournalStart
    rlPhaseStartSetup
        rlAssertRpm fapolicyd
        rlServiceStop fapolicyd
    rlPhaseEnd

    rlPhaseStartTest "RHEL-13011 + RHEL-169985"
        rlRun "man fapolicyd-cli | col -b | grep -A 2 -- --check-rules"
        rlRun "fapolicyd-cli --help | grep -- --check-rules"

        # without a rules files
        rlRun -s "fapolicyd-cli --check-rules" 2
        rlAssertGrep "requires.*argument" $rlRun_LOG -i
        rlRun "rm -f $rlRun_LOG"

        # non-existent rules file
        rlRun -s "fapolicyd-cli --check-rules ./non-existent.rules" 7
        rlAssertGrep "cannot open" $rlRun_LOG -i
        rlRun "rm -f $rlRun_LOG"

        # empty rules file
        rlRun "echo > ${TESTING_RULES}"
        rlRun -s "fapolicyd-cli --check-rules ${TESTING_RULES}" 5
        rlAssertGrep "no rules found" $rlRun_LOG -i
        rlRun "rm -f $rlRun_LOG"

        # incomplete rules file
        rlRun "echo 'allow perm=any exe=/usr/lib/systemd/systemd' > ${TESTING_RULES}"
        rlRun -s "fapolicyd-cli --check-rules ${TESTING_RULES}" 5
        rlAssertGrep "validation failed|missing|unknown" $rlRun_LOG -Ei
        rlRun "rm -f $rlRun_LOG"

        # invalid rules file
        rlRun "echo 'allow perm=all exe=/usr/lib/systemd/systemd : dir=/usr/share/foreman-proxy/bin/smart-proxy ftype=text/x-ruby trust=0' > ${TESTING_RULES}"
        rlRun -s "fapolicyd-cli --check-rules ${TESTING_RULES}" 5
        rlAssertGrep "validation failed|unknown" $rlRun_LOG -Ei
        rlRun "rm -f $rlRun_LOG"

        # valid rules file
        rlRun "echo 'allow perm=any exe=/usr/lib/systemd/systemd : dir=/usr/share/foreman-proxy/bin/smart-proxy ftype=text/x-ruby trust=0' > ${TESTING_RULES}"
        rlRun -s "fapolicyd-cli --check-rules ${TESTING_RULES}" 0
        rlAssertGrep "rules file is valid" $rlRun_LOG -i
        rlRun "rm -f $rlRun_LOG"

        # negative case: run fagenrules instead of fapolicyd-cli
        rlRun "echo 'allow perm=all exe=/usr/lib/systemd/systemd : dir=/usr/share/foreman-proxy/bin/smart-proxy ftype=text/x-ruby trust=0' > /etc/fapolicyd/rules.d/${TESTING_RULES}"
        rlRun -s "fagenrules --load" 5
        rlAssertGrep "validation failed|unknown" $rlRun_LOG -Ei
        rlRun "rm -f $rlRun_LOG"

        # positive case: run fagenrules instead of fapolicyd-cli
        rlRun "rm -f /etc/fapolicyd/rules.d/${TESTING_RULES}"
        rlRun -s "fagenrules --load"
        rlAssertGrep "rules file is valid" $rlRun_LOG -i
        rlRun "rm -f $rlRun_LOG"
    rlPhaseEnd

    rlPhaseStartCleanup
        rlRun "rm -f ${TESTING_RULES}"
        rlServiceRestore
    rlPhaseEnd
rlJournalEnd

