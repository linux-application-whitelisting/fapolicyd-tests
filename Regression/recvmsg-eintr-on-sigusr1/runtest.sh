#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /Regression/recvmsg-eintr-on-sigusr1
#   Description: SIGUSR1 during startup causes recvmsg EINTR crash
#   Author: Renaud Métrich <rmetrich@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2026 Red Hat, Inc.
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

. /usr/share/beakerlib/beakerlib.sh || exit 1

PACKAGE="fapolicyd"

rlJournalStart && {
  rlPhaseStartSetup && {
    rlRun "rlImport --all" 0 "Import libraries" || rlDie "cannot continue"
    rlRun "rlCheckDependencies" || rlDie "cannot continue"
    rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
    CleanupRegister "rlRun 'rm -r $TmpDir' 0 'Removing tmp directory'"
    CleanupRegister 'rlRun "popd"'
    rlRun "pushd $TmpDir"
    CleanupRegister 'rlRun "fapCleanup"'
    rlRun "fapSetup"
  rlPhaseEnd; }

  rlPhaseStartTest "SIGUSR1 during startup should not crash daemon" && {
    # Strategy: freeze the rpm-loader child with SIGSTOP so the daemon
    # stays blocked in recvmsg, then send SIGUSR1 to trigger EINTR,
    # then SIGCONT to let the loader finish. This makes the test
    # deterministic regardless of RPM database size.

    rlRun "rlServiceStop fapolicyd" 0-255
    rlRun "rm -f /run/fapolicyd/fapolicyd.fifo /run/fapolicyd.pid"
    trap '' USR1
    /usr/sbin/fapolicyd --debug > $TmpDir/fapolicyd.log 2>&1 &
    DPID=$!
    rlLog "daemon started with PID=$DPID"

    # Wait for the loader child to appear and immediately freeze it
    timeout=3000
    while ! pkill -STOP -f fapolicyd-rpm-loader 2>/dev/null; do
      sleep 0.01
      let timeout--
      [ $timeout -le 0 ] && break
    done

    if [ $timeout -gt 0 ]; then
      rlLog "loader frozen with SIGSTOP"

      # Daemon is now blocked in recvmsg. Send SIGUSR1 to trigger EINTR.
      rlLog "sending SIGUSR1 to daemon PID=$DPID"
      kill -USR1 $DPID

      sleep 1

      # Unfreeze the loader so it can send the memfd
      rlLog "unfreezing loader with SIGCONT"
      pkill -CONT -f fapolicyd-rpm-loader 2>/dev/null

      sleep 3

      if [ -d /proc/$DPID ]; then
        rlPass "daemon survived SIGUSR1 during recvmsg"
      else
        wait $DPID 2>/dev/null
        rlFail "daemon crashed on SIGUSR1 during recvmsg"
      fi
      rlAssertNotGrep 'recvmsg failed' $TmpDir/fapolicyd.log
      rlAssertNotGrep 'missing fd' $TmpDir/fapolicyd.log
    else
      rlFail "fapolicyd-rpm-loader child never appeared (timeout)"
      kill $DPID 2>/dev/null
      wait $DPID 2>/dev/null
    fi

    # Cleanup: ensure the manually-started daemon is stopped
    # (fapCleanup's rlServiceStop won't find it)
    if [ -d /proc/$DPID ]; then
      kill $DPID 2>/dev/null
      sleep 2
      # Force kill if still running (debug mode can hang on shutdown)
      [ -d /proc/$DPID ] && kill -9 $DPID 2>/dev/null
    fi
    wait $DPID 2>/dev/null
  rlPhaseEnd; }

  rlPhaseStartCleanup && {
    CleanupDo
  rlPhaseEnd; }
  rlJournalPrintText
rlJournalEnd; }
