#!/bin/bash
#
# pilot wrapper used for Rubin jobs
#
# https://google.github.io/styleguide/shell.xml

VERSION=20220715a-rubin

function err() {
  dt=$(date --utc +"%Y-%m-%d %H:%M:%S,%3N [wrapper]")
  echo "$dt $@" >&2
}

function log() {
  dt=$(date --utc +"%Y-%m-%d %H:%M:%S,%3N [wrapper]")
  echo "$dt $@"
}

function get_workdir {
  if [[ ${piloturl} == 'local' ]]; then
    echo $(pwd)
    return 0
  fi

  if [[ -n "${TMPDIR}" ]]; then
    templ=${TMPDIR}/rubin_XXXXXXXX
  else
    templ=$(pwd)/rubin_XXXXXXXX
  fi
  tempd=$(mktemp -d $templ)
  echo ${tempd}
}

function setup_python3() {
  if [[ ${localpyflag} == 'true' ]]; then
    log "localpyflag is true so we skip ALRB python3, and use default system python3"
  else
    log "TODO: localpyflag is NOT true so we setup python explicitly TODO-Rubin, exiting"
    log "TODO: localpyflag is NOT true so we setup python explicitly TODO-Rubin, exiting"
    apfmon_fault 1
    sortie 1
  fi
}

function check_python3() {
  pybin=$(which python3)
  if [[ $? -ne 0 ]]; then
    log "FATAL: python3 not found in PATH"
    err "FATAL: python3 not found in PATH"
    if [[ -z "${PATH}" ]]; then
      log "In fact, PATH env var is unset mon amie"
      err "In fact, PATH env var is unset mon amie"
    fi
    log "PATH content: ${PATH}"
    err "PATH content: ${PATH}"
    apfmon_fault 1
    sortie 1
  fi
    
  pyver=$($pybin -V 2>&1 | sed 's/.* \([0-9]\).\([0-9]\).*/\1\2/')
  # check if python version > 3.6
  if [[ ${pyver} -ge 36 ]] ; then
    log "Python version is > 3.6 (${pyver})"
    log "Using ${pybin} for python compatibility"
  else
    log "ERROR: this site has python < 3.6"
    err "ERROR: this site has python < 3.6"
    log "Python ${pybin} is old: ${pyver}"
  
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
  local VO_LSST_SW_DIR=/cvmfs/sw.lsst.eu/linux-x86_64/lsst_distrib
  if [[ -d ${VO_LSST_SW_DIR} ]]; then
    log "Found LSST software repository: ${VO_LSST_SW_DIR}"
  else
    log "ERROR: LSST software repository NOT found: ${VO_LSST_SW_DIR}"
    log "FATAL: Failed to find LSST software repository"
    err "FATAL: Failed to find LSST software repository"
    apfmon_fault 1
    sortie 1
  fi
}
  
function setup_lsst() {
  log "Sourcing: /cvmfs/sw.lsst.eu/linux-x86_64/panda_env/v0.0.2-dev/setup_panda.sh"
  source /cvmfs/sw.lsst.eu/linux-x86_64/panda_env/v0.0.2-dev/setup_panda.sh
  log "INFO: temp using ALRB to setup rucio"
  [ -z "$ALRB_noGridMW" ] && export ALRB_noGridMW=YES
  ALRB_PYTHON_OPT="-3"
  source $ATLAS_LOCAL_ROOT_BASE/user/atlasLocalSetup.sh --quiet $ALRB_PYTHON_OPT
  export RUCIO_ACCOUNT=rubin
  lsetup rucio 
  log "rucio whoami: $(rucio whoami)"
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
  cmd="${pybin} ${pilotbase}/pilot.py -q ${qarg} -i ${iarg} -j ${jarg} ${pilotargs}"
  echo ${cmd}
}

function sing_cmd() {
  cmd="$BINARY_PATH exec $SINGULARITY_OPTIONS $IMAGE_PATH $0 $myargs"
  echo ${cmd}
}

