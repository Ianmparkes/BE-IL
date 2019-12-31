#!/bin/ksh
# $Header: /products/oracle/stage/masterbin_app_linux/sse_stop_odi_agent.sh,v 1.5 2019/12/06 13:49:37 ip38354 Exp $
# 
# Description
#     Stops up the Fusion ODI standlone agent for the current Apps DBA environment
#
# Modification History
#
# IMP            06/09/2019      LINUX conversion of AIX script sse_stp_stop_fusion_odi_agent.sh v1.1.
# IMP            19/11/2019      Removed requirement for 'ODI_AGENT_HOME' variable from environ.ref. Now using ${DOMAIN_HOME}
#
#


# ===============================================
# function to test if environment owner
# ===============================================
env_owner ()
{
  if [ $(grep "${LOGNAME}:" /etc/oratab | grep -v "#" | grep ${TIERTYPE} | wc -l) -eq 1 ]
  then
    log_message "${LOGNAME} is the environment owner"
  else
    log_message "${LOGNAME} is NOT the environment owner, exiting."
    exit 1
  fi
}


# ===============================================
# function to log output message
# ===============================================
log_message()
{
  DATE_TIME=$(date '+%d/%m/%Y %T')
  echo "${SCRIPT}: ${DATE_TIME}: $*" | tee -a ${LOG_FILE}
}


# ===============================================
# function to run on exit
# ===============================================
exit_script()
{
  EXIT_CODE=$1
  find ${TMPDIR} -name 'sse_stop_odi_agent*' -type f -user ${LOGNAME} -mtime +7 -exec rm {} \;
  log_message ""
  log_message "--------------------------------------------------------------------------"
  log_message "exit ${EXIT_CODE}"
  log_message "--------------------------------------------------------------------------"
  exit ${EXIT_CODE}
}


# ===============================================
# function to check odi agent processes
# ===============================================
check_odi_agent_processes()
{
  log_message ""
  log_message "--------------------------------------------------------------------------"
  log_message "checking  odi agent processes"
  log_message ""
  log_message "  running ps -fu ${LOGNAME} | grep -v grep | grep -i ${ODI_AGENT_NAME}"
  log_message ""

  if ps -fu ${LOGNAME} | grep -v grep | grep -qi ${ODI_AGENT_NAME}
  then
      ODI_AGENT_PID_COUNT=$(ps -fu ${LOGNAME} | grep -v grep | grep -ic ${ODI_AGENT_NAME})
      log_message "  there are ${ODI_AGENT_PID_COUNT} odi agent processes running"
      log_message ""

      ps -fu ${LOGNAME} | grep -v grep | grep -i ${ODI_AGENT_NAME} | cut -c 1-100 | while read PID
      do
          log_message "    ${PID}"
      done

      ODI_AGENT_STATUS="up"
  else
      ODI_AGENT_STATUS="down"
      log_message "  there are no odi agent processes running"
  fi

  log_message ""
  log_message "  odi agent is ${ODI_AGENT_STATUS}"
}


# ===============================================
# function to set sse_service_status
# ===============================================
set_sse_service_status()
{
  SERVICE=$1
  STATUS=$2

  log_message ""
  log_message "--------------------------------------------------------------------------"
  log_message "setting sse_service_status to ${STATUS} for ${SERVICE}"
  log_message ""

  if [ "${VALID_SERVICE}" = "true" ]
  then
      log_message "  running sse_service_status ${SERVICE} ${STATUS}"
      log_message "  logfile ${TMPDIR}/sse_service_status_${SERVICE}_${STATUS}.log"

      sudo sse_service_status ${SERVICE} ${STATUS} > ${TMPDIR}/sse_service_status_${SERVICE}_${STATUS}.log 2>&1
      STATUS_RC=$?

      if [ ${STATUS_RC} -eq 0 ]
      then
          log_message ""
          log_message "  ${SERVICE} service is ${STATUS}"
      else
          log_message ""
          log_message "  error: problem detected setting sse_service_status ${SERVICE} ${STATUS}, exiting"
          exit_script 1
      fi
  else
      log_message "${SERVICE} service is not defined on this server"
  fi
}


# ===============================================
# set environment variables
# ===============================================
SCRIPT=sse_stop_odi_agent.sh
THIS_RUN=$(date '+%Y%m%d_%H%M%S')
LOG_FILE=${TMPDIR}/sse_stop_odi_agent_${THIS_RUN}.log
#LOGNAME=$(logname)
EMAIL_ADDRESS="appsdbasupport@sse.com"
TIERTYPE=$(grep "${LOGNAME}:" /etc/oratab | grep -v '#' | awk -F : '{print $7}')

ENVIRON_REF=${HOME}/context/environ.ref
if [ ! -f ${ENVIRON_REF} ]
then
    echo "error: ${ENVIRON_REF} does not exist, exiting"
    exit 1
fi

if grep -q ODI_AGENT_NAME ${ENVIRON_REF}
then
    ODI_AGENT_NAME=$(grep '^ODI_AGENT_NAME' ${ENVIRON_REF} | awk -F '=' '{print $2}')
