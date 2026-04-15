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

# RHTS/Beaker only; omit noisy "No such file" on Fedora/tmt (no rhts-environment package).
[[ -f /usr/bin/rhts-environment.sh ]] && . /usr/bin/rhts-environment.sh
. /usr/share/beakerlib/beakerlib.sh || exit 1

PACKAGE="fapolicyd"

fap_repoquery() {
  if command -v dnf &>/dev/null; then
    dnf repoquery "$@"
  else
    yum repoquery "$@"
  fi
}

# dnf5 vs dnf4 for dnf download --srpm vs --source (do not grep dnf download --help for --srpm).
# Improved for CS10: dnf5 binary, symlink target, or version line (DNF 5 / libdnf5).
fap_rules_d_dnf_download_is_dnf5() {
  command -v dnf5 &>/dev/null && return 0
  local p
  p=$(type -P dnf 2>/dev/null) || return 1
  p=$(readlink -f "$p" 2>/dev/null) || p=$(type -P dnf 2>/dev/null)
  [[ "$(basename "$p")" == *dnf5* ]] && return 0
  command -v dnf &>/dev/null || return 1
  dnf --version 2>&1 | grep -qiE 'dnf5|version[[:space:]]*:?[[:space:]]*5\.|libdnf5'
}

# Fedora & CentOS Stream 10+ fapolicyd RPMs often keep default rules.d across uninstall and may repopulate
# rules.d on upgrade even when fapolicyd.rules exists — unlike RHEL/Alma/Rocky %%preun clearing %%ghost defaults.
# CentOS Stream 9 (and EL8 Stream) follow RHEL-like %%ghost/preun behavior in practice; do not treat as Fedora.
fap_rules_d_rules_packaging_like_fedora() {
  rlIsFedora && return 0
  local is_stream=0 maj
  if rpm -q centos-stream-release &>/dev/null; then
    is_stream=1
  elif [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    [[ "${ID:-}" == centos && "${NAME:-}" == *Stream* ]] && is_stream=1
  fi
  [[ "$is_stream" -eq 1 ]] || return 1
  maj=$(rpm -E '%{?rhel}' 2>/dev/null) || true
  if [[ -z "$maj" || "$maj" == "%{?rhel}" ]] && [[ -r /etc/os-release ]]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    maj="${VERSION_ID%%.*}"
  fi
  [[ "${maj:-0}" =~ ^[0-9]+$ ]] && [[ "$maj" -ge 10 ]] && return 0
  return 1
}

# CRB / CodeReady / powertools names differ by product (RHEL vs CentOS Stream vs EL clones).
# Best-effort enable — same intent as https://github.com/linux-application-whitelisting/fapolicyd-tests/pull/17
# but without --enablerepo '*' on builddep (over-broad; see PR review).
fap_rules_d_enable_repo() {
  local id=$1
  if command -v dnf &>/dev/null; then
    # dnf5 rejects "config-manager set-enabled ID" (missing --); use --set-enabled only.
    rlRun "dnf config-manager --set-enabled $id" 0-255 "dnf config-manager --set-enabled $id" || true
  elif command -v yum-config-manager &>/dev/null; then
    rlRun "yum-config-manager --enable $id" 0-255 "yum-config-manager --enable $id" || true
  fi
}

fap_rules_d_enable_build_repos() {
  rlLog "Enable CRB / CodeReady Builder / powertools (best effort for rpm build dependencies)"
  command -v crb &>/dev/null && rlRun "crb enable" 0-255 "crb enable" || true
  fap_rules_d_enable_repo crb
  fap_rules_d_enable_repo powertools
  local rh
  rh=$(rpm -E '%{?rhel}' 2>/dev/null) || true
  [[ -z "$rh" || "$rh" == "%{?rhel}" ]] || \
    fap_rules_d_enable_repo "codeready-builder-for-rhel-${rh}-$(uname -m)-rpms"
}

# SRPMs live in *-source repos (usually off by default). Enable trio + RHEL subscription ids + CentOS Stream
# dynamic ids from VERSION_ID major (e.g. centos-stream-10-*-source, c10s-build-source).
fap_rules_d_enable_source_repos() {
  rlLog "Enable source RPM repos (best effort for rlFetchSrcForInstalled / dnf download --source)"
  local rh m id os_ver
  rh=$(rpm -E '%{?rhel}' 2>/dev/null) || true
  m=$(uname -m)
  os_ver=$(awk -F= '/^VERSION_ID=/{gsub(/"/,"",$2); print $2}' /etc/os-release 2>/dev/null | cut -d. -f1)

  if command -v dnf &>/dev/null; then
    rlRun "dnf config-manager --set-enabled baseos-source appstream-source crb-source" 0-255 \
      "dnf config-manager --set-enabled baseos-source appstream-source crb-source" || true
  else
    for id in baseos-source appstream-source crb-source; do
      fap_rules_d_enable_repo "$id"
    done
  fi

  local -a ids=( powertools-source )
  if [[ -n "$rh" && "$rh" != "%{?rhel}" ]]; then
    ids+=(
      "rhel-${rh}-for-${m}-baseos-source-rpms"
      "rhel-${rh}-for-${m}-appstream-source-rpms"
      "codeready-builder-for-rhel-${rh}-${m}-source-rpms"
    )
  fi
  if [[ -n "$os_ver" ]] && rpm -q centos-stream-release &>/dev/null; then
    ids+=(
      "centos-stream-${os_ver}-baseos-source"
      "centos-stream-${os_ver}-appstream-source"
      "centos-stream-${os_ver}-crb-source"
      "c${os_ver}s-build-source"
    )
  fi
  for id in "${ids[@]}"; do
    fap_rules_d_enable_repo "$id"
  done
}

# True if local file is a real SRPM (file(1) rejects HTML/XML/text; trust file "RPM…src"; rpm -qp last resort).
fap_rules_d_rpm_file_is_srpm() {
  local f=$1 a ft
  [[ -s "$f" ]] || return 1

  if command -v file &>/dev/null; then
    ft=$(file -b "$f" 2>/dev/null) || ft=''
    # Reject captive portal / proxy HTML error pages
    echo "$ft" | grep -qiE 'HTML|XML|text' && return 1
    # If file(1) recognizes a source RPM, trust it (unsigned Brew / strict digest can break rpm -qp alone).
    echo "$ft" | grep -qiE 'RPM.*src' && return 0
  else
    head -c 1024 "$f" 2>/dev/null | grep -qiE '<!DOCTYPE|<html|<\?xml' && return 1
  fi

  # Last resort: ignore missing signatures/digests (internal unsigned builds)
  a=$(rpm -qp --nodigest --nosignature --qf '%{ARCH}\n' "$f" 2>/dev/null | grep -v '^warning:' | tr -d '\n') || return 1
  [[ "$a" == "src" || "$a" == "nosrc" ]]
}

fap_rules_d_have_valid_fapolicyd_srpm_in_cwd() {
  local g
  for g in ./fapolicyd-*.src.rpm; do
    [[ -f "$g" ]] || continue
    fap_rules_d_rpm_file_is_srpm "$g" && return 0
  done
  return 1
}

fap_rules_d_scrub_invalid_fapolicyd_srpm_globs() {
  local g
  for g in ./fapolicyd-*.src.rpm; do
    [[ -f "$g" ]] || continue
    fap_rules_d_rpm_file_is_srpm "$g" || rm -f -- "$g"
  done
}

# Obtain installed fapolicyd SRPM into cwd (TmpDir). DNF *source* wildcard, Brew, Stream Koji/mirrors by OS major.
fap_rules_d_fetch_fapolicyd_srpm() {
  local n=$1 v=$2 r=$3
  local srpm dnf_src_args='--enablerepo=*source*' rh_mirror koji_url brew_path _fap_mir os_ver

  if [[ -z "$n" || -z "$v" || -z "$r" ]]; then
    n=$(rpm -q --qf '%{name}' fapolicyd 2>/dev/null) || n='fapolicyd'
    v=$(rpm -q --qf '%{version}' fapolicyd 2>/dev/null) || v=''
    r=$(rpm -q --qf '%{release}' fapolicyd 2>/dev/null) || r=''
  fi
  [[ -n "$v" && -n "$r" ]] || \
    rlDie "fap_rules_d_fetch_fapolicyd_srpm: missing version/release (rpm -q fapolicyd)"

  srpm=$(rpm -q --qf '%{SOURCERPM}' fapolicyd)
  os_ver=$(awk -F= '/^VERSION_ID=/{gsub(/"/,"",$2); print $2}' /etc/os-release 2>/dev/null | cut -d. -f1)

  try_curl_srpm() {
    local url=$1 dest="./${srpm}"
    rm -f -- "$dest"
    if curl -fL --connect-timeout 15 --retry 2 -o "$dest" "$url" &>/dev/null; then
      if fap_rules_d_rpm_file_is_srpm "$dest"; then
        rlLog "Success: valid SRPM from ${url}"
        return 0
      fi
      rlLog "Warning: URL returned payload but not a valid SRPM ($(command -v file &>/dev/null && file -b "$dest" || echo unknown))"
      rm -f -- "$dest"
    fi
    return 1
  }

  command -v dnf &>/dev/null && \
    rlRun "dnf makecache" 0-255 "Refresh DNF metadata" || true
  rlRun "rlFetchSrcForInstalled fapolicyd" 0-255
  fap_rules_d_scrub_invalid_fapolicyd_srpm_globs
  fap_rules_d_have_valid_fapolicyd_srpm_in_cwd && return 0

  rlLog "BeakerLib did not leave a valid fapolicyd *.src.rpm; SRPM recovery (dnf / Brew / Stream Koji)"

  if command -v dnf &>/dev/null; then
    if fap_rules_d_dnf_download_is_dnf5; then
      rlRun "dnf download -y --destdir=. ${dnf_src_args} --srpm ${n}-${v}-${r}" 0-255 \
        "dnf5: dnf download --srpm (wildcard *source* repos)" || true
    else
      rlRun "dnf download -y --destdir=. ${dnf_src_args} --source ${n}-${v}-${r}" 0-255 \
        "dnf4: dnf download --source (wildcard *source* repos)" || true
    fi
    if ! fap_rules_d_have_valid_fapolicyd_srpm_in_cwd; then
      if fap_rules_d_dnf_download_is_dnf5; then
        rlRun "dnf download -y --destdir=. ${dnf_src_args} --srpm ${n}" 0-255 \
          "dnf5: dnf download --srpm ${n} (wildcard *source*)" || true
      else
        rlRun "dnf download -y --destdir=. ${dnf_src_args} --source ${n}" 0-255 \
          "dnf4: dnf download --source ${n} (wildcard *source*)" || true
      fi
    fi
  else
    rlRun "yumdownloader --source ${n}-${v}-${r}" 0-255 "yumdownloader --source (no dnf)" || true
  fi
  fap_rules_d_scrub_invalid_fapolicyd_srpm_globs
  fap_rules_d_have_valid_fapolicyd_srpm_in_cwd && return 0

  brew_path="brewroot/packages/${n}/${v}/${r}/src/${srpm}"
  try_curl_srpm "http://download.eng.bos.redhat.com/${brew_path}" && return 0
  try_curl_srpm "https://download.devel.redhat.com/${brew_path}" && return 0

  rh_mirror=$(rpm -E '%{?rhel}' 2>/dev/null) || true
  # Stream Koji + mirror layout use ${os_ver}-stream (e.g. 10-stream). Skip on Fedora etc. (no Stream / wrong major).
  if [[ -n "$os_ver" ]] && { rpm -q centos-stream-release &>/dev/null || \
      [[ -n "$rh_mirror" && "$rh_mirror" != "%{?rhel}" && "$rh_mirror" =~ ^(9|10)$ ]]; }; then
    koji_url="https://kojihub.stream.centos.org/kojifiles/packages/${n}/${v}/${r}/src/${srpm}"
    try_curl_srpm "$koji_url" && return 0
    for _fap_mir in AppStream BaseOS CRB; do
      try_curl_srpm "https://mirror.stream.centos.org/${os_ver}-stream/${_fap_mir}/source/tree/Packages/f/${srpm}" && return 0
    done
  fi

  fap_rules_d_have_valid_fapolicyd_srpm_in_cwd || \
    rlDie "could not obtain fapolicyd SRPM (dnf *source*, internal Brew, Stream Koji, mirrors)"
}
fap_normalize_evr() {
  sed 's/^(none):/0:/' <<<"$1"
}

# Newest fapolicyd NVR in repos that is still strictly older than the installed build (for upgrade-from-legacy tests).
fap_rules_d_pick_older_fapolicyd() {
  FAP_UPGRADE_FROM_OLD=0
  V_old=''
  R_old=''
  if ! command -v rpmdev-vercmp &>/dev/null; then
    rlLog "rpmdev-vercmp (rpmdevtools) missing; cannot auto-select an older fapolicyd — upgrade-from-old phases will be skipped"
    return
  fi
  local installed arch="$1"
  installed=$(fap_normalize_evr "$(rpm -q --qf '%{epoch}:%{version}-%{release}\n' fapolicyd)")

  local best_evr='' ver='' rel=''
  local evr nv nr na rc
  while IFS='|' read -r evr nv nr na; do
    [[ -n "$evr" ]] || continue
    [[ "$na" == "$arch" ]] || continue
    evr=$(fap_normalize_evr "$evr")
    rpmdev-vercmp "$evr" "$installed"
    rc=$?
    [[ "$rc" -eq 12 ]] || continue
    if [[ -z "$best_evr" ]]; then
      best_evr=$evr
      ver=$nv
      rel=$nr
    else
      rpmdev-vercmp "$best_evr" "$evr"
      rc=$?
      [[ "$rc" -eq 12 ]] && { best_evr=$evr; ver=$nv; rel=$nr; }
    fi
  done < <(fap_repoquery --available --showduplicates -q \
    --qf '%{epoch}:%{version}-%{release}|%{version}|%{release}|%{arch}' fapolicyd 2>/dev/null)

  if [[ -n "$ver" && -n "$rel" ]]; then
    V_old=$ver
    R_old=$rel
    FAP_UPGRADE_FROM_OLD=1
    rlLog "Older fapolicyd for upgrade tests: ${V_old}-${R_old}.$arch (installed EVR $installed)"
  else
    rlLog "No older fapolicyd NVR in enabled repos — upgrade-from-old phases will be skipped"
  fi
}

# Ship a _99 RPM whose default 95-allow-open.rules uses perm=any (test "updated default rules").
# Lines are injected immediately before %%build, so they run at the end of %%prep (same cwd as the
# extracted sources — same phase as the old %%patch99 approach, without brittle spec line numbers).
# If upstream renames the file or changes the allow line, update the sed/grep below (the old
# unified diff broke the same way when context drifted).
fap_rules_d_spec_add_prep_sed_for_99() {
  local spec=$1
  awk '
    /^# rules-d test: vendor-updated default rules \(_99\)$/ { next }
    /^%build$/ && !inserted {
      print "# rules-d test: vendor-updated default rules (_99)"
      print "test -f rules.d/95-allow-open.rules || { echo '\''rules-d test: missing rules.d/95-allow-open.rules'\'' >&2; exit 1; }"
      print "sed -i '\''s/^allow perm=open all : all$/allow perm=any all : all/'\'' rules.d/95-allow-open.rules"
      print "grep -q '\''^allow perm=any all : all$'\'' rules.d/95-allow-open.rules || { echo '\''rules-d test: _99 sed did not apply; adjust fap_rules_d_spec_add_prep_sed_for_99 for new default rule syntax'\'' >&2; exit 1; }"
      inserted = 1
    }
    { print }
  ' "$spec" > "${spec}.rulesd.new" && mv -f "${spec}.rulesd.new" "$spec"
}

rlJournalStart && {
  rlPhaseStartSetup && {
    rlRun "rlImport --all" 0 "Import libraries" || rlDie "cannot continue"
    # fapSetup / fapCleanup come from fapolicyd/common (not always pulled by rlImport --all without Makefile).
    if ! declare -F fapSetup &>/dev/null; then
      rlRun "rlImport fapolicyd/common" 0-255 "Import fapolicyd common library (beakerlib)"
      if ! declare -F fapSetup &>/dev/null; then
        _fap_common_lib=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && printf '%s/Library/common/lib.sh\n' "$(pwd)")
        if [[ -f "$_fap_common_lib" ]]; then
          # shellcheck source=/dev/null
          . "$_fap_common_lib"
          rlLog "sourced fapolicyd common from ${_fap_common_lib}"
        fi
      fi
    fi
    declare -F fapSetup &>/dev/null || rlDie "fapSetup missing: require fapolicyd/common (main.fmf) or full fapolicyd-tests tree"
    # FMF/tmt has no Makefile; same dependency check as e.g. Sanity/rpm-exclude-list, destructive/*.
    tcfRun "rlCheckRecommended; rlCheckRequired" || rlDie "cannot continue"
    fap_rules_d_enable_build_repos
    fap_rules_d_enable_source_repos
    IFS=' ' read -r SRC N V R A < <(rpm -q --qf '%{sourcerpm} %{name} %{version} %{release} %{arch}\n' fapolicyd)
    fap_rules_d_pick_older_fapolicyd "$A"
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
    fap_rules_d_fetch_fapolicyd_srpm "$N" "$V" "$R"
    rlRun "rpm -ivh ./fapolicyd*.src.rpm"
    # Rawhide / dnf5: yum-builddep sometimes exits 1; dnf builddep is the supported path.
    rlRun "dnf builddep -y ~/rpmbuild/SPECS/fapolicyd.spec || yum-builddep -y ~/rpmbuild/SPECS/fapolicyd.spec" 0 \
      "install spec BuildRequires (dnf builddep or yum-builddep)"
    R2=".$(echo "$R" | cut -d . -f 2-)"
    rlRun -s "rpmbuild -bb -D 'dist ${R2}_98' ~/rpmbuild/SPECS/fapolicyd.spec" 0 "build newer package"
    rlRun_LOG1=$rlRun_LOG
    fap_rules_d_spec_add_prep_sed_for_99 ~/rpmbuild/SPECS/fapolicyd.spec
    rlRun -s "rpmbuild -bb -D 'dist ${R2}_99' ~/rpmbuild/SPECS/fapolicyd.spec" 0 "build newer package with updated default rules"
    rlRun "mkdir rpms"
    pushd rpms
    _fap_wrote_rpms=$(awk '/^Wrote: /{print $2}' "$rlRun_LOG1" "$rlRun_LOG" 2>/dev/null | tr '\n' ' ')
    if [[ -n "${_fap_wrote_rpms// }" ]]; then
      rlRun "cp ${_fap_wrote_rpms} ./" 0 "copy built RPMs into local repo"
    else
      rlDie "no rpmbuild Wrote: lines (fix builddep / rpmbuild first; avoid empty cp)"
    fi
    packages=()
    if [[ ${FAP_UPGRADE_FROM_OLD:-0} -eq 1 ]]; then
      packages+=(
        fapolicyd-${V_old}-${R_old}.$A
        fapolicyd-selinux-${V_old}-${R_old}.noarch
      )
      if [[ -n "$(fap_repoquery -q --available "fapolicyd-dnf-plugin-${V_old}-${R_old}.noarch" 2>/dev/null)" ]]; then
        packages+=(fapolicyd-dnf-plugin-${V_old}-${R_old}.noarch)
      fi
      for package in "${packages[@]}"; do
        rlRpmDownload $package
      done
    fi
    rlRun "createrepo --database ./"
    rlRun -s "ls -la"
    _98=$( cat $rlRun_LOG | grep -o 'fapolicyd-[0-9].*_98.*\.rpm' | sed -r 's/\.rpm//' )
    _99=$( cat $rlRun_LOG | grep -o 'fapolicyd-[0-9].*_99.*\.rpm' | sed -r 's/\.rpm//' )
    popd
    # dnf5 removed "config-manager --add-repo"; write .repo directly (Fedora/tmt safe).
    _rules_d_rpms_base=$(readlink -f "$PWD/rpms")
    repofile=/etc/yum.repos.d/fapolicyd-rules-d-test-$$.repo
    CleanupRegister "rlRun 'rm -f $repofile'"
    cat > "$repofile" <<EOF
[fapolicyd-rules-d-test]
name=fapolicyd rules-d test local repo
baseurl=file://${_rules_d_rpms_base}
enabled=1
gpgcheck=0
sslverify=0
skip_if_unavailable=1
EOF
    rlRun "test -s $repofile" 0 "register local repo at file://${_rules_d_rpms_base}"
    rlRun "yum clean all"
    rlRun "repoquery -a | grep fapolicyd" 0-255
  rlPhaseEnd; }

  tcfTry "Tests" --no-assert && {
    rlPhaseStartTest "clean install" && {
      # fapolicyd.rules should not exit
      # rules.d should be populated
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "yum remove fapolicyd -y"
      rlRun "yum install fapolicyd-$V-$R -y --allowerasing"
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
      # fapolicyd must refuse to start if both fapolicyd.rules and populated rules.d exist.
      # fapStart calls rlServiceStart — BeakerLib may log ERROR when start fails; that is expected here.
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "yum reinstall fapolicyd-$V-$R -y"
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
      _fap_start_log=$rlRun_LOG
      sleep 1
      rlRun -s "journalctl -u fapolicyd -n 120 --no-pager --no-full"
      cat "$_fap_start_log" >>"$rlRun_LOG"
      # Message is usually in the journal; full text may be "Error - both old and new rules exist. Delete …"
      rlAssertGrep 'both old and new rules exist' "$rlRun_LOG"
      rm -f /etc/fapolicyd/fapolicyd.rules
    rlPhaseEnd; }

    rlPhaseStartTest "upgrade from old version - default rules" && {
      if [[ ${FAP_UPGRADE_FROM_OLD:-0} -ne 1 ]]; then
        rlLog "SKIP upgrade from old version - default rules: no older fapolicyd in repos (rpmdevtools + duplicate NVRs needed)"
      else
        # fapolicyd.rules should be replace with populated rules.d
        rlRun "rm -rf /etc/fapolicyd"
        rlRun "yum install fapolicyd-$V_old-$R_old -y --allowerasing"
        rlRun "yum reinstall fapolicyd-$V_old-$R_old -y --allowerasing"
        rlRun "ls -la /etc/fapolicyd/"
        rlRun "yum install fapolicyd-$V-$R -y --allowerasing"
        rlRun "ls -la /etc/fapolicyd/"
        rlRun "ls -la /etc/fapolicyd/rules.d/"
        rlAssertNotExists /etc/fapolicyd/fapolicyd.rules
        rlAssertGreater "rules are deployed into /etc/fapolicyd/rules.d" $(ls -1 /etc/fapolicyd/rules.d | wc -w) 0
      fi
    rlPhaseEnd; }

    rlPhaseStartTest "upgrade from old version - changed rules" && {
      if [[ ${FAP_UPGRADE_FROM_OLD:-0} -ne 1 ]]; then
        rlLog "SKIP upgrade from old version - changed rules: no older fapolicyd in repos (rpmdevtools + duplicate NVRs needed)"
      else
        # fapolicyd.rules should stay untouched
        # rules.d should not be populated
        rlRun "rm -rf /etc/fapolicyd"
        rlRun "yum install fapolicyd-$V_old-$R_old -y --allowerasing"
        rlRun "yum reinstall fapolicyd-$V_old-$R_old -y --allowerasing"
        echo "allow perm=any all : all" >> /etc/fapolicyd/fapolicyd.rules
        rlRun "ls -la /etc/fapolicyd/"
        rlRun "yum install fapolicyd-$V-$R -y --allowerasing"
        rlRun "ls -la /etc/fapolicyd/"
        rlRun "ls -la /etc/fapolicyd/rules.d/"
        rlAssertExists /etc/fapolicyd/fapolicyd.rules
        if fap_rules_d_rules_packaging_like_fedora; then
          rlLog "Fedora / CentOS Stream 10+: upgrade may repopulate rules.d while fapolicyd.rules remains"
          rlAssertGreater "rules.d after upgrade (distro may install sample rules)" \
            $(ls -1 /etc/fapolicyd/rules.d | wc -w) 0
        else
          rlAssertEquals "rules are deployed into /etc/fapolicyd/rules.d" $(ls -1 /etc/fapolicyd/rules.d | wc -w) 0
        fi
      fi
    rlPhaseEnd; }

    rlPhaseStartTest "upgrade to new version - still with fapolicyd.rules" && {
      # fapolicyd.rules should stay untouched
      # rules.d should not be populated
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "yum install fapolicyd-$V-$R -y --allowerasing"
      rlRun "yum reinstall fapolicyd-$V-$R -y --allowerasing"
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
      rlRun "yum install ${_98} -y --allowerasing"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlAssertExists /etc/fapolicyd/fapolicyd.rules
      rlAssertEquals "rules are deployed into /etc/fapolicyd/rules.d" $(ls -1 /etc/fapolicyd/rules.d | wc -w) 0
    rlPhaseEnd; }

    rlPhaseStartTest "upgrade to new version - changed default rules" && {
      # fapolicyd.rules should not exit
      # rules.d should stay untouched
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "yum install fapolicyd-$V-$R -y --allowerasing"
      rlRun "yum reinstall fapolicyd-$V-$R -y --allowerasing"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      echo "allow perm=any all : all" >> /etc/fapolicyd/rules.d/95-allow-open.rules
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertGrep 'allow perm=open' $rlRun_LOG
      rlAssertGrep 'allow perm=any' $rlRun_LOG
      rlRun "yum install ${_98} -y --allowerasing"
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
      rlRun "yum install fapolicyd-$V-$R -y --allowerasing"
      rlRun "yum reinstall fapolicyd-$V-$R -y --allowerasing"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertGrep 'allow perm=open' $rlRun_LOG
      # rules.d/*.rules are %%ghost: %%post copies sample-rules when rules.d is empty. Fedora &
      # CentOS Stream 10+ often keep existing *.rules across upgrade — clear so %%post installs _99 defaults.
      if fap_rules_d_rules_packaging_like_fedora; then
        rlRun "rm -f /etc/fapolicyd/rules.d/*.rules"
      fi
      rlRun "yum install ${_99} -y --allowerasing"
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
      rlRun "yum install fapolicyd-$V-$R -y --allowerasing"
      rlRun "yum reinstall fapolicyd-$V-$R -y --allowerasing"
      rlRun "echo 'allow perm=open exe=/path/to/binary : all' > /etc/fapolicyd/rules.d/51-custom.rules"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertGrep 'allow perm=open' $rlRun_LOG
      rlAssertGrep 'allow perm=open exe=/path/to/binary : all' /etc/fapolicyd/rules.d/51-custom.rules
      rlRun "yum install ${_98} -y --allowerasing"
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
      rlRun "yum install fapolicyd-$V-$R -y --allowerasing"
      rlRun "yum reinstall fapolicyd-$V-$R -y --allowerasing"
      rlRun "echo 'allow perm=open exe=/path/to/binary : all' > /etc/fapolicyd/rules.d/51-custom.rules"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertGrep 'allow perm=open' $rlRun_LOG
      rlAssertGrep 'allow perm=open exe=/path/to/binary : all' /etc/fapolicyd/rules.d/51-custom.rules
      rlRun "yum install ${_99} -y --allowerasing"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertGrep 'allow perm=open' $rlRun_LOG
      rlAssertNotGrep 'allow perm=any' $rlRun_LOG
      rlAssertGrep 'allow perm=open exe=/path/to/binary : all' /etc/fapolicyd/rules.d/51-custom.rules
    rlPhaseEnd; }

    rlPhaseStartTest "uninstall - default rules" && {
      # Main package must be gone (rpm -q below). rules.d differs by distro:
      #   Fedora & CentOS Stream 10+: defaults often stay after uninstall (count unchanged).
      #   RHEL / Alma / Rocky / …: %%preun may clear unchanged %%ghost defaults — rules.d empty.
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "yum install fapolicyd-$V-$R -y --allowerasing"
      rlRun "yum reinstall fapolicyd-$V-$R -y --allowerasing"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertGrep 'allow perm=open' $rlRun_LOG
      fap_rules_d_n_before=$(ls -1 /etc/fapolicyd/rules.d | wc -w)
      rlRun "yum remove fapolicyd -y"
      rlRun "rpm -q fapolicyd" 1 "fapolicyd RPM is not installed"
      rlRun "ls -la /etc/fapolicyd/" 0-255
      rlRun "ls -la /etc/fapolicyd/rules.d/" 0-255
      if fap_rules_d_rules_packaging_like_fedora; then
        rlAssertExists /etc/fapolicyd/rules.d
        fap_rules_d_n_after=$(ls -1 /etc/fapolicyd/rules.d | wc -w)
        rlAssertEquals "Fedora / CentOS Stream 10+: default rules.d preserved after uninstall" \
          "$fap_rules_d_n_after" "$fap_rules_d_n_before"
      else
        if [[ -d /etc/fapolicyd/rules.d/ ]]; then
          fap_rules_d_n_after=$(ls -1 /etc/fapolicyd/rules.d | wc -w)
          rlAssertEquals "RHEL-like: rules.d empty after uninstall (unchanged defaults removed)" \
            "$fap_rules_d_n_after" 0
        fi
      fi
    rlPhaseEnd; }

    rlPhaseStartTest "uninstall - custom rules" && {
      # fapolicyd.rules should not exit
      # rules.d should stay untouched
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "yum install fapolicyd-$V-$R -y --allowerasing"
      rlRun "yum reinstall fapolicyd-$V-$R -y --allowerasing"
      rlRun "echo 'allow perm=open exe=/path/to/binary : all' > /etc/fapolicyd/rules.d/51-custom.rules"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertGrep 'allow perm=open' $rlRun_LOG
      rlAssertGrep 'allow perm=open exe=/path/to/binary : all' /etc/fapolicyd/rules.d/51-custom.rules
      rlRun "yum remove fapolicyd -y"
      rlRun "ls -la /etc/fapolicyd/" 0-255
      rlRun "ls -la /etc/fapolicyd/rules.d/" 0-255
      rlAssertGreater "rules are deployed into /etc/fapolicyd/rules.d" $(ls -1 /etc/fapolicyd/rules.d | wc -w) 0
    rlPhaseEnd; }

    rlPhaseStartTest "uninstall - changed default rules" && {
      # fapolicyd.rules should not exit
      # rules.d should stay untouched
      rlRun "rm -rf /etc/fapolicyd"
      rlRun "yum install fapolicyd-$V-$R -y --allowerasing"
      rlRun "yum reinstall fapolicyd-$V-$R -y --allowerasing"
      rlRun "sed -ir 's/open/any/' /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlRun "ls -la /etc/fapolicyd/"
      rlRun "ls -la /etc/fapolicyd/rules.d/"
      rlRun -s "cat /etc/fapolicyd/rules.d/95-allow-open.rules"
      rlAssertGrep 'allow perm=any' $rlRun_LOG
      rlRun "yum remove fapolicyd -y"
      rlRun "ls -la /etc/fapolicyd/" 0-255
      rlRun "ls -la /etc/fapolicyd/rules.d/" 0-255
      rlAssertGreater "rules are deployed into /etc/fapolicyd/rules.d" $(ls -1 /etc/fapolicyd/rules.d | wc -w) 0
    rlPhaseEnd; }

    if rlIsRHELLike '>=9.7' ; then
      rlPhaseStartTest "RHEL-30020 - custom rule pattern=normal" && {
        rlRun "yum install fapolicyd -y --allowerasing"
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
