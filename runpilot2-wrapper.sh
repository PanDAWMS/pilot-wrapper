#!/bin/bash
#
# pilot2 wrapper used at CERN central pilot factories
#
# https://google.github.io/styleguide/shell.xml

VERSION=20200316b-pilot2next

function err() {
  dt=$(date --utc +"%Y-%m-%d %H:%M:%S,%3N [wrapper]")
  echo $dt $@ >&2
}

function log() {
  dt=$(date --utc +"%Y-%m-%d %H:%M:%S,%3N [wrapper]")
  echo $dt $@
}

function get_workdir {
  if [[ ${piloturl} == 'local' && ${harvesterflag} == 'false' ]]; then
    echo $(pwd)
    return 0
  fi

  if [[ ${harvesterflag} == 'true' ]]; then
    # test if Harvester WorkFlow is OneToMany aka "Jumbo" Jobs
    if [[ ${workflowarg} == 'OneToMany' ]]; then
      if [[ -n ${!harvesterarg} ]]; then
        templ=$(pwd)/atlas_${!harvesterarg}
        mkdir ${templ}
        echo ${templ}
        return 0
      fi
    else
      echo $(pwd)
      return 0
    fi
  fi

  if [[ -n ${OSG_WN_TMP} ]]; then
    templ=${OSG_WN_TMP}/atlas_XXXXXXXX
  elif [[ -n ${TMPDIR} ]]; then
    templ=${TMPDIR}/atlas_XXXXXXXX
  else
    templ=$(pwd)/atlas_XXXXXXXX
  fi
  temp=$(mktemp -d $templ)
  echo ${temp}
}


function check_python() {
  pybin=$(which python)
  if [[ $? -ne 0 ]]; then
    log "FATAL: python not found in PATH"
    err "FATAL: python not found in PATH"
    if [[ -z "${PATH}" ]]; then
      log "In fact, PATH env var is unset mon amie"
      err "In fact, PATH env var is unset mon amie"
    fi
    log "PATH content is ${PATH}"
    err "PATH content is ${PATH}"
    apfmon_fault 1
    sortie 1
  fi
    
  pyver=$($pybin -c "import sys; print '%03d%03d%03d' % sys.version_info[0:3]")
  # check if native python version > 2.6.0
  if [[ ${pyver} -ge 002006000 ]] ; then
    log "Native python version is > 2.6.0 (${pyver})"
    log "Using ${pybin} for python compatibility"
  else
    log "ERROR: this site has native python < 2.6.0"
    err "ERROR: this site has native python < 2.6.0"
    log "Native python ${pybin} is old: ${pyver}"
  
    # Oh dear, we're doomed...
    log "FATAL: Failed to find a compatible python, exiting"
    err "FATAL: Failed to find a compatible python, exiting"
    apfmon_fault 1
    sortie 1
  fi
}

function check_proxy() {
  voms-proxy-info -all
  if [[ $? -ne 0 ]]; then
    log "WARNING: error running: voms-proxy-info -all"
    err "WARNING: error running: voms-proxy-info -all"
    arcproxy -I
    if [[ $? -eq 127 ]]; then
      log "FATAL: error running: arcproxy -I"
      err "FATAL: error running: arcproxy -I"
      apfmon_fault 1
      sortie 1
    fi
  fi
}

function check_cvmfs() {
  export VO_ATLAS_SW_DIR=${VO_ATLAS_SW_DIR:-/cvmfs/atlas.cern.ch/repo/sw}
  if [[ -d ${VO_ATLAS_SW_DIR} ]]; then
    log "Found atlas software repository"
  else
    log "ERROR: atlas software repository NOT found: ${VO_ATLAS_SW_DIR}"
    log "FATAL: Failed to find atlas software repository"
    err "FATAL: Failed to find atlas software repository"
    apfmon_fault 1
    sortie 1
  fi
}
  
function check_tags() {
  if [ -e /cvmfs/atlas.cern.ch/repo/sw/tags ]; then
    echo "sha256sum /cvmfs/atlas.cern.ch/repo/sw/tags"
    sha256sum /cvmfs/atlas.cern.ch/repo/sw/tags
  else
    log "ERROR: tags file does not exist: /cvmfs/atlas.cern.ch/repo/sw/tags, exiting."
    err "ERROR: tags file does not exist: /cvmfs/atlas.cern.ch/repo/sw/tags, exiting."
    apfmon_fault 1
    sortie 1
  fi
  echo
}

