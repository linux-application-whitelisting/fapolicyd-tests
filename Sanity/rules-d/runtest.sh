#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Author: Dalibor Pospisil <dapospis@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2021 Red Hat, Inc.
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

# EL supplemental repos for dnf builddep (Fedora: no-op). Repolist via rlRun -s (BeakerLib); grep
# for branching only — rlAssertGrep would fail the phase when repos are absent before enablement.
enable_el_builder_repos() {
  if rlIsFedora; then
    rlLogInfo "Fedora: skipping CodeReady / CRB / PowerTools (not used for build deps)"
    return 0
  fi
  rlRun -s "dnf repolist enabled" 0 "List enabled DNF repositories"
  if grep -Eiq 'rhel-CRB|codeready-builder|^[[:space:]]*crb[[:space:]]|powertools|PowerTools' "$rlRun_LOG"; then
    rlLogInfo "CodeReady Builder / CRB / PowerTools already enabled"
    return 0
  fi
  local _maj=0 _arch
  _arch=$(uname -m)
  [[ -r /etc/os-release ]] && . /etc/os-release && _maj=${VERSION_ID%%.*}
  if (( _maj >= 9 )); then
    rlRun "dnf config-manager --set-enabled crb" 0-255 "Enable crb" || true
  elif (( _maj >= 8 )); then
    rlRun "dnf config-manager --set-enabled powertools" 0-255 "Enable powertools" || true
    rlRun "dnf config-manager --set-enabled PowerTools" 0-255 "Enable PowerTools" || true
  fi
  if (( _maj >= 8 )) && command -v subscription-manager &>/dev/null && subscription-manager identity &>/dev/null; then
    rlRun "subscription-manager repos --enable codeready-builder-for-rhel-${_maj}-${_arch}-rpms" 0-255 "Enable CodeReady Builder (RHSM)" || true
  fi
}

fapolicyd_spec_inject_rules_test_sed() {
  local spec="$HOME/rpmbuild/SPECS/fapolicyd.spec"
  [[ -f $spec ]] || {
    rlLogError "missing $spec"
    return 1
  }

  # Inject a sed command right before the %build section begins
  if ! grep -q 'sed -i.*allow perm=any' "$spec"; then
    awk '
    /^%build[[:space:]]*$/ && !done {
      print "sed -i \"s/allow perm=open all : all/allow perm=any all : all/g\" rules.d/95-allow-open.rules"
      print ""
      done=1
    }
    { print }
    ' "$spec" > "${spec}.tmp" && mv -f "${spec}.tmp" "$spec" || return 1
  fi
}

# Set V_old / R_old to the newest repo build that is still older than installed.
rules_d_resolve_older_fapolicyd_nvr() {
  local inst_epoch inst_evr e v r nvr_line cand_evr best_evr best_v best_r
  inst_epoch=$(rpm -q --qf '%{EPOCHNUM}' fapolicyd) || return 1
  inst_evr="${inst_epoch}:${V}-${R}"

  rlRun -s "dnf -q repoquery --enablerepo='*' --available --latest-limit=1 --qf '%{epoch} %{version} %{release}' \"fapolicyd < ${inst_evr}\"" 0-255 "Resolve latest older fapolicyd NVR"
  nvr_line=$(awk 'NF == 3 && ($1 ~ /^[0-9]+$/ || $1 == "(none)") { print; exit }' "$rlRun_LOG")
  if [[ -n $nvr_line ]]; then
    IFS=' ' read -r e V_old R_old <<<"$nvr_line"
    [[ -z ${e:-} || $e == '(none)' ]] && e=0
    cand_evr="${e}:${V_old}-${R_old}"
    rlTestVersion "$cand_evr" "<" "$inst_evr" || {
      rlLogError "resolved candidate ${V_old}-${R_old} is not older than installed ${V}-${R}"
      return 1
    }
    rlLogInfo "Older fapolicyd for upgrade tests: ${V_old}-${R_old} (installed ${V}-${R})"
    return 0
  fi

  rlLogWarning "Filtered repoquery returned no parsable result, trying full-list fallback"
  rlRun -s "dnf -q repoquery --enablerepo='*' --available --qf '%{epoch} %{version} %{release}\\n' fapolicyd" 0 "List available fapolicyd versions"
  best_evr=""
  best_v=""
  best_r=""
  while read -r e v r; do
    [[ -n ${v:-} && -n ${r:-} ]] || continue
    [[ -z ${e:-} || $e == '(none)' ]] && e=0
    [[ $e =~ ^[0-9]+$ ]] || continue
    cand_evr="${e}:${v}-${r}"
    rlTestVersion "$cand_evr" "<" "$inst_evr" || continue
    if [[ -z $best_evr ]] || rlTestVersion "$cand_evr" ">" "$best_evr"; then
      best_evr="$cand_evr"
      best_v="$v"
      best_r="$r"
    fi
  done < <(awk 'NF == 3 && ($1 ~ /^[0-9]+$/ || $1 == "(none)")' "$rlRun_LOG" | sort -u)

  if [[ -z $best_evr ]]; then
    rlLogError "no fapolicyd in repos older than installed ${V}-${R} (EVR ${inst_evr})"
    rlLogInfo "Available versions in repo: $(tr '\n' '|' < "$rlRun_LOG")"
    return 1
  fi
  V_old="$best_v"
  R_old="$best_r"
  rlLogInfo "Older fapolicyd for upgrade tests (fallback): ${V_old}-${R_old} (installed ${V}-${R})"
}

