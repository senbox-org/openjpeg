#!/bin/bash

# This script executes the script step when running under travis-ci

# Set-up some bash options
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o pipefail  ## Fail on error in pipe

if [ "${OPJ_CI_DOCKER:-}" == "true" ]; then
    echo "Building inside docker container..."

    # run this script inside the docker container
    # - mount home from the host to the same place on the container
    # - forward env. var. from this script to the docker daemon (except OPJ_CI_DOCKER !)

    # Forward OPJ_ specific vars
    for envvar in OPJ_CI_ARCH OPJ_CI_BUILD_CONFIGURATION OPJ_CI_BUILD_SHARED_LIBS OPJ_CI_CPACK_SYSTEM_NAME ; do
        echo $envvar=${!envvar} >> dockerenv
    done

    # Forward TRAVIS env. var.
    for envvar in TRAVIS_BRANCH TRAVIS_BUILD_DIR TRAVIS_BUILD_ID TRAVIS_BUILD_NUMBER TRAVIS_COMMIT TRAVIS_COMMIT_RANGE TRAVIS_JOB_ID TRAVIS_JOB_NUMBER TRAVIS_OS_NAME TRAVIS_PULL_REQUEST TRAVIS_REPO_SLUG TRAVIS_SECURE_ENV_VARS TRAVIS_TAG ; do
        echo $envvar=${!envvar} >> dockerenv
    done

    echo CC=/usr/bin/gcc >> dockerenv
    
    echo "The following env.var. are forwarded to docker :"
    cat dockerenv

    echo "Starting docker run..."
    docker run --rm=true --env-file=dockerenv -v $HOME:$HOME:rw jmk/centosbuilder /bin/bash -c "cd $TRAVIS_BUILD_DIR && ./tools/travis-ci/run.sh"
    exit $?
fi

#if cygwin, check path
case ${MACHTYPE} in
	*cygwin*) OPJ_CI_IS_CYGWIN=1;;
	*) ;;
esac

# Hack for appveyor to get GNU find in path before windows one.
export PATH=$(dirname ${BASH}):$PATH

function opjpath ()
{
	if [ "${OPJ_CI_IS_CYGWIN:-}" == "1" ]; then
		cygpath $1 "$2"
	else
		echo "$2"
	fi
}

# ABI check is done by abi-check.sh
if [ "${OPJ_CI_ABI_CHECK:-}" == "1" ]; then
	exit 0
fi

# Set-up some variables
if [ "${OPJ_CI_BUILD_CONFIGURATION:-}" == "" ]; then
	export OPJ_CI_BUILD_CONFIGURATION=Release #default
fi
OPJ_SOURCE_DIR=$(cd $(dirname $0)/../.. && pwd)

if [ "${OPJ_DO_SUBMIT:-}" == "" ]; then
	OPJ_DO_SUBMIT=0 # Do not flood cdash by default
fi
if [ "${TRAVIS_REPO_SLUG:-}" != "" ]; then
	OPJ_OWNER=$(echo "${TRAVIS_REPO_SLUG}" | sed 's/\(^.*\)\/.*/\1/')
	OPJ_SITE="${OPJ_OWNER}.travis-ci.org"
	if [ "${OPJ_OWNER}" == "uclouvain" ]; then
		OPJ_DO_SUBMIT=1
	fi
elif [ "${APPVEYOR_REPO_NAME:-}" != "" ]; then
	OPJ_OWNER=$(echo "${APPVEYOR_REPO_NAME}" | sed 's/\(^.*\)\/.*/\1/')
	OPJ_SITE="${OPJ_OWNER}.appveyor.com"
	if [ "${OPJ_OWNER}" == "uclouvain" ]; then
		OPJ_DO_SUBMIT=1
	fi
else
	OPJ_SITE="$(hostname)"
fi

if [ "${TRAVIS_OS_NAME:-}" == "" ]; then
  # Let's guess OS for testing purposes
	echo "Guessing OS"
	if uname -s | grep -i Darwin &> /dev/null; then
		TRAVIS_OS_NAME=osx
	elif uname -s | grep -i Linux &> /dev/null; then
		TRAVIS_OS_NAME=linux
		if [ "${CC:-}" == "" ]; then
			# default to gcc
			export CC=gcc
		fi
	elif uname -s | grep -i CYGWIN &> /dev/null; then
		TRAVIS_OS_NAME=windows
	elif uname -s | grep -i MINGW &> /dev/null; then
		TRAVIS_OS_NAME=windows
	elif [ "${APPVEYOR:-}" == "True" ]; then
		TRAVIS_OS_NAME=windows
	else
		echo "Failed to guess OS"; exit 1
	fi
	echo "${TRAVIS_OS_NAME}"
fi

if [ "${TRAVIS_OS_NAME}" == "osx" ]; then
	OPJ_OS_NAME=$(sw_vers -productName | tr -d ' ')$(sw_vers -productVersion | sed 's/\([^0-9]*\.[0-9]*\).*/\1/')
	OPJ_CC_VERSION=$(xcodebuild -version | grep -i xcode)
	OPJ_CC_VERSION=xcode${OPJ_CC_VERSION:6}