function setup_alrb() {
  log 'NOTE: rucio,davix,xrootd setup now done in local site setup atlasLocalSetup.sh'
  if [[ ${iarg} == "RC" ]]; then
    log 'RC pilot requested, setting ALRB_rucioVersion=testing'
    export ALRB_rucioVersion=testing
  fi
  if [[ ${iarg} == "ALRB" ]]; then
    log 'ALRB pilot requested, setting ALRB env vars to testing'
    export ALRB_asetupVersion=testing
    export ALRB_xrootdVersion=testing
    export ALRB_davixVersion=testing
    export ALRB_rucioVersion=testing
  fi
  export ATLAS_LOCAL_ROOT_BASE=${ATLAS_LOCAL_ROOT_BASE:-/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase}
  export ALRB_userMenuFmtSkip=YES
  export ALRB_noGridMW=${ALRB_noGridMW:-NO}

  if [[ ${ALRB_noGridMW} == "YES" ]]; then
    log "Site has set ALRB_noGridMW=YES so use site native install rather than ALRB"
    if [[ ${tflag} == 'true' ]]; then
      log 'Skipping proxy checks due to -t flag'
    else
      check_vomsproxyinfo || check_arcproxy
      if [[ $? -eq 1 ]]; then
        log "FATAL: Site MW being used but proxy tools not found"
        err "FATAL: Site MW being used but proxy tools not found"
        apfmon_fault 1
        sortie 1
      fi
    fi
  else
    log "Will use ALRB MW because ALRB_noGridMW=NO (default)"
  fi

  if [ -d ${ATLAS_LOCAL_ROOT_BASE} ]; then
    log 'source ${ATLAS_LOCAL_ROOT_BASE}/user/atlasLocalSetup.sh --quiet'
    source ${ATLAS_LOCAL_ROOT_BASE}/user/atlasLocalSetup.sh --quiet
  else
    log "ERROR: ALRB ATLAS_LOCAL_ROOT_BASE not found: ${ATLAS_LOCAL_ROOT_BASE}, exiting"
    err "ERROR: ALRB ATLAS_LOCAL_ROOT_BASE not found: ${ATLAS_LOCAL_ROOT_BASE}, exiting"
    apfmon_fault 1
    sortie 1
  fi
}

function setup_local() {
  log "Looking for ${VO_ATLAS_SW_DIR}/local/setup.sh"
  if [[ -f ${VO_ATLAS_SW_DIR}/local/setup.sh ]]; then
    log "Sourcing ${VO_ATLAS_SW_DIR}/local/setup.sh -s ${qarg}"
    source ${VO_ATLAS_SW_DIR}/local/setup.sh -s ${qarg}
  else
    log 'WARNING: No ATLAS local setup found'
    err 'WARNING: this site has no local setup ${VO_ATLAS_SW_DIR}/local/setup.sh'
  fi
  # OSG MW setup
  if [[ -f ${OSG_GRID}/setup.sh ]]; then
    log "Setting up OSG MW using ${OSG_GRID}/setup.sh"
    source ${OSG_GRID}/setup.sh
  fi
}

function setup_shoal() {
  log "will set FRONTIER_SERVER with shoal"
  if [[ -n "${FRONTIER_SERVER}" ]] ; then
    export FRONTIER_SERVER
    log "call shoal frontier"
    outputstr=`shoal-client -f`
    log "result: $outputstr"

    if [[ $? -eq 0 ]] ; then
      export FRONTIER_SERVER=$outputstr
    fi

    log "set FRONTIER_SERVER = $FRONTIER_SERVER"
  fi
}

function setup_harvester_symlinks() {
  for datafile in `find ${HARVESTER_WORKDIR} -maxdepth 1 -type l -exec /usr/bin/readlink -e {} ';'`; do
      symlinkname=$(basename $datafile)
      ln -s $datafile $symlinkname
  done      
}


function check_vomsproxyinfo() {
  out=$(voms-proxy-info --version 2>/dev/null)
  if [[ $? -eq 0 ]]; then
    log "Check version: ${out}"
    return 0
  else
    log "voms-proxy-info not found"
    return 1
  fi
}

function check_arcproxy() {
  out=$(arcproxy --version 2>/dev/null)
  if [[ $? -eq 0 ]]; then
    log "Check version: ${out}"
    return 0
  else
    log "arcproxy not found"
    return 1
  fi
}

