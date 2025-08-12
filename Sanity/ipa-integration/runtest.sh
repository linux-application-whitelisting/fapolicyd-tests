#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /CoreOS/fapolicyd/Sanity/ipa-integration
#   Description: ipa-integration
#   Author: Dalibor Pospisil <dapospis@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2020 Red Hat, Inc.
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
. /usr/bin/rhts-environment.sh || :
. /usr/share/beakerlib/beakerlib.sh || exit 1

PACKAGE="fapolicyd"

rlJournalStart && {
  rlPhaseStartSetup && {
    rlRun "rlImport --all" 0 "Import libraries" || rlDie "cannot continue"
    rlRun "rlImport ./common" 0 "Import common fapolicyd library" || rlDie "cannot continue"
    if rlIsRHEL '8'; then
      CleanupRegister 'rlRun "RpmSnapshotRevert"; rlRun "RpmSnapshotDiscard"'
      CleanupRegister 'rlRun "dnf -y module reset idm"'
      rlRun "dnf -y module reset idm"
      rlRun "RpmSnapshotCreate"
      rlRun "dnf -y module remove idm:client"
      rlRun "dnf -y module install idm:DL1/dns"
    fi
    tcfRun "rlCheckMakefileRequires" || rlDie "cannot continue"
    rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
    CleanupRegister "rlRun 'rm -r $TmpDir' 0 'Removing tmp directory'"
    CleanupRegister 'rlRun "popd"'
    rlRun "pushd $TmpDir"
    rlFileBackup "/etc/hosts"
  rlPhaseEnd; }

  tcfTry "Tests" --no-assert && {
    rlPhaseStartTest "check trustdb" && {
      rlRun "fapServiceStart"
      rlRun "fapServiceStop"
      rlRun -s "fapolicyd-cli -D | grep /usr/share | grep '\.jar'"
      #rlAssertGrep "" $rlRun_LOG
      rm -f $rlRun_LOG
    rlPhaseEnd; }

    rlPhaseStartTest "check ipa-server-install" && {
      CleanupRegister --mark 'rlRun "fapCleanup"'
      if rlIsRHELLike '>=10'; then
      #https://access.redhat.com/solutions/5567781
        rlRun "cat <<EOF > /etc/fapolicyd/rules.d/33-tomcat.rules
allow perm=open dir=/usr/lib/jvm/ : path=/usr/share/pki/server/webapps/ROOT/index.jsp
allow perm=open dir=/usr/lib/jvm/ : all ftype=application/javascript trust=0
EOF"
      #https://access.redhat.com/solutions/3400091
        rlRun "umask 0022"
      fi
      rlRun "fapSetup"
      CleanupRegister 'rlRun "fapStop"'
      rlRun "fapStart" > /dev/null
      fapServiceOut -b -f
      CleanupRegister "kill $!"

      IP_ADDRESS=`hostname -I | awk '{print $1}'`
      DOMAIN_NAME="domain.com"
      IPA_MACHINE_HOSTNAME="test`date +%s`.${DOMAIN_NAME}"
      REALM_NAME="TESTREALM.COM"
      DM_PASSWORD="Secret123"
      MASTER_PASSWORD="Secret123"
      ADMIN_PASSWORD="Secret123"

      # Hardcoded temporary hostname as IPA server hostname must be shorter than 64 characters and contain valid domain name
      rlRun "echo \"${IP_ADDRESS} ${IPA_MACHINE_HOSTNAME}\" | sudo tee -a /etc/hosts"

      CleanupRegister 'rlRun "ipa-server-install --uninstall --unattended"'
      if rlTestVersion "$(rpm -q ipa-server)" '<' "ipa-server-4.5"; then
        rlRun "ipa-server-install --hostname=$IPA_MACHINE_HOSTNAME -r $REALM_NAME -n $DOMAIN_NAME -p $DM_PASSWORD -P $MASTER_PASSWORD -a $ADMIN_PASSWORD --unattended --ip-address $IP_ADDRESS" 0
      else
        rlRun "ipa-server-install --hostname=$IPA_MACHINE_HOSTNAME -r $REALM_NAME -n $DOMAIN_NAME -p $DM_PASSWORD -a $ADMIN_PASSWORD --unattended --ip-address $IP_ADDRESS" 0
      fi
      CleanupDo --mark
    rlPhaseEnd; }
  tcfFin; }

  rlPhaseStartCleanup && {
    CleanupDo
    tcfCheckFinal
    rlFileRestore
  rlPhaseEnd; }
  rlJournalPrintText
rlJournalEnd; }