function sing_env() {
  export SINGULARITYENV_X509_USER_PROXY=${X509_USER_PROXY}
  if [[ -n "${ATLAS_LOCAL_AREA}" ]]; then
    export SINGULARITYENV_ATLAS_LOCAL_AREA=${ATLAS_LOCAL_AREA}
  fi
  if [[ -n "${TMPDIR}" ]]; then
    export SINGULARITYENV_TMPDIR=${TMPDIR}
  fi
  if [[ -n "${RECOVERY_DIR}" ]]; then
    export SINGULARITYENV_RECOVERY_DIR=${RECOVERY_DIR}
  fi
  if [[ -n "${GTAG}" ]]; then
    export SINGULARITYENV_GTAG=${GTAG}
  fi
}

function get_piloturl() {
  local version=$1
  local pilotdir=file:///cvmfs/atlas.cern.ch/repo/sw/PandaPilot/tar

  if [[ -n ${piloturl} ]]; then
    echo ${piloturl}
    return 0
  fi

  if [[ ${version} == '1' ]]; then
    log "FATAL: pilot version 1 requested, not supported by this wrapper"
    err "FATAL: pilot version 1 requested, not supported by this wrapper"
    apfmon 1
    sortie 1
  elif [[ ${version} == '2' ]]; then
    log "FATAL: pilot version 2 requested, not supported by this wrapper"
    err "FATAL: pilot version 2 requested, not supported by this wrapper"
    apfmon 1
    sortie 1
  elif [[ ${version} == 'latest' ]]; then
    pilottar=${pilotdir}/pilot3.tar.gz
    pilotbase='pilot3'
  elif [[ ${version} == 'current' ]]; then
    pilottar=${pilotdir}/pilot3.tar.gz
    pilotbase='pilot3'
  elif [[ ${version} == '3' ]]; then
    pilottar=${pilotdir}/pilot3.tar.gz
    pilotbase='pilot3'
  else
    pilottar=${pilotdir}/pilot3-${version}.tar.gz
    pilotbase='pilot3'
  fi
  echo ${pilottar}
}

function get_pilot() {

  local url=$1

  if [[ ${url} == 'local' ]]; then
    log "piloturl=local so download not needed"
    
    if [[ -f pilot3.tar.gz ]]; then
      log "local tarball pilot3.tar.gz exists OK"
      tar -xzf pilot3.tar.gz
      if [[ $? -ne 0 ]]; then
        log "ERROR: pilot extraction failed for pilot3.tar.gz"
        err "ERROR: pilot extraction failed for pilot3.tar.gz"
        return 1
      fi
    else
      log "local pilot3.tar.gz not found so assuming already extracted"
    fi
  else
    log "TODO: for Rubin, get pilot from /cvmfs/sw.lsst.eu/..."
    curl --connect-timeout 30 --max-time 180 -sSL ${url} | tar -xzf -
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
      log "ERROR: pilot download failed: ${url}"
      err "ERROR: pilot download failed: ${url}"
      return 1
    fi
  fi

  if [[ -f ${pilotbase}/pilot.py ]]; then
    log "Sanity check: file ${pilotbase}/pilot.py exists OK"
    log "${pilotbase}/PILOTVERSION: $(cat ${pilotbase}/PILOTVERSION)"
    return 0
  else
    log "ERROR: ${pilotbase}/pilot.py not found"
    err "ERROR: ${pilotbase}/pilot.py not found"
    return 1
  fi
}

function muted() {
  log "apfmon messages muted"
}