function pilot_cmd() {
  # test if not harvester job 
  if [[ ${harvesterflag} == 'false' ]] ; then  
    cmd="${pybin} pilot2/pilot.py -q ${qarg} -i ${iarg} -j ${jarg} --pilot-user=ATLAS ${pilotargs}"
  else
    # check to see if we are running OneToMany Harvester workflow (aka Jumbo Jobs)
    if [[ ${workflowarg} == 'OneToMany' ]] && [ -z ${HARVESTER_PILOT_WORKDIR+x} ] ; then
      cmd="${pybin} pilot2/pilot.py -q ${qarg} -i ${iarg} -j ${jarg} -a ${HARVESTER_PILOT_WORKDIR} --pilot-user=ATLAS ${pilotargs}"
    else
      cmd="${pybin} pilot2/pilot.py -q ${qarg} -i ${iarg} -j ${jarg} --pilot-user=ATLAS ${pilotargs}"
    fi
  fi
  echo ${cmd}
}

function get_pilot() {

  if [[ ${harvesterflag} == 'true' ]] && [[ ${workflowarg} == 'OneToMany' ]]; then
    cp -v ${HARVESTER_WORK_DIR}/pilot2.tar.gz .
  fi

  if [[ -f pilot2.tar.gz ]]; then
    tar -xzf pilot2.tar.gz
    if [ -f pilot2/pilot.py ]; then
      log "Pilot extracted from existing tarball"
      return 0
    fi
    log "FATAL: pilot extraction failed"
    err "FATAL: pilot extraction failed"
    return 1
  fi

  if [[ ${piloturl} == 'local' ]]; then
    log "Local pilotcode will be used since piloturl=local"
    if [[ -f pilot2/pilot.py ]]; then
      log "Local pilot OK: $(pwd)/pilot2/pilot.py"
      return 0
    else
      log "Local pilot NOT found: $(pwd)/pilot2/pilot.py"
      err "Local pilot NOT found: $(pwd)/pilot2/pilot.py"
      return 1 
    fi
  fi
   
  curl --connect-timeout 30 --max-time 180 -sSL ${piloturl} | tar -xzf -
  if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    log "ERROR: pilot download failed: ${piloturl}"
    err "ERROR: pilot download failed: ${piloturl}"
    return 1
  fi
  if [[ -f pilot2/pilot.py ]]; then
    log "Pilot download OK: ${piloturl}"
    return 0
  else
    log "ERROR: pilot extraction failed: ${piloturl}"
    err "ERROR: pilot extraction failed: ${piloturl}"
    return 1
  fi
}

function muted() {
  log "apfmon messages muted"
}

function apfmon_running() {
  [[ ${mute} == 'true' ]] && muted && return 0
  echo -n "running 0 ${VERSION} ${qarg} ${APFFID}:${APFCID}" > /dev/udp/148.88.67.14/28527
  out=$(curl -ksS --connect-timeout 10 --max-time 20 -d uuid=${UUID} \
             -d qarg=${qarg} -d state=wrapperrunning -d wrapper=${VERSION} \
             -d gtag=${GTAG} -d hid=${HARVESTER_ID} -d hwid=${HARVESTER_WORKER_ID} \
             ${APFMON}/jobs/${APFFID}:${APFCID})
  if [[ $? -eq 0 ]]; then
    log $out
  else
    err "WARNING: wrapper monitor ${UUID}"
  fi
}

function apfmon_exiting() {
  [[ ${mute} == 'true' ]] && muted && return 0
  out=$(curl -ksS --connect-timeout 10 --max-time 20 \
             -d state=wrapperexiting -d rc=$1 -d uuid=${UUID} \
             -d ids="${pandaids}" -d duration=$2 \
             ${APFMON}/jobs/${APFFID}:${APFCID})
  if [[ $? -eq 0 ]]; then
    log $out
  else
    err "WARNING: wrapper monitor ${UUID}"
  fi
}

function apfmon_fault() {
  [[ ${mute} == 'true' ]] && muted && return 0

  out=$(curl -ksS --connect-timeout 10 --max-time 20 \
             -d state=wrapperfault -d rc=$1 -d uuid=${UUID} \
             ${APFMON}/jobs/${APFFID}:${APFCID})
  if [[ $? -eq 0 ]]; then
    log $out
  else
    err "WARNING: wrapper monitor ${UUID}"
  fi
}

function trap_handler() {
  log "Caught $1, signalling pilot PID: $pilotpid"
  kill -s $1 $pilotpid
  wait
}