elif [ "${TRAVIS_OS_NAME}" == "linux" ]; then
	OPJ_OS_NAME=linux
	if which lsb_release > /dev/null; then
		OPJ_OS_NAME=$(lsb_release -si)$(lsb_release -sr | sed 's/\([^0-9]*\.[0-9]*\).*/\1/')
	fi
	if [ -z "${CC##*gcc*}" ]; then
		OPJ_CC_VERSION=$(${CC} --version | head -1 | sed 's/.*\ \([0-9.]*[0-9]\)/\1/')
		if [ -z "${CC##*mingw*}" ]; then
			OPJ_CC_VERSION=mingw${OPJ_CC_VERSION}
			# disable testing for now
			export OPJ_CI_SKIP_TESTS=1
		else
			OPJ_CC_VERSION=gcc${OPJ_CC_VERSION}
		fi
	elif [ -z "${CC##*clang*}" ]; then
		OPJ_CC_VERSION=clang$(${CC} --version | grep version | sed 's/.*version \([^0-9.]*[0-9.]*\).*/\1/')
	else
		echo "Compiler not supported: ${CC}"; exit 1
	fi
elif [ "${TRAVIS_OS_NAME}" == "windows" ]; then
	OPJ_OS_NAME=windows
	if which cl > /dev/null; then
		OPJ_CL_VERSION=$(cl 2>&1 | grep Version | sed 's/.*Version \([0-9]*\).*/\1/')
		if [ ${OPJ_CL_VERSION} -eq 19 ]; then
			OPJ_CC_VERSION=vs2015
		elif [ ${OPJ_CL_VERSION} -eq 18 ]; then
			OPJ_CC_VERSION=vs2013
		elif [ ${OPJ_CL_VERSION} -eq 17 ]; then
			OPJ_CC_VERSION=vs2012
		elif [ ${OPJ_CL_VERSION} -eq 16 ]; then
			OPJ_CC_VERSION=vs2010
		elif [ ${OPJ_CL_VERSION} -eq 15 ]; then
			OPJ_CC_VERSION=vs2008
		elif [ ${OPJ_CL_VERSION} -eq 14 ]; then
			OPJ_CC_VERSION=vs2005
		else
			OPJ_CC_VERSION=vs????
		fi
	fi
else
	echo "OS not supported: ${TRAVIS_OS_NAME}"; exit 1
fi

if [ "${OPJ_CI_ARCH:-}" == "" ]; then
	echo "Guessing build architecture"
	MACHINE_ARCH=$(uname -m)
	if [ "${MACHINE_ARCH}" == "x86_64" ]; then
		export OPJ_CI_ARCH=x86_64
	fi
	echo "${OPJ_CI_ARCH}"
fi

if [ "${TRAVIS_BRANCH:-}" == "" ]; then
	if [ "${APPVEYOR_REPO_BRANCH:-}" != "" ]; then
		TRAVIS_BRANCH=${APPVEYOR_REPO_BRANCH}
	else
		echo "Guessing branch"
		TRAVIS_BRANCH=$(git -C ${OPJ_SOURCE_DIR} branch | grep '*' | tr -d '*[[:blank:]]')
	fi
fi

OPJ_BUILDNAME=${OPJ_OS_NAME}-${OPJ_CC_VERSION}-${OPJ_CI_ARCH}-${TRAVIS_BRANCH}
OPJ_BUILDNAME_TEST=${OPJ_OS_NAME}-${OPJ_CC_VERSION}-${OPJ_CI_ARCH}
if [ "${TRAVIS_PULL_REQUEST:-}" != "false" ] && [ "${TRAVIS_PULL_REQUEST:-}" != "" ]; then
	OPJ_BUILDNAME=${OPJ_BUILDNAME}-pr${TRAVIS_PULL_REQUEST}
elif [ "${APPVEYOR_PULL_REQUEST_NUMBER:-}" != "" ]; then
	OPJ_BUILDNAME=${OPJ_BUILDNAME}-pr${APPVEYOR_PULL_REQUEST_NUMBER}
fi
OPJ_BUILDNAME=${OPJ_BUILDNAME}-${OPJ_CI_BUILD_CONFIGURATION}-3rdP
OPJ_BUILDNAME_TEST=${OPJ_BUILDNAME_TEST}-${OPJ_CI_BUILD_CONFIGURATION}-3rdP
if [ "${OPJ_CI_ASAN:-}" == "1" ]; then
	OPJ_BUILDNAME=${OPJ_BUILDNAME}-ASan
	OPJ_BUILDNAME_TEST=${OPJ_BUILDNAME_TEST}-ASan
fi

if [ "${OPJ_NONCOMMERCIAL:-}" == "1" ] && [ "${OPJ_CI_SKIP_TESTS:-}" != "1" ] && [ -d kdu ]; then
	echo "
Testing will use Kakadu trial binaries. Here's the copyright notice from kakadu:
Copyright is owned by NewSouth Innovations Pty Limited, commercial arm of the UNSW Australia in Sydney.
You are free to trial these executables and even to re-distribute them,
so long as such use or re-distribution is accompanied with this copyright notice and is not for commercial gain.
Note: Binaries can only be used for non-commercial purposes.
"
fi