else
    echo "error: ODI_AGENT_NAME not defined in ${ENVIRON_REF}, exiting"
    exit 1
fi

log_message "--------------------------------------------------------------------------"
env_owner
log_message ""
log_message "log file for this run is \${TMPDIR}/sse_stop_odi_agent_${THIS_RUN}.log"


# ===============================================
# check whether sse_service_status is available
# ===============================================
log_message ""
log_message "--------------------------------------------------------------------------"
log_message "checking whether sse_service_status is available"
log_message ""

SSE_SERVICE_NAME="${LOGNAME}_odi"
#SSE_SERVICE_NAME=$(grep '^SSE_SERVICE_ON_ODI_AGENT' ${ENVIRON_REF} | awk -F '=' '{print $2}')
VALID_SERVICE="false"

if [ "${SSE_SERVICE_NAME}" ]
then
    if sse_service_status ${SSE_SERVICE_NAME} > /dev/null 2>&1
    then
        VALID_SERVICE="true"
        ORIG_SERVICE_STATUS=$(sudo sse_service_status ${SSE_SERVICE_NAME} | grep ${SSE_SERVICE_NAME} | awk '{print $2}')
        log_message "  ${SSE_SERVICE_NAME} service is defined and currently set to ${ORIG_SERVICE_STATUS}"
    else
        log_message "  ${SSE_SERVICE_NAME} service is not defined on this server"
        log_message "  will not attempt to set sse_service_status for ${SSE_SERVICE_NAME}"
    fi
else
    log_message "  there is no sse_service_status definition for odi agent"
fi


# ===============================================
# check  odi agent unix processes
# ===============================================
check_odi_agent_processes

if [ "${FUSION_ODI_AGENT_STATUS}" = "down" ]
then
    set_sse_service_status ${ODI_AGENT_NAME} down
    exit_script 0
fi


# ===============================================
# set sse_service_status to down for odi agent
# ===============================================
set_sse_service_status ${SSE_SERVICE_NAME} down


# =====================================
# stop odi agent
# =====================================
log_message ""
log_message "--------------------------------------------------------------------------"
log_message "stopping odi agent"
log_message ""
log_message "  ODI_AGENT_HOME = ${DOMAIN_HOME}"
log_message ""

ODI_AGENT_HOME=${DOMAIN_HOME}

if [ -f ${ODI_AGENT_HOME}/bin/agentstop.sh ]
then
    log_message "  running \${ODI_AGENT_HOME}/bin/agentstop.sh -NAME=${ODI_AGENT_NAME} "
    log_message "  logfile ${TMPDIR}/agentstop_${ODI_AGENT_NAME}_${THIS_RUN}.log"

    ${ODI_AGENT_HOME}/bin/agentstop.sh -NAME=${ODI_AGENT_NAME}  > ${TMPDIR}/agentstop_${ODI_AGENT_NAME}_${THIS_RUN}.log 2>&1
    ODI_AGENT_STOP_RC=$?

    log_message ""

    if [ ${ODI_AGENT_STOP_RC} -eq 0 ]
    then
        log_message "  command completed ok"
    else
        log_message ""
        log_message "  error: problem detected stopping odi agent, exiting"
        set_sse_service_status ${SSE_SERVICE_NAME} up
        exit_script 1
    fi
else
    log_message ""
    log_message "  error: ${ODI_AGENT_HOME}/bin/agentstop.sh does not exist, exiting"
    exit_script 1
fi


# ===============================================
# wait up to 30 seconds for di agent process to stop
# ===============================================
log_message ""
log_message "--------------------------------------------------------------------------"
log_message "waiting up to 30 seconds for the odi agent process to stop"
log_message ""

(( SLEEP_TIME = 0 ))

ODI_AGENT_PID_COUNT=$(ps -fu ${LOGNAME} | grep -v grep | grep -ic ${ODI_AGENT_NAME})

until [ ${SLEEP_TIME} -eq 30 -o ${ODI_AGENT_PID_COUNT} -eq 0 ]
do
    sleep 1
    (( SLEEP_TIME = ${SLEEP_TIME} + 1 ))
    ODI_AGENT_PID_COUNT=$(ps -fu ${LOGNAME} | grep -v grep | grep -ic ${ODI_AGENT_NAME})
done

log_message "  there are ${ODI_AGENT_PID_COUNT} odi agent processes running"

if [ ${SLEEP_TIME} == 30 ]
then
    log_message ""
    log_message "error: failed to stop odi agent process(es), exiting"
    set_sse_service_status ${SSE_SERVICE_NAME} up
    exit_script 1
fi


# ===============================================
# check odi agent processes
# ===============================================
check_odi_agent_processes

if [ "${ODI_AGENT_STATUS}" = "up" ]
then
    log_message ""
    log_message "  error: failed to stop odi agent process, exiting"
    set_sse_service_status ${SSE_SERVICE_NAME} up
    exit_script 1
fi
  

# ===============================================
# the end
# ===============================================
exit_script 0