function sortie() {
  ec=$1
  if [[ $ec -eq 0 ]]; then
    state=wrapperexiting
  else
    state=wrapperfault
  fi

  log "==== wrapper stdout END ===="
  err "==== wrapper stderr END ===="

  duration=$(( $(date +%s) - ${starttime} ))
  log "wrapper ${state} ec=$ec, duration=${duration}"
  
  if [[ ${mute} == 'true' ]]; then
    muted
  else
    echo -n "${state} ${duration} ${VERSION} ${qarg} ${APFFID}:${APFCID}" > /dev/udp/148.88.67.14/28527
  fi

  exit $ec
}


function main() {
  #
  # Fail early, fail often^W with useful diagnostics
  #

  echo "This is ATLAS pilot2 wrapper version: $VERSION"
  echo "Please send development requests to p.love@lancaster.ac.uk"

  log "==== wrapper stdout BEGIN ===="
  err "==== wrapper stderr BEGIN ===="
  UUID=$(cat /proc/sys/kernel/random/uuid)
  apfmon_running
  echo

  echo "---- Host details ----"
  echo "hostname:" $(hostname -f)
  echo "pwd:" $(pwd)
  echo "whoami:" $(whoami)
  echo "id:" $(id)
  echo "getopt:" $(getopt -V 2>/dev/null)
  if [[ -r /proc/version ]]; then
    echo "/proc/version:" $(cat /proc/version)
  fi
  echo "lsb_release:" $(lsb_release -d 2>/dev/null)
  
  myargs=$@
  echo "wrapper call: $0 $myargs"

  cpuinfo_flags="flags: EMPTY"
  if [ -f /proc/cpuinfo ]; then
    cpuinfo_flags="$(grep '^flags' /proc/cpuinfo 2>/dev/null | sort -u 2>/dev/null)"
    if [ -z "${cpuinfo_flags}" ]; then 
      cpuinfo_flags="flags: EMPTY"
    fi
  else
    cpuinfo_flags="flags: EMPTY"
  fi
  
  echo "Flags from /proc/cpuinfo:"
  echo ${cpuinfo_flags}
  echo

  
  echo "---- Enter workdir ----"
  workdir=$(get_workdir)
  if [[ -f pandaJobData.out ]]; then
    log "Copying job description to working dir"
    cp pandaJobData.out $workdir/pandaJobData.out
  fi
  log "cd ${workdir}"
  cd ${workdir}
  if [[ ${harvesterflag} == 'true' ]]; then
        export HARVESTER_PILOT_WORKDIR=${workdir}
        log "Define HARVESTER_PILOT_WORKDIR : ${HARVESTER_PILOT_WORKDIR}"
  fi
  echo
  
  echo "---- Retrieve pilot code ----"
  get_pilot
  if [[ $? -ne 0 ]]; then
    log "FATAL: failed to get pilot code"
    err "FATAL: failed to get pilot code"
    apfmon_fault 1
    sortie 1
  fi
  echo
  
  echo "---- Initial environment ----"
  printenv | sort
  if [[ ${containerflag} == 'true' ]]; then
    log 'Skipping defining VO_ATLAS_SW_DIR due to --container flag'
    log 'Skipping defining ATLAS_LOCAL_ROOT_BASE due to --container flag'
  else
    export VO_ATLAS_SW_DIR='/cvmfs/atlas.cern.ch/repo/sw'
    export ATLAS_LOCAL_ROOT_BASE='/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase'
  fi
  echo
  
  echo "---- Shell process limits ----"
  ulimit -a
  echo
  
  echo "---- Check python version ----"
  check_python
  echo

  echo "---- Check cvmfs area ----"
  if [[ ${containerflag} == 'true' ]]; then
    log 'Skipping Check cvmfs area due to --container flag'
  else
    check_cvmfs
  fi
  echo

  echo "---- Setup ALRB ----"
  if [[ ${containerflag} == 'true' ]]; then
    log 'Skipping Setup ALRB due to --container flag'
  else
    setup_alrb
  fi
  echo

  echo "---- Setup local ATLAS ----"
  if [[ ${containerflag} == 'true' ]]; then
    log 'Skipping Setup local ATLAS due to --container flag'
  else
    setup_local
  fi
  echo

  if [[ ${harvesterflag} == 'true' ]]; then
    echo "---- Create symlinks to input data ----"
    log 'Create to symlinks to input data from harvester info'
    setup_harvester_symlinks
    echo
  fi
    
  if [[ "${shoalflag}" == 'true' ]]; then
    echo "--- Setup shoal ---"
    setup_shoal
    echo
  fi

  echo "---- Proxy Information ----"
  if [[ ${tflag} == 'true' ]]; then
    log 'Skipping proxy checks due to -t flag'
  else
    check_proxy
  fi
  echo
  
  echo "---- Build pilot cmd ----"
  cmd=$(pilot_cmd)
  echo cmd: ${cmd}
  echo

  echo "---- JOB Environment ----"
  printenv | sort
  echo

  echo "---- Ready to run pilot ----"
  trap trap_handler SIGTERM SIGQUIT SIGSEGV SIGXCPU SIGUSR1 SIGBUS
  echo

  log "==== pilot stdout BEGIN ===="
  $cmd &
  pilotpid=$!
  log "pilotpid: $pilotpid"
  wait $pilotpid
  pilotrc=$?
  log "==== pilot stdout END ===="
  log "==== wrapper stdout RESUME ===="
  log "Pilot exit status: $pilotrc"
  
  log "pandaIDs.out files:"
  find ${workdir}/pilot2 -name pandaIDs.out -exec ls -l {} \;
  # note max 30 pandaids for safety
  pandaids=$(find ${workdir}/pilot2 -name pandaIDs.out -exec cat {} \; | xargs echo | cut -d' ' -f-30)
  log "pandaids: ${pandaids}"

  duration=$(( $(date +%s) - ${starttime} ))
  apfmon_exiting ${pilotrc} ${duration}
  

  if [[ ${piloturl} != 'local' ]]; then
      log "cleanup: rm -rf $workdir"
      rm -fr $workdir
  else 
      log "Test setup, not cleaning"
  fi

  sortie 0
}