if [ -d cmake-install ]; then
	export PATH=${PWD}/cmake-install/bin:${PATH}
fi

set -x
# This will print configuration
# travis-ci doesn't dump cmake version in system info, let's print it 
cmake --version

# Ensure cpack is installed and dump its version
cpack --version

export TRAVIS_OS_NAME="${TRAVIS_OS_NAME}"
export OPJ_SITE="${OPJ_SITE}"
export OPJ_BUILDNAME="${OPJ_BUILDNAME}"
export OPJ_SOURCE_DIR="$(opjpath -m ${OPJ_SOURCE_DIR})"
export OPJ_BINARY_DIR="$(opjpath -m ${PWD}/build)"
export OPJ_BUILD_CONFIGURATION="${OPJ_CI_BUILD_CONFIGURATION}"
export OPJ_BUILD_SHARED_LIBS="${OPJ_CI_BUILD_SHARED_LIBS:-}"
export OPJ_DO_SUBMIT="${OPJ_DO_SUBMIT}"
export OPJ_CPACK_SYSTEM_NAME="${OPJ_CI_CPACK_SYSTEM_NAME:-}"

ctest -S ${OPJ_SOURCE_DIR}/tools/ctest_scripts/travis-ci.cmake -VV || true
# ctest will exit with various error codes depending on version.
# ignore ctest exit code & parse this ourselves

set +x

# let's parse configure/build/tests for failure

echo "
Parsing logs for failures
"
OPJ_CI_RESULT=0

# 1st configure step
OPJ_CONFIGURE_XML=$(find build -path 'build/Testing/*' -name 'Configure.xml')
if [ ! -f "${OPJ_CONFIGURE_XML}" ]; then
	echo "No configure log found"
	OPJ_CI_RESULT=1
else
	if ! grep '<ConfigureStatus>0</ConfigureStatus>' ${OPJ_CONFIGURE_XML} &> /dev/null; then
		echo "Errors were found in configure log"
		OPJ_CI_RESULT=1
	fi
fi

# 2nd build step
# We must have one Build.xml file
OPJ_BUILD_XML=$(find build -path 'build/Testing/*' -name 'Build.xml')
if [ ! -f "${OPJ_BUILD_XML}" ]; then
	echo "No build log found"
	OPJ_CI_RESULT=1
else
	if grep '<Error>' ${OPJ_BUILD_XML} &> /dev/null; then
		echo "Errors were found in build log"
		OPJ_CI_RESULT=1
	fi
fi

if [ ${OPJ_CI_RESULT} -ne 0 ]; then
	# Don't trash output with failing tests when there are configure/build errors
	exit ${OPJ_CI_RESULT}
fi

if [ "${OPJ_CI_SKIP_TESTS:-}" != "1" ]; then
	OPJ_TEST_XML=$(find build -path 'build/Testing/*' -name 'Test.xml')
	if [ ! -f "${OPJ_TEST_XML}" ]; then
		echo "No test log found"
		OPJ_CI_RESULT=1
	else
		echo "Parsing tests for new/unknown failures"
		# 3rd test step
		OPJ_FAILEDTEST_LOG=$(find build -path 'build/Testing/Temporary/*' -name 'LastTestsFailed_*.log')
		if [ -f "${OPJ_FAILEDTEST_LOG}" ]; then
			awk -F: '{ print $2 }' ${OPJ_FAILEDTEST_LOG} > failures.txt
			while read FAILEDTEST; do
				# Start with common errors
				if grep -x "${FAILEDTEST}" $(opjpath -u ${OPJ_SOURCE_DIR})/tools/travis-ci/knownfailures-all.txt > /dev/null; then
					continue
				fi
				if [ -f $(opjpath -u ${OPJ_SOURCE_DIR})/tools/travis-ci/knownfailures-${OPJ_BUILDNAME_TEST}.txt ]; then
					if grep -x "${FAILEDTEST}" $(opjpath -u ${OPJ_SOURCE_DIR})/tools/travis-ci/knownfailures-${OPJ_BUILDNAME_TEST}.txt > /dev/null; then
						continue
					fi
				fi
				echo "${FAILEDTEST}"
				OPJ_CI_RESULT=1
			done < failures.txt
		fi
	fi
	
	if [ ${OPJ_CI_RESULT} -eq 0 ]; then
		echo "No new/unknown test failure found
		"
	else
		echo "
New/unknown test failure found!!!
	"
	fi
	
	# 4th memcheck step
	OPJ_MEMCHECK_XML=$(find build -path 'build/Testing/*' -name 'DynamicAnalysis.xml')
	if [ -f "${OPJ_MEMCHECK_XML}" ]; then
		if grep '<Defect Type' ${OPJ_MEMCHECK_XML} 2> /dev/null; then
			echo "Errors were found in dynamic analysis log"
			OPJ_CI_RESULT=1
		fi
	fi
fi

exit ${OPJ_CI_RESULT}