function apfmon_running() {
  [[ ${mute} == 'true' ]] && muted && return 0
  echo -n "running 0 ${VERSION} ${qarg} ${APFFID}:${APFCID}" > /dev/udp/148.88.67.14/28527
  resource=${GRID_GLOBAL_JOBHOST:-}
  out=$(curl -ksS --connect-timeout 10 --max-time 20 -d uuid=${UUID} \
             -d qarg=${qarg} -d state=wrapperrunning -d wrapper=${VERSION} \
             -d gtag=${GTAG} -d resource=${resource} \
             -d hid=${HARVESTER_ID} -d hwid=${HARVESTER_WORKER_ID} \
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
  if [[ -n "${pilotpid}" ]]; then
    log "WARNING: Caught $1, signalling pilot PID: $pilotpid"
    kill -s $1 $pilotpid
    wait
  else
    log "WARNING: Caught $1 prior to pilot starting"
  fi
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
  log "${state} ec=$ec, duration=${duration}"
  
  if [[ ${mute} == 'true' ]]; then
    muted
  else
    echo -n "${state} ${duration} ${VERSION} ${qarg} ${APFFID}:${APFCID}" > /dev/udp/148.88.67.14/28527
  fi

  exit $ec
}

function get_cricopts() {
  container_opts=$(curl --silent $cricurl | grep container_options | grep -v null)
  if [[ $? -eq 0 ]]; then
    cricopts=$(echo $container_opts | awk -F"\"" '{print $4}')
    echo ${cricopts}
    return 0
  else
    return 1
  fi
}

function get_catchall() {
  local result
  local content
  result=$(curl --silent $cricurl | grep catchall | grep -v null)
  if [[ $? -eq 0 ]]; then
    content=$(echo $result | awk -F"\"" '{print $4}')
    echo ${content}
    return 0
  else
    return 1
  fi
}

function get_environ() {
  local result
  local content
  result=$(curl --silent $cricurl | grep environ | grep -v null)
  if [[ $? -eq 0 ]]; then
    content=$(echo $result | awk -F"\"" '{print $4}')
    echo ${content}
    return 0
  else
    return 1
  fi
}

function check_singularity() {
  BINARY_PATH="/cvmfs/atlas.cern.ch/repo/containers/sw/singularity/`uname -m`-el7/current/bin/singularity"
  IMAGE_PATH="/cvmfs/atlas.cern.ch/repo/containers/fs/singularity/`uname -m`-centos7"
  SINGULARITY_OPTIONS="$(get_cricopts) -B /cvmfs -B $PWD --cleanenv"
  out=$(${BINARY_PATH} --version 2>/dev/null)
  if [[ $? -eq 0 ]]; then
    log "Singularity binary found, version $out"
    log "Singularity binary path: ${BINARY_PATH}"
  else
    log "Singularity binary not found"
  fi
}

function check_type() {
  if [[ -f queuedata.json ]]; then
    result=$(cat queuedata.json | grep container_type | grep 'singularity:wrapper')
  else
    result=$(curl --silent $cricurl | grep container_type | grep 'singularity:wrapper')
  fi
  if [[ $? -eq 0 ]]; then
    log "CRIC container_type: singularity:wrapper found"
    return 0
  else
    log "CRIC container_type: singularity:wrapper not found"
    return 1
  fi
}


function main() {
  #
  # Fail early, fail often^W with useful diagnostics
  #
  trap 'trap_handler SIGINT' SIGINT
  trap 'trap_handler SIGTERM' SIGTERM
  trap 'trap_handler SIGQUIT' SIGQUIT
  trap 'trap_handler SIGSEGV' SIGSEGV
  trap 'trap_handler SIGXCPU' SIGXCPU
  trap 'trap_handler SIGUSR1' SIGUSR1
  trap 'trap_handler SIGUSR2' SIGUSR2
  trap 'trap_handler SIGBUS' SIGBUS

  if [[ -z ${SINGULARITY_ENVIRONMENT} ]]; then
    # SINGULARITY_ENVIRONMENT not set
    echo "This is Rubin pilot wrapper version: $VERSION"
    echo "Please send development requests to p.love@lancaster.ac.uk"
    echo
    log "==== wrapper stdout BEGIN ===="
    err "==== wrapper stderr BEGIN ===="
    UUID=$(cat /proc/sys/kernel/random/uuid)
    apfmon_running
    log "${cricurl}"
    echo
    echo "---- Initial environment ----"
    printenv | sort
    echo
    echo "---- PWD content ----"
    pwd
    ls -la
    echo

    echo "---- Check singularity details (development) ----"
    cric_opts=$(get_cricopts)
    if [[ $? -eq 0 ]]; then
      log "CRIC container_options: $cric_opts"
    else
      log "WARNING: failed to get CRIC container_options"
    fi

    check_type
    if [[ $? -eq 0 ]]; then
      use_singularity=true
      log "container_type contains singularity:wrapper, so use_singularity=true"
    else
      use_singularity=false
    fi

    if [[ ${use_singularity} = true ]]; then
      # check if already in SINGULARITY environment
      log 'SINGULARITY_ENVIRONMENT is not set'
      sing_env
      log 'Setting SINGULARITY_env'
      check_singularity
      export ALRB_noGridMW=NO
      echo '   _____ _                   __           _ __        '
      echo '  / ___/(_)___  ____ ___  __/ /___ ______(_) /___  __ '
      echo '  \__ \/ / __ \/ __ `/ / / / / __ `/ ___/ / __/ / / / '
      echo ' ___/ / / / / / /_/ / /_/ / / /_/ / /  / / /_/ /_/ /  '
      echo '/____/_/_/ /_/\__, /\__,_/_/\__,_/_/  /_/\__/\__, /   '
      echo '             /____/                         /____/    '
      echo
      cmd=$(sing_cmd)
      echo "cmd: $cmd"
      echo
      log '==== singularity stdout BEGIN ===='
      err '==== singularity stderr BEGIN ===='
      $cmd &
      singpid=$!
      wait $singpid
      log "singularity return code: $?"
      log '==== singularity stdout END ===='
      err '==== singularity stderr END ===='
      log "==== wrapper stdout END ===="
      err "==== wrapper stderr END ===="
      exit 0
    else
      log 'Will NOT use singularity, at least not from the wrapper'
    fi
    echo
  else
    log 'SINGULARITY_ENVIRONMENT is set, run basic setup'
    export ALRB_noGridMW=NO
    df -h
  fi

  echo "---- Host details ----"
  echo "hostname:" $(hostname -f)
  echo "pwd:" $(pwd)
  echo "whoami:" $(whoami)
  echo "id:" $(id)
  echo "getopt:" $(getopt -V 2>/dev/null)
  echo "jq:" $(jq --version 2>/dev/null)
  if [[ -r /proc/version ]]; then
    echo "/proc/version:" $(cat /proc/version)
  fi
  echo "lsb_release:" $(lsb_release -d 2>/dev/null)
  echo "SINGULARITY_ENVIRONMENT:" ${SINGULARITY_ENVIRONMENT}
  
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

  if [[ -n "${LSST_LOCAL_PROLOG}" ]]; then
    if [[ -f "${LSST_LOCAL_PROLOG}" ]]; then
      log "Sourcing local site prolog: ${LSST_LOCAL_PROLOG}"
      source ${LSST_LOCAL_PROLOG}
    else
      log "WARNING: prolog script not found, expecting LSST_LOCAL_PROLOG=${LSST_LOCAL_PROLOG}"
    fi
  fi

  echo "---- Enter workdir ----"
  workdir=$(get_workdir)
  log "Workdir: ${workdir}"
  if [[ -f pandaJobData.out ]]; then
    log "Job description file exists (PUSH mode), copying to working dir"
    log "cp pandaJobData.out $workdir/pandaJobData.out"
    cp pandaJobData.out $workdir/pandaJobData.out
  fi
  log "cd ${workdir}"
  cd ${workdir}
  echo
  
  echo "---- Retrieve pilot code ----"
  piloturl=$(get_piloturl ${pilotversion})
  log "Using piloturl: ${piloturl}"

  log "Only supporting pilot3 so pilotbase directory: pilot3"
  pilotbase='pilot3'

  get_pilot ${piloturl}
  if [[ $? -ne 0 ]]; then
    log "FATAL: failed to get pilot code"
    err "FATAL: failed to get pilot code"
    apfmon_fault 1
    sortie 1
  fi
  echo
  
  if [[ ${containerflag} == 'true' ]]; then
    log 'Skipping defining VO_ATLAS_SW_DIR due to --container flag'
    log 'Skipping defining ATLAS_LOCAL_ROOT_BASE due to --container flag'
  else
    export VO_ATLAS_SW_DIR=${VO_ATLAS_SW_DIR:-/cvmfs/atlas.cern.ch/repo/sw}
    export ATLAS_LOCAL_ROOT_BASE=${ATLAS_LOCAL_ROOT_BASE:-/cvmfs/atlas.cern.ch/repo/ATLASLocalRootBase}
  fi
  echo
  
  echo "---- Shell process limits ----"
  ulimit -a
  echo
  
  echo "---- Check python version ----"
  if [[ ${pythonversion} == '3' ]]; then
    log "pythonversion 3 selected from cmdline"
    setup_python3
    check_python3
  else
    log "FATAL: python version 3 required, cmdline --pythonversion was: ${pythonversion}"
    err "FATAL: python version 3 required, cmdline --pythonversion was: ${pythonversion}"
    apfmon_fault 1
    sortie 1
  fi
  echo

  echo "---- Check cvmfs area ----"
  if [[ ${containerflag} == 'true' ]]; then
    log 'Skipping Check cvmfs area due to --container flag'
  else
    check_cvmfs
  fi
  echo

  echo "--- Bespoke environment from CRIC ---"
  result=$(get_environ)
  if [[ $? -eq 0 ]]; then
    if [[ -z ${result} ]]; then
      log 'CRIC environ field: <empty>'
    else
      log 'CRIC environ content'
      log "export ${result}"
      export ${result}
    fi
  else
    log 'No content found in CRIC environ'
  fi
  echo

  echo "---- Setup LSST environ ----"
  if [[ ${containerflag} == 'true' ]]; then
    log 'Skipping Setup local ATLAS due to --container flag'
  else
    setup_lsst
  fi
  echo

  echo "---- Proxy Information ----"
  if [[ ${tflag} == 'true' ]]; then
    log 'Skipping proxy checks due to -t flag'
  else
    check_proxy
  fi
  
  echo "---- Job Environment ----"
  printenv | sort
  echo

  echo "---- Build pilot cmd ----"
  cmd=$(pilot_cmd)
  echo $cmd
  echo

  echo "---- Ready to run pilot ----"
  echo

  log "==== pilot stdout BEGIN ===="
  $cmd &
  pilotpid=$!
  wait $pilotpid
  pilotrc=$?
  log "==== pilot stdout END ===="
  log "==== wrapper stdout RESUME ===="
  log "pilotpid: $pilotpid"
  log "Pilot exit status: $pilotrc"
  
  if [[ -f ${workdir}/${pilotbase}/pandaIDs.out ]]; then
    # max 30 pandaids
    pandaids=$(cat ${workdir}/${pilotbase}/pandaIDs.out | xargs echo | cut -d' ' -f-30)
    log "pandaids: ${pandaids}"
  else
    log "File not found: ${workdir}/${pilotbase}/pandaIDs.out, no payload"
    err "File not found: ${workdir}/${pilotbase}/pandaIDs.out, no payload"
    pandaids=''
  fi

  duration=$(( $(date +%s) - ${starttime} ))
  apfmon_exiting ${pilotrc} ${duration}
  

  if [[ ${piloturl} != 'local' ]]; then
      log "cleanup: rm -rf $workdir"
      rm -fr $workdir
  else 
      log "Test setup, not cleaning"
  fi

  if [[ -n "${LSST_LOCAL_EPILOG}" ]]; then
    if [[ -f "${LSST_LOCAL_EPILOG}" ]]; then
      log "Sourcing local site epilog: ${LSST_LOCAL_EPILOG}"
      source ${LSST_LOCAL_EPILOG}
    else
      log "WARNING: epilog script not found, expecting LSST_LOCAL_EPILOG=${LSST_LOCAL_EPILOG}"
    fi
  fi

  sortie 0
}

function usage () {
  echo "Usage: $0 -q <queue> -r <resource> -s <site> [<pilot_args>]"
  echo
  echo "  --container (Standalone container), file to source for release setup "
  echo "  -i,   pilot type, default PR"
  echo "  -j,   job type prodsourcelabel, default 'managed'"
  echo "  -q,   panda queue"
  echo "  -r,   panda resource"
  echo "  -s,   sitename for local setup"
  echo "  -t,   pass -t option to pilot, skipping proxy check"
  echo "  --piloturl, URL of pilot code tarball"
  echo "  --pilotversion, request particular pilot version"
  echo "  --pythonversion,   valid values '2' (default), and '3'"
  echo "  --localpy, skip ALRB setup and use local python"
  echo
  exit 1
}

starttime=$(date +%s)

containerflag='false'
containerarg=''
harvesterarg=''
workflowarg=''
iarg='PR'
jarg='managed'
qarg=''
rarg=''
localpyflag='false'
tflag='false'
piloturl=''
pilotversion='latest'
pilotbase='pilot3'
pythonversion='3'
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
    --mute)
    mute='true'
    shift
    ;;
    --pilotversion)
    pilotversion="$2"
    shift
    shift
    ;;
    --pythonversion)
    pythonversion="$2"
    shift
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
    --localpy)
    localpyflag=true
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

cricurl="http://pandaserver-doma.cern.ch:25085/cache/schedconfig/${sarg}.all.json"
fabricmon="http://apfmon.lancs.ac.uk/api"
if [ -z ${APFMON} ]; then
  APFMON=${fabricmon}
fi
main "$myargs"