function usage () {
  echo "Usage: $0 -q <queue> -r <resource> -s <site> [<pilot_args>]"
  echo
  echo "  --container (Standalone container), file to source for release setup "
  echo "  --harvester (Harvester at HPC edge), NodeID from HPC batch system "
  echo "  -i,   pilot type, default PR"
  echo "  -j,   job type prodsourcelabel, default 'managed'"
  echo "  -q,   panda queue"
  echo "  -r,   panda resource"
  echo "  -s,   sitename for local setup"
  echo "  --piloturl, URL of pilot code tarball, default is http://project-atlas-gmsb.web.cern.ch/project-atlas-gmsb/pilot2.tar.gz"
  echo
  exit 1
}

starttime=$(date +%s)

# wrapper args are explicit if used in the wrapper
# additional pilot2 args are passed as extra args
containerflag='false'
containerarg=''
harvesterflag='false'
harvesterarg=''
workflowarg=''
iarg='PR'
jarg='managed'
qarg=''
rarg=''
shoalflag=false
tflag='false'
piloturl='http://pandaserver.cern.ch:25085/cache/pilot/pilot2.tar.gz'
mute='false'
myargs="$@"

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"
case $key in
    -h|--help)
    usage
    shift
    shift
    ;;
    --container)
    containerflag='true'
    #containerarg="$2"
    #shift
    shift
    ;;
    --harvester)
    harvesterflag='true'
    harvesterarg="$2"
    mute='true'
    piloturl='local'
    shift
    shift
    ;;
    --harvester_workflow)
    harvesterflag='true'
    workflowarg="$2"
    shift
    shift
    ;;
    --mute)
    mute='true'
    shift
    ;;
    --piloturl)
    piloturl="$2"
    shift
    shift
    ;;
    -i)
    iarg="$2"
    shift
    shift
    ;;
    -j)
    jarg="$2"
    shift
    shift
    ;;
    -q)
    qarg="$2"
    shift
    shift
    ;;
    -r)
    rarg="$2"
    shift
    shift
    ;;
    -s)
    sarg="$2"
    shift
    shift
    ;;
    -S|--shoal)
    shoalflag=true
    shift
    ;;
    -t)
    tflag='true'
    POSITIONAL+=("$1") # save it in an array for later
    shift
    ;;
    *)
    POSITIONAL+=("$1") # save it in an array for later
    shift
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

if [ -z "${qarg}" ]; then usage; exit 1; fi

pilotargs="$@"

fabricmon="http://fabricmon.cern.ch/api"
fabricmon="http://apfmon.lancs.ac.uk/api"
if [ -z ${APFMON} ]; then
  APFMON=${fabricmon}
fi
main "$myargs"