PACKAGE="fapolicyd"
rlJournalStart && {
  rlPhaseStartSetup && {
    rlRun "rlImport --all" 0 "Import libraries" || rlDie "cannot continue"
    #tcfRun "rlCheckMakefileRequires" || rlDie "cannot continue"
    enable_el_builder_repos
    IFS=' ' read -r SRC N V R A < <(rpm -q --qf '%{sourcerpm} %{name} %{version} %{release} %{arch}\n' fapolicyd)
    rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
    CleanupRegister "rlRun 'rm -r $TmpDir' 0 'Removing tmp directory'"
    CleanupRegister 'rlRun "popd"'
    rlRun "pushd $TmpDir"
    CleanupRegister 'rlRun "rlFileRestore"'
    rlRun "rlFileBackup --clean /root/rpmbuild"
    CleanupRegister 'rlRun "fapCleanup"'
    rlRun "fapSetup"
    CleanupRegister --mark "rlRun 'RpmSnapshotRevert'; rlRun 'RpmSnapshotDiscard'"
    rlRun "RpmSnapshotCreate"
    if ! rlFetchSrcForInstalled fapolicyd; then
      rlLogWarning "Installed SRPM not available, trying latest available source package"
      rlRun -s "dnf -q repoquery --enablerepo='*-source' --arch=src --latest-limit=1 --location fapolicyd" 0 "Fallback: locate latest fapolicyd SRPM URL"
      SRPM_URL=$(awk 'NF {print; exit}' "$rlRun_LOG")
      [[ -n ${SRPM_URL:-} ]] || rlDie "Fallback did not return any SRPM URL for fapolicyd"
      rlRun "curl -fL -O \"$SRPM_URL\"" 0 "Fallback: download latest fapolicyd SRPM"
    fi
    shopt -s nullglob
    src_rpms=(./fapolicyd*.src.rpm)
    shopt -u nullglob
    (( ${#src_rpms[@]} > 0 )) || rlDie "No fapolicyd SRPM downloaded"
    SRPM="${src_rpms[0]}"
    rlRun "dnf builddep -y --enablerepo='*' \"$SRPM\"" 0 "Build deps from SRPM (all repos)"
    rlRun "rpm -ivh \"$SRPM\""
    R2=".$(echo "$R" | cut -d . -f 2-)"
    rlRun -s "rpmbuild -bb -D 'dist ${R2}_98' ~/rpmbuild/SPECS/fapolicyd.spec" 0 "build newer package"
    rlRun_LOG1=$rlRun_LOG
    rlRun "fapolicyd_spec_inject_rules_test_sed" 0 "Inject rules test sed into fapolicyd.spec"
    rlRun -s "rpmbuild -bb -D 'dist ${R2}_99' ~/rpmbuild/SPECS/fapolicyd.spec" 0 "build newer package with updated default rules"
    rlRun "mkdir rpms"
    pushd rpms
    rlRun "cp $(grep 'Wrote:' $rlRun_LOG | cut -d ' ' -f 2 | tr '\n' ' ') $(grep 'Wrote:' $rlRun_LOG1 | cut -d ' ' -f 2 | tr '\n' ' ') ./"
    packages=()
    rules_d_resolve_older_fapolicyd_nvr || rlDie "cannot resolve older fapolicyd NVR from repos"
    if [[ -n $(dnf repoquery --enablerepo='*' --available -q "fapolicyd-dnf-plugin = ${V_old}-${R_old}" 2>/dev/null) ]]; then
      packages+=(fapolicyd-dnf-plugin-${V_old}-${R_old}.noarch)
    fi
    packages+=(
      fapolicyd-${V_old}-${R_old}.$A
      #fapolicyd-debuginfo-${V_old}-${R_old}.$A
      #fapolicyd-debugsource-${V_old}-${R_old}.$A
      fapolicyd-selinux-${V_old}-${R_old}.noarch
    )

    for package in "${packages[@]}"; do
      rlRpmDownload $package
    done
    rlRun "createrepo --database ./"
    rlRun -s "ls -la"
    _98=$( cat $rlRun_LOG | grep -o 'fapolicyd-[0-9].*_98.*\.rpm' | sed -r 's/\.rpm//' )
    _99=$( cat $rlRun_LOG | grep -o 'fapolicyd-[0-9].*_99.*\.rpm' | sed -r 's/\.rpm//' )
    popd
    repofile="/etc/yum.repos.d/rules-d-local.repo"
    rlRun "printf '%s\n' '[rules-d-local]' 'name=rules-d-local' 'baseurl=file://$PWD/rpms' 'enabled=1' 'gpgcheck=0' 'skip_if_unavailable=1' 'sslverify=0' > $repofile"
    CleanupRegister "rlRun 'rm -f $repofile'"
    rlRun "dnf clean all"
    rlRun "repoquery -a | grep fapolicyd" 0-255
  rlPhaseEnd; }

  tcfTry "Tests" --no-assert && {
    rlPhaseStartTest "clean install" && {
      # fapolicyd.rules should not exit
      # rules.d should be populated
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "dnf remove fapolicyd -y"
      rlRun "dnf install fapolicyd-$V-$R -y --allowerasing"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlAssertNotExists /etc/fapolicyd/fapolicyd.rules
      rlAssertGreater "rules are deployed into /etc/fapolicyd/rules.d" $(ls -1 /etc/fapolicyd/rules.d | wc -w) 0
    rlPhaseEnd; }

    rlPhaseStartTest "rules order" && {
      # rules.d alphanumeric sorting generates correct compiled.rules order
      CleanupRegister --mark 'rlRun "rm -f /etc/fapolicyd/rules.d/5{1,2,3}-custom.rules"'
      rlRun "echo 'allow perm=open exe=/path/to/binary1 : all' > /etc/fapolicyd/rules.d/52-custom.rules"
      rlRun "echo 'allow perm=open exe=/path/to/binary2 : all' > /etc/fapolicyd/rules.d/51-custom.rules"
      rlRun "echo 'allow perm=open exe=/path/to/binary3 : all' > /etc/fapolicyd/rules.d/53-custom.rules"
      rlRun "fagenrules"
      rlRun "cat /etc/fapolicyd/compiled.rules"
      rlRun "cat /etc/fapolicyd/compiled.rules | tr '\n' ' ' | grep -q 'binary2.*binary1.*binary3'" 0 "check correct order"
      CleanupDo --mark
    rlPhaseEnd; }

    rlPhaseStartTest "concurent rules present" && {
      # fapolicyd service does not start if both fapolicyd.rules
      # and populated rules.d exist
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "dnf reinstall fapolicyd-$V-$R -y"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlAssertNotExists /etc/fapolicyd/fapolicyd.rules
      rlAssertGreater "rules are deployed into /etc/fapolicyd/rules.d" $(ls -1 /etc/fapolicyd/rules.d | wc -w) 0
      cat > /etc/fapolicyd/fapolicyd.rules <<EOF
%languages=application/x-bytecode.ocaml,application/x-bytecode.python,application/java-archive,text/x-java,application/x-java-applet,application/javascript,text/javascript,text/x-awk,text/x-gawk,text/x-lisp,application/x-elc,text/x-lua,text/x-m4,text/x-nftables,text/x-perl,text/x-php,text/x-python,text/x-R,text/x-ru
deny_audit perm=any pattern=ld_so : all
allow perm=any uid=0 : dir=/var/tmp/
allow perm=any uid=0 trust=1 : all
allow perm=open exe=/usr/bin/rpm : all
allow perm=open exe=/usr/bin/python3.10 comm=dnf : all
deny_audit perm=any all : ftype=application/x-bad-elf
allow perm=open all : ftype=application/x-sharedlib trust=1
deny_audit perm=open all : ftype=application/x-sharedlib
allow perm=any exe=/my/special/rule : trust=1
allow perm=execute all : trust=1
allow perm=open all : ftype=%languages trust=1
deny_audit perm=any all : ftype=%languages
allow perm=any all : ftype=text/x-shellscript
deny_audit perm=execute all : all
allow perm=open all : all
EOF
      rlRun -s "fapStart" 1-255
      rlAssertGrep 'Error - both old and new rules exist' $rlRun_LOG
      rm -f /etc/fapolicyd/fapolicyd.rules
    rlPhaseEnd; }

    rlPhaseStartTest "upgrade from old version - default rules" && {
      # fapolicyd.rules should be replace with populated rules.d
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "dnf install fapolicyd-$V_old-$R_old -y --allowerasing"
      rlRun "dnf reinstall fapolicyd-$V_old-$R_old -y --allowerasing"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "dnf install fapolicyd-$V-$R -y --allowerasing"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlAssertNotExists /etc/fapolicyd/fapolicyd.rules
      rlAssertGreater "rules are deployed into /etc/fapolicyd/rules.d" $(ls -1 /etc/fapolicyd/rules.d | wc -w) 0
    rlPhaseEnd; }

    rlPhaseStartTest "upgrade from old version - changed rules" && {
      # fapolicyd.rules should stay untouched
      # rules.d should not be populated
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "dnf install fapolicyd-$V_old-$R_old -y --allowerasing"
      rlRun "dnf reinstall fapolicyd-$V_old-$R_old -y --allowerasing"
      echo "allow perm=any all : all" >> /etc/fapolicyd/fapolicyd.rules
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "dnf install fapolicyd-$V-$R -y --allowerasing"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlAssertExists /etc/fapolicyd/fapolicyd.rules
      rlAssertEquals "rules are deployed into /etc/fapolicyd/rules.d" $(ls -1 /etc/fapolicyd/rules.d | wc -w) 0
    rlPhaseEnd; }

    rlPhaseStartTest "upgrade to new version - still with fapolicyd.rules" && {
      # fapolicyd.rules should stay untouched
      # rules.d should not be populated
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "dnf install fapolicyd-$V-$R -y --allowerasing"
      rlRun "dnf reinstall fapolicyd-$V-$R -y --allowerasing"
      rlRun "rm -f /etc/fapolicyd/rules.d/*"
      cat > /etc/fapolicyd/fapolicyd.rules <<EOF
%languages=application/x-bytecode.ocaml,application/x-bytecode.python,application/java-archive,text/x-java,application/x-java-applet,application/javascript,text/javascript,text/x-awk,text/x-gawk,text/x-lisp,application/x-elc,text/x-lua,text/x-m4,text/x-nftables,text/x-perl,text/x-php,text/x-python,text/x-R,text/x-ru
deny_audit perm=any pattern=ld_so : all
allow perm=any uid=0 : dir=/var/tmp/
allow perm=any uid=0 trust=1 : all
allow perm=open exe=/usr/bin/rpm : all
allow perm=open exe=/usr/bin/python3.10 comm=dnf : all
deny_audit perm=any all : ftype=application/x-bad-elf
allow perm=open all : ftype=application/x-sharedlib trust=1
deny_audit perm=open all : ftype=application/x-sharedlib
allow perm=any exe=/my/special/rule : trust=1
allow perm=execute all : trust=1
allow perm=open all : ftype=%languages trust=1
deny_audit perm=any all : ftype=%languages
allow perm=any all : ftype=text/x-shellscript
deny_audit perm=execute all : all
allow perm=open all : all
EOF
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlAssertExists /etc/fapolicyd/fapolicyd.rules
      rlAssertEquals "rules are deployed into /etc/fapolicyd/rules.d" $(ls -1 /etc/fapolicyd/rules.d | wc -w) 0
      rlRun "dnf install ${_98} -y --allowerasing"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlAssertExists /etc/fapolicyd/fapolicyd.rules
      rlAssertEquals "rules are deployed into /etc/fapolicyd/rules.d" $(ls -1 /etc/fapolicyd/rules.d | wc -w) 0
    rlPhaseEnd; }

    rlPhaseStartTest "upgrade to new version - changed default rules" && {
      # fapolicyd.rules should not exit
      # rules.d should stay untouched
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "dnf install fapolicyd-$V-$R -y --allowerasing"
      rlRun "dnf reinstall fapolicyd-$V-$R -y --allowerasing"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      echo "allow perm=any all : all" >> /etc/fapolicyd/rules.d/95-allow-open.rules
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertGrep 'allow perm=open' $rlRun_LOG
      rlAssertGrep 'allow perm=any' $rlRun_LOG
      rlRun "dnf install ${_98} -y --allowerasing"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertGrep 'allow perm=open' $rlRun_LOG
      rlAssertGrep 'allow perm=any' $rlRun_LOG
    rlPhaseEnd; }

    rlPhaseStartTest "upgrade to new version - updated default rules" && {
      # fapolicyd.rules should not exit
      # rules.d should be updated
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "dnf install fapolicyd-$V-$R -y --allowerasing"
      rlRun "dnf reinstall fapolicyd-$V-$R -y --allowerasing"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertGrep 'allow perm=open' $rlRun_LOG
      rlRun "dnf install ${_99} -y --allowerasing"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertNotGrep 'allow perm=open' $rlRun_LOG
      rlAssertGrep 'allow perm=any' $rlRun_LOG
    rlPhaseEnd; }

    rlPhaseStartTest "upgrade to new version - custom rules file added" && {
      # fapolicyd.rules should not exit
      # rules.d should stay untouched
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "dnf install fapolicyd-$V-$R -y --allowerasing"
      rlRun "dnf reinstall fapolicyd-$V-$R -y --allowerasing"
      rlRun "echo 'allow perm=open exe=/path/to/binary : all' > /etc/fapolicyd/rules.d/51-custom.rules"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertGrep 'allow perm=open' $rlRun_LOG
      rlAssertGrep 'allow perm=open exe=/path/to/binary : all' /etc/fapolicyd/rules.d/51-custom.rules
      rlRun "dnf install ${_98} -y --allowerasing"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertGrep 'allow perm=open' $rlRun_LOG
      rlAssertGrep 'allow perm=open exe=/path/to/binary : all' /etc/fapolicyd/rules.d/51-custom.rules
    rlPhaseEnd; }

    rlPhaseStartTest "upgrade to new version - custom rules file added + updated default rules" && {
      # fapolicyd.rules should not exit
      # rules.d should be populated
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "dnf install fapolicyd-$V-$R -y --allowerasing"
      rlRun "dnf reinstall fapolicyd-$V-$R -y --allowerasing"
      rlRun "echo 'allow perm=open exe=/path/to/binary : all' > /etc/fapolicyd/rules.d/51-custom.rules"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertGrep 'allow perm=open' $rlRun_LOG
      rlAssertGrep 'allow perm=open exe=/path/to/binary : all' /etc/fapolicyd/rules.d/51-custom.rules
      rlRun "dnf install ${_99} -y --allowerasing"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertGrep 'allow perm=open' $rlRun_LOG
      rlAssertNotGrep 'allow perm=any' $rlRun_LOG
      rlAssertGrep 'allow perm=open exe=/path/to/binary : all' /etc/fapolicyd/rules.d/51-custom.rules
    rlPhaseEnd; }

    rlPhaseStartTest "uninstall - default rules" && {
      # fapolicyd.rules should be removed
      # rules.d should be removed
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "dnf install fapolicyd-$V-$R -y --allowerasing"
      rlRun "dnf reinstall fapolicyd-$V-$R -y --allowerasing"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertGrep 'allow perm=open' $rlRun_LOG
      rlRun "dnf remove fapolicyd -y"
      rlRun "ls -la /etc/fapolicyd/" 0-255
      rlRun "ls -la /etc/fapolicyd/rules.d/" 0-255
      [[ -d /etc/fapolicyd/rules.d/ ]] && rlAssertEquals "rules are deployed into /etc/fapolicyd/rules.d" $(ls -1 /etc/fapolicyd/rules.d | wc -w) 0
    rlPhaseEnd; }

    rlPhaseStartTest "uninstall - custom rules" && {
      # fapolicyd.rules should not exit
      # rules.d should stay untouched
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "dnf install fapolicyd-$V-$R -y --allowerasing"
      rlRun "dnf reinstall fapolicyd-$V-$R -y --allowerasing"
      rlRun "echo 'allow perm=open exe=/path/to/binary : all' > /etc/fapolicyd/rules.d/51-custom.rules"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertGrep 'allow perm=open' $rlRun_LOG
      rlAssertGrep 'allow perm=open exe=/path/to/binary : all' /etc/fapolicyd/rules.d/51-custom.rules
      rlRun "dnf remove fapolicyd -y"
      rlRun "ls -la /etc/fapolicyd/" 0-255
      rlRun "ls -la /etc/fapolicyd/rules.d/" 0-255
      rlAssertGreater "rules are deployed into /etc/fapolicyd/rules.d" $(ls -1 /etc/fapolicyd/rules.d | wc -w) 0
    rlPhaseEnd; }

    rlPhaseStartTest "uninstall - changed default rules" && {
      # fapolicyd.rules should not exit
      # rules.d should stay untouched
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "dnf install fapolicyd-$V-$R -y --allowerasing"
      rlRun "dnf reinstall fapolicyd-$V-$R -y --allowerasing"
      rlRun "sed -ir 's/open/any/' /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertGrep 'allow perm=any' $rlRun_LOG
      rlRun "dnf remove fapolicyd -y"
      rlRun "ls -la /etc/fapolicyd/" 0-255
      rlRun "ls -la /etc/fapolicyd/rules.d/" 0-255
      rlAssertGreater "rules are deployed into /etc/fapolicyd/rules.d" $(ls -1 /etc/fapolicyd/rules.d | wc -w) 0
    rlPhaseEnd; }

    if rlIsRHELLike '>=9.7' ; then
      rlPhaseStartTest "RHEL-30020 - custom rule pattern=normal" && {
        rlRun "dnf install fapolicyd -y --allowerasing"
        rlRun "fapStart"
        TIMESTAMP=$(date +"%F %T")
        rlRun "echo 'deny_audit perm=any pattern=normal : all' > /etc/fapolicyd/rules.d/28-custom.rules"
        CleanupRegister --mark "rlRun 'rm -f /etc/fapolicyd/rules.d/28-custom.rules'"
        rlRun -s "systemctl restart fapolicyd"
        rlRun -s "journalctl --since '${TIMESTAMP}' -u fapolicyd" 0 "Listing system log for fapolicyd"
        rlAssertNotGrep "Unknown pattern value normal" $rlRun_LOG
        CleanupDo --mark
        rlRun "fapStop" 0 "Stopping fapolicyd service"
      rlPhaseEnd; }
    fi

    :
  tcfFin; }

  rlPhaseStartCleanup && {
    CleanupDo
    tcfCheckFinal
  rlPhaseEnd; }
  rlJournalPrintText
rlJournalEnd; }