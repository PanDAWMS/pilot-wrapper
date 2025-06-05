#!/bin/bash
#
# pilot wrapper used for Rubin jobs
#
# https://google.github.io/styleguide/shell.xml

VERSION=20250605a-supervisor

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
    sortie 1
  fi
}

function check_cvmfs() {
  local VO_LSST_SW_DIR=/cvmfs/sw.lsst.eu/almalinux-x86_64/lsst_distrib
  if [[ -d ${VO_LSST_SW_DIR} ]]; then
    log "Found LSST software repository: ${VO_LSST_SW_DIR}"
  else
    log "ERROR: LSST software repository NOT found: ${VO_LSST_SW_DIR}"
    log "FATAL: Failed to find LSST software repository"
    err "FATAL: Failed to find LSST software repository"
    sortie 1
  fi
}

function get_pandaenvdir() {
  if [[ -z "$pandaenvtag" ]]; then
    echo "$(ls -td /cvmfs/sw.lsst.eu/almalinux-x86_64/panda_env/v* | head -1)"
  else
    echo "$(ls -td /cvmfs/sw.lsst.eu/almalinux-x86_64/panda_env/${pandaenvtag}* | head -1)"
  fi
}

function setup_lsst() {
  log "Sourcing: ${pandaenvdir}/conda/install/bin/activate pilot"
  source ${pandaenvdir}/conda/install/bin/activate pilot
  export PILOT_ES_EXECUTOR_TYPE=fineGrainedProc
  log "DAF_BUTLER_REPOSITORY_INDEX=${DAF_BUTLER_REPOSITORY_INDEX}"
  if stat "${DAF_BUTLER_REPOSITORY_INDEX}"; then
    log 'cat ${DAF_BUTLER_REPOSITORY_INDEX}'
    cat ${DAF_BUTLER_REPOSITORY_INDEX}
  else
    log 'FATAL: failed to stat $DAF_BUTLER_REPOSITORY_INDEX'
    err 'FATAL: failed to stat $DAF_BUTLER_REPOSITORY_INDEX'
    sortie 1
  fi
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

function get_piloturl() {
  local version=$1
  local pilotdir=file://${pandaenvdir}/pilot

  if [[ -n ${piloturl} ]]; then
    echo ${piloturl}
    return 0
  fi

  if [[ ${version} == '1' ]]; then
    log "FATAL: pilot version 1 requested, not supported by this wrapper"
    err "FATAL: pilot version 1 requested, not supported by this wrapper"
    sortie 1
  elif [[ ${version} == '2' ]]; then
    log "FATAL: pilot version 2 requested, not supported by this wrapper"
    err "FATAL: pilot version 2 requested, not supported by this wrapper"
    sortie 1
  elif [[ ${version} == 'latest' ]]; then
    pilottar=${pilotdir}/pilot3.tar.gz
  elif [[ ${version} == 'current' ]]; then
    pilottar=${pilotdir}/pilot3.tar.gz
  elif [[ ${version} == '3' ]]; then
    pilottar=${pilotdir}/pilot3.tar.gz
  else
    pilottar=${pilotdir}/pilot3-${version}.tar.gz
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
    pilotdir=$(tar ztf pilot3.tar.gz | head -1)
    pilotbase=$(basename ${pilotdir})
    log "pilotbase: ${pilotbase}"
  else
    log "Extracting pilot from: ${url}"
    curl --connect-timeout 30 --max-time 180 -sSL ${url} | tar -xzf -
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
      log "ERROR: pilot download failed: ${url}"
      err "ERROR: pilot download failed: ${url}"
      return 1
    fi
    pilotdir=$(curl --connect-timeout 30 --max-time 180 -sSL ${url} 2>/dev/null | tar ztf - | head -1)
    pilotbase=$(basename ${pilotdir})
    export PANDA_PILOT_SOURCE=${pilotdir}
    log "PANDA_PILOT_SOURCE=${PANDA_PILOT_SOURCE}"
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

function rtmon_running() {
  log "APFCE: ${APFCE}"
  echo -n "${VERSION} \
         ${APFFID}:${APFCID} \
         running 0 \
         ${qarg:-unknown} \
         ${APFCE:-unknown} \
         ${HARVESTER_ID:-unknown} \
         ${HARVESTER_WORKER_ID:-unknown} \
         ${GTAG:-unknown}" \
         > /dev/udp/148.88.97.108/15778
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
  if [[ $1 -eq 0 ]]; then
    state=exiting
  else
    state=fault
  fi

  if [[ -n "${SUPERVISOR_PID}" ]]; then
    CHILD=$(ps -o pid= --ppid "$SUPERVISOR_PID")
  else
    log "No supervise_pilot process found"
  fi
  if [[ -n "${CHILD}" ]]; then
    log "cleanup supervisor_pilot $CHILD $SUPERVISOR_PID"
  else
    log "No supervise_pilot CHILD process found"
  fi
  kill -s 15 $CHILD $SUPERVISOR_PID > /dev/null 2>&1

  if [[ ${piloturl} != 'local' ]]; then
      log "cleanup: rm -rf $workdir"
      rm -fr $workdir
  else
      log "Test setup, not cleaning"
  fi
  
  duration=$(( $(date +%s) - ${starttime} ))
  log "${state} ec=$1, duration=${duration}"
  echo -n "${VERSION} \
         ${APFFID}:${APFCID} \
         ${state} ${duration} \
         ${qarg:-unknown} \
         ${APFCE:-unknown} \
         ${HARVESTER_ID:-unknown} \
         ${HARVESTER_WORKER_ID:-unknown} \
         ${GTAG:-unknown}" \
         > /dev/udp/148.88.97.108/15778
  
  log "==== wrapper stdout END ===="
  err "==== wrapper stderr END ===="

  exit $1
}

function supervise_pilot() {
  # check pilotlog.txt is being updated otherwise kill the pilot
  local PILOT_PID=$1
  local counter=0
  while true; do
    ((counter++))
    err "supervise_pilot (15 min periods counter: ${counter})"
    if [[ -f "pilotlog.txt" ]]; then
      CURRENT_TIME=$(date +%s)
      LAST_MODIFICATION=$(stat -c %Y "pilotlog.txt")
      TIME_DIFF=$(( CURRENT_TIME - LAST_MODIFICATION ))

      if [[ $TIME_DIFF -gt 3600 ]]; then
        err "CURRENT_TIME: ${CURRENT_TIME}"
        err "LAST_MODIFICATION: ${LAST_MODIFICATION}"
        err "TIME_DIFF: ${TIME_DIFF}"
        log "pilotlog.txt has not been updated in the last hour. Sending SIGINT (2) signal to the pilot process."
        err "pilotlog.txt has not been updated in the last hour. Sending SIGINT (2) signal to the pilot process."
        kill -s 2 $PILOT_PID > /dev/null 2>&1
        touch wrapper_sigint_$PILOT_PID
        sleep 180
        if kill -s 0 $PILOT_PID > /dev/null 2>&1; then
          log "The pilot process ($PILOT_PID) is still running after 3m. Sending SIGKILL (9)."
          err "The pilot process ($PILOT_PID) is still running after 3m. Sending SIGKILL (9)."
          kill -s 9 $PILOT_PID
          touch wrapper_sigkill_$PILOT_PID
        fi
        exit 2
      fi
    else
      log "pilotlog.txt does not exist (yet)"
      err "pilotlog.txt does not exist (yet)"
    fi

    # Check every 15 mins
    sleep 900
  done
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

  echo "This is Rubin pilot wrapper version: $VERSION"
  echo "Please send development requests to p.love@lancaster.ac.uk"
  echo "Wrapper timestamps are UTC"
  echo
  log "==== wrapper stdout BEGIN ===="
  err "==== wrapper stderr BEGIN ===="
  UUID=$(cat /proc/sys/kernel/random/uuid)
  rtmon_running
  echo

  echo "---- Host details ----"
  echo "hostname:" $(hostname -f)
  echo "pwd:" $(pwd)
  echo "whoami:" $(whoami)
  echo "id:" $(id)
  echo "getopt -V:" $(getopt -V 2>/dev/null)
  echo "jq --version:" $(jq --version 2>/dev/null)
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

  echo "---- Initial environment (redacted) ----"
  printenv | grep -v GOOGLE_APPLICATION_CREDENTIALS | grep -v LSST_DB_AUTH
  echo
  echo "---- PWD content ----"
  pwd
  ls -la
  echo

  echo "---- Check cvmfs area ----"
  check_cvmfs
  pandaenvdir=$(get_pandaenvdir)
  log "pandaenvdir: ${pandaenvdir}"
  echo

  echo "---- Enter workdir ----"
  workdir=$(get_workdir)
  log "Workdir: ${workdir}"
  if [[ -f pandaJobData.out ]]; then
    log "Job description file exists PUSH mode, copying to working dir"
    log "cp pandaJobData.out $workdir/pandaJobData.out"
    cp pandaJobData.out $workdir/pandaJobData.out
  fi
  log "cd ${workdir}"
  cd ${workdir}
  echo
 
  echo "---- LSST_LOCAL_PROLOG script ----"
  if [[ -n "${LSST_LOCAL_PROLOG}" ]]; then
    if [[ -f "${LSST_LOCAL_PROLOG}" ]]; then
      log "Sourcing local site prolog: ${LSST_LOCAL_PROLOG}"
      source ${LSST_LOCAL_PROLOG}
    else
      log "WARNING: prolog script not found, expecting LSST_LOCAL_PROLOG=${LSST_LOCAL_PROLOG}"
    fi
  fi
  echo

  echo "---- Retrieve pilot code ----"
  piloturl=$(get_piloturl ${pilotversion})
  log "Using piloturl: ${piloturl}"

  get_pilot ${piloturl}
  if [[ $? -ne 0 ]]; then
    log "FATAL: failed to get pilot code"
    err "FATAL: failed to get pilot code"
    sortie 1
  fi
  echo

  # mkdir pilot3 since this is hardcoded in pilot3 store_jobid function
  mkdir -p pilot3
  
  echo "---- Shell process limits ----"
  ulimit -a
  echo
  
  echo "---- Setup LSST environ ----"
  setup_lsst
  echo

  echo "---- Check python version ----"
  check_python3
  echo 

  echo "---- Job Environment (redacted) ----"
  printenv | grep -v GOOGLE_APPLICATION_CREDENTIALS | grep -v LSST_DB_AUTH
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
  supervise_pilot ${pilotpid} &
  SUPERVISOR_PID=$!
  err "Started supervisor process ($SUPERVISOR_PID) (watching ${pilotpid})"
  wait $pilotpid >/dev/null 2>&1
  pilotrc=$?
  log "==== pilot stdout END ===="
  log "==== wrapper stdout RESUME ===="
  log "pilotpid: $pilotpid"
  log "Pilot exit status: $pilotrc"

  pilotbase=pilot3
  if [[ -f ${workdir}/${pilotbase}/pandaIDs.out ]]; then
    # max 30 pandaids
    pandaids=$(cat ${workdir}/${pilotbase}/pandaIDs.out | xargs echo | cut -d' ' -f-30)
    log "pandaids: ${pandaids}"
  else
    log "File not found: ${workdir}/${pilotbase}/pandaIDs.out, no payload"
    err "File not found: ${workdir}/${pilotbase}/pandaIDs.out, no payload"
    pandaids=''
  fi

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
  echo "  -i,   pilot type, default PR"
  echo "  -j,   job type prodsourcelabel, default 'managed'"
  echo "  -q,   panda queue"
  echo "  -r,   panda resource"
  echo "  -s,   sitename for local setup"
  echo "  -t,   pass -t option to pilot, skipping proxy check"
  echo "  --piloturl, URL of pilot code tarball"
  echo "  --pilotversion, request particular pilot version"
  echo "  --localpy, use local python"
  echo
  exit 1
}

starttime=$(date +%s)

harvesterarg=''
workflowarg=''
iarg='PR'
jarg='managed'
qarg=''
rarg=''
tflag='false'
piloturl=''
pilotversion='latest'
pilotbase='pilot3'
pandaenvtag=''
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
    --localpy)
    localpyflag=true
    shift
    ;;
    --piloturl)
    piloturl="$2"
    shift
    shift
    ;;
    --pandaenvtag)
    pandaenvtag="$2"
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

if [ -z ${RTMON} ]; then
  RTMON="https://rtmon.lancs.ac.uk/api"
fi
if [[ -n "${GRID_GLOBAL_JOBHOST}" ]]; then
  # ARCCE
  APFCE="${GRID_GLOBAL_JOBHOST}"
elif [[ -n "${SCHEDD_NAME}" ]]; then
  # HTCONDORCE
  APFCE="${SCHEDD_NAME}"
elif [[ -n "${CONDORCE_COLLECTOR_HOST}" ]]; then
  # HTCONDORCE
  APFCE="${CONDORCE_COLLECTOR_HOST%:*}"
else
  APFCE="unknown"
fi
main "$myargs"
