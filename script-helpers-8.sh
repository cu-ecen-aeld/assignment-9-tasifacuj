#!/bin/sh

# Set this with a string describing the validation error(s) if any occur
export validate_error=

# See https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux
RED='\033[0;31m'
NC='\033[0m' # No Color

add_validate_error() {
	validate_error="${validate_error}:$1"
	export validate_error
	printf "${RED}Validation Error:$1${NC}\n"
}


# This function is used to ssh into qemu in order to execute a command fed as parameter
# @parameter1: command to be executed inside qemu.
#       If you need to send more than one parameter, enclose in quotes
ssh_cmd() {
	cmd=$1
	sshpass -p 'root' ssh -o StrictHostKeyChecking=no root@localhost -p 10022 ${cmd}
}

# Add the local file at
#   param1
# to the rootfs of the target at location
#   param2
add_to_rootfs() {
	path_to_file=$1
	rootfs_location=$2
	echo "adding ${path_to_file} to the rootfs at ${rootfs_location}"
	sshpass -p 'root' scp -o StrictHostKeyChecking=no -P  10022 ${path_to_file} root@localhost:${rootfs_location}
}

#This function waits for the qemu to boot up.
wait_for_qemu(){
	ssh-keygen -f "${HOME}/.ssh/known_hosts" -R "[localhost]:10022"
	echo "Waiting for qemu to startup"
	local wait_for_ssh_startup="true"
	while [ $wait_for_ssh_startup == "true" ]; do
	tmpfile=`mktemp`
		ssh_cmd "exit" > ${tmpfile} 2>&1
		rc=$?
		if [ $rc -eq 0 ]; then
			echo "SSH login successful, waiting 40 additional seconds for process startup"
			sleep 40
			wait_for_ssh_startup="false"
		else
			sleep 5
			echo "still waiting for qemu to startup... last attempt returned $rc with output "
			cat ${tmpfile}
		fi
	done
}

validate_driver_assignment7() {
    ssh_cmd lsmod >> result.txt
    if [ $? -eq 0 ]; then
        ssh_cmd "modprobe hello" >> result.txt
        if [ $? -eq 0 ]; then
            ssh_cmd "dmesg | tail -n 3" >> result.txt
        fi
    fi
}


# This function runs runqemu.sh in background and waits for qemu to boot up.
validate_qemu(){
	echo "Executing runqemu.sh in background"

	./runqemu.sh &
	wait_for_qemu
}

# This function copies the testing scripts inside qemu and executes them.
# @parameter1: Absolute Directory path to the testing scripts on the host machine in order to copy them inside qemu.
# @parameter2: Absolute Directory path where the testing scripts need to be copied inside qemu.
# Note: The testing scripts should be copied in the same directory where the executables are stored.
validate_assignment2_checks() {
	script_dir=${1}
	executable_path=${2}

	# scp the scripts required to validate the assignment 1 checks.
	sshpass -p 'root' scp -o StrictHostKeyChecking=no -P 10022 ${script_dir}/assignment-1-test.sh root@localhost:${executable_path}
	sshpass -p 'root' scp -o StrictHostKeyChecking=no -P 10022 ${script_dir}/script-helpers root@localhost:${executable_path}

	ssh_cmd "${executable_path}/assignment-1-test.sh"
	rc=$?
	if [ $rc -ne 0 ]; then
		add_validate_error "Failed to run assignment-1-test script inside qemu"
	fi
}

# This function is used for validating buildroot defconfig file in base_external/configs/aesd_qemu_defconfig file.
validate_buildroot_config() {
	DEFCONFIG_BASE_EXTERNAL=base_external/configs/aesd_qemu_defconfig

	grep -q 'BR2_PACKAGE_DROPBEAR=y' "${DEFCONFIG_BASE_EXTERNAL}"
	rc=$?
	if [ $rc -ne 0 ]; then
		add_validate_error "Dropbear support missing in aesd_qemu_defconfig"
		echo "Adding Dropbear Support manually"
		echo 'BR2_PACKAGE_DROPBEAR=y' >> "${DEFCONFIG_BASE_EXTERNAL}"
	fi

	grep -q 'BR2_PACKAGE_AESD_ASSIGNMENTS=y' "${DEFCONFIG_BASE_EXTERNAL}"
	rc=$?
	if [ $rc -ne 0 ]; then
		add_validate_error "AESD_ASSIGNMENTS package disabled in aesd_qemu_defconfig"
		echo "Adding AESD_ASSIGNMENTS package manually"
		echo 'BR2_PACKAGE_AESD_ASSIGNMENTS=y' >> "${DEFCONFIG_BASE_EXTERNAL}"
	fi

	grep -q 'BR2_TARGET_GENERIC_ROOT_PASSWD="root"' "${DEFCONFIG_BASE_EXTERNAL}"
	rc=$?
	if [ $rc -ne 0 ]; then
		add_validate_error "Root password not added in aesd_qemu_defconfig"
		echo "Setting password to root manually"
		echo 'BR2_TARGET_GENERIC_ROOT_PASSWD="root"' >> "${DEFCONFIG_BASE_EXTERNAL}"
	fi
}



# This function runs sockettest.sh in order to validate aesdsocket functionality.
# @param1: Path to sockettest.sh script
validate_socket() {
	script_dir=$1
	echo "Running sockettest.sh"

	${script_dir}/sockettest.sh -t localhost
	rc=$?
	if [ $rc -ne 0 ]; then
		add_validate_error "sockettest.sh failed for required testcases inside qemu"
	fi
}


# This function runs sockettest_long_string.sh in order to validate aesdsocket functionality for long strings.
# @param1: Path to sockettest_long_string.sh script
validate_socket_long_string() {
	script_dir=$1
	echo "Running sockettest_long_string.sh"
	pushd ${script_dir}
	./sockettest_long_string.sh -t localhost
	rc=$?
	if [ $rc -ne 0 ]; then
		add_validate_error "sockettest_long_string.sh failed for long string inside qemu"
	fi
	popd
}

# This function validates whether aesdsocket runs as a daemon at startup.
# If the aesdsocket does not run at boot up, aesdsocket is run as daemon manually.
validate_socket_daemon() {
	echo "validating aesdsocket daemon task"

	ssh_cmd "ps | grep -v grep| grep /usr/bin/aesdsocket"
	rc=$?
	if [ $rc -ne 0 ]; then
		add_validate_error "aesdsocket does not run as daemon on startup"
		echo "Running aesdsocket as daemon manually"
		ssh_cmd "/usr/bin/aesdsocket -d" &
		sleep 5s
	fi
	sleep 5s
}


# This function validates if the /var/tmp/aesdsocketdata or /var/tmp/aesdsocketdata.txt file has been deleted.
validate_aesdsocketdata_removal() {
	echo "Validating if the file /var/tmp/aesdsocketdata has been deleted"
	if [ -e /var/tmp/aesdsocketdata ] || [ -e /var/tmp/aesdsocketdata.txt ]; then
		add_validate_error "/var/tmp/aesdsocketdata has not been deleted at the end"
		echo "Deleting /var/tmp/aesdsocketdata or /var/tmp/aesdsocketdata.txt"
		rm /var/tmp/aesdsocketdata || rm /var/tmp/aesdsocketdata.txt
	fi
}


# This function validates if the aesdsocket program has implemented a signal handler catching signals SIGTERM and SIGINT
# The aesdsocket program must be running before calling this functions
validate_signal_handlers() {
	echo "validating signal handlers for SIGTERM and SIGINT"

	ssh_cmd 'kill -s 15 $(pidof aesdsocket)'
	ssh_cmd "ps | grep -v grep| grep /usr/bin/aesdsocket"
	rc=$?
	if [ $rc -ne 0 ]; then
		echo "successfully killed using SIGTERM"

		#validating if the textfile has been deleted at the end
		validate_aesdsocketdata_removal
	else
		add_validate_error "Signal handler for SIGTERM cannot terminate aesdsocket"
	fi

	# Running the program again
	echo "Running aesdsocket program again"
	# The below command does not work unless run in background. Can't seem to understand why.
	ssh_cmd "/usr/bin/aesdsocket -d" &
	rc=$?

	sleep 5s

	if [ $rc -eq 0 ]; then
		echo "aesdsocket running"
		ssh_cmd 'kill -s 2 $(pidof /usr/bin/aesdsocket)'
		ssh_cmd "ps | grep -v grep| grep /usr/bin/aesdsocket"
		rc=$?
		if [ $rc -ne 0 ]; then
			echo "successfully killed using SIGINT"

			#validating if the textfile has been deleted at the end
			validate_aesdsocketdata_removal
		else
			add_validate_error "Signal handler for SIGINT cannot terminate aesdsocket"
		fi
	else
		add_validate_error "Could not find aesdsocket in /usr/bin"
	fi
}

## TODO: Recheck this function implementation
validate_error_checks() {
	echo "validating error codes"

	ssh_cmd "/usr/bin/aesdsocket -d" &
	rc=$?
	if [ $rc -eq 0 ]; then
		sleep 5s

		## TODO Check this might get stuck if failed actually
		ssh_cmd "/usr/bin/aesdsocket -d"
		rc=$?
		sleep 5s
		if [ $rc -ne 0 ]; then
			echo "-1 returned for bind error"
		else
			add_validate_error "bind error not handled"
		fi
	ssh_cmd 'kill -9 $(pidof aesdsocket)'
	fi
}

# This function creates the aesdsocket executable and checks for memory leaks using Valgrind.
# The function checks for memeory leaks on host machine after running sockettest.sh and killing it to cover all kinds of memory leaks.
# @param1: Path to sockettest.sh script
validate_makefile_and_memoryleak() {
	script_dir=$1
	valgrind_test=0			# 0 indicates true

	echo "Removing any previous valgrind test output file"
	rm valgrind-out.txt
	echo "validating memory leak using Valgrind"

	commit_id=$(grep "SRCREV" meta-aesd/recipes-aesd-assignments/aesd-assignments/aesd-assignments_git.bb | cut -d'"' -f2)
	short_commit_id=$(echo ${commit_id} | head -c 10)
	MAKEFILE_PATH=build/tmp/work/aarch64-poky-linux/aesd-assignments/1.0+gitAUTOINC+${short_commit_id}-r0/git/

	make clean -C ${MAKEFILE_PATH}
	make -C ${MAKEFILE_PATH} || make all -C ${MAKEFILE_PATH}
	rc=$?
	if [ $rc -ne 0 ]; then
		add_validate_error "Makefile cannot build an executable on host machine"
		add_validate_error "Valgrind test was not implemented on host machine"

		valgrind_test=1		# 1 indicates false
	fi

	if [ $valgrind_test -eq 0 ]; then
		PATH_EXEC=$(find ${MAKEFILE_PATH} -name "aesdsocket")
		valgrind --error-exitcode=1 --leak-check=full --show-leak-kinds=all --track-origins=yes --errors-for-leak-kinds=definite --verbose --log-file=valgrind-out.txt ./${PATH_EXEC}&
		sleep 10s

		# Running sockettest script here to take care of all memory leaks possible
		echo "Running sockettest.sh for Valgrind test"
		#${script_dir}/sockettest.sh -t localhost
		echo "TEST1: testing memory leak string" | nc localhost 9000 -w 1
		echo "TEST2: testing memory leak string" | nc localhost 9000 -w 1
		echo "TEST3: testing memory leak string" | nc localhost 9000 -w 1
		echo "TEST4: testing memory leak string" | nc localhost 9000 -w 1
		echo "TEST5: testing memory leak string" | nc localhost 9000 -w 1


		rc=$?
		if [ $rc -ne 0 ]; then
			add_validate_error "sockettest.sh failed for required testcases on host machine for Valgrind test, could not complete memory leak check"
		fi

		sleep 2s
		ps -aux | grep -v grep | grep "aesdsocket"
		pid_num=$(pidof '/usr/bin/valgrind.bin')
		echo "$pid_num"
		kill -s 2 ${pid_num}
		sleep 5s

		grep -i "no leaks are possible" valgrind-out.txt
		rc=$?
		if [ $rc -eq 0 ]; then
			echo "All memory freed"
			rm valgrind-out.txt
		else
			add_validate_error "Memory leak detected using Valgrind"
		fi
	fi
}

# This function checks for Wall and Werror flags in makefile
validate_makefile_flags() {
	echo "validating makefile Flags"

	commit_id=$(grep "AESD_ASSIGNMENTS_VERSION" base_external/package/aesd-assignments/aesd-assignments.mk | cut -d "=" -f2 | tr -d ' ')
	MAKEFILE_PATH=buildroot/output/build/aesd-assignments-${commit_id}


	grep -is "wall" ${MAKEFILE_PATH}/makefile
	rc=$?
	if [ $rc -ne 0 ]; then
		grep -is "wall" ${MAKEFILE_PATH}/Makefile
		rc=$?
		if [ $rc -ne 0 ]; then
			add_validate_error "wall flag missing in Makefile"
		fi
	fi

	grep -is "Werror" ${MAKEFILE_PATH}/makefile
	rc=$?
	if [ $rc -ne 0 ]; then
		grep -is "Werror" ${MAKEFILE_PATH}/Makefile
		rc=$?
		if [ $rc -ne 0 ]; then
			add_validate_error "Werror flag missing"
		fi
	fi
}



# This function copies the required file to the directory ~/assignment4_build_binaries/<basename ${1}>
# @parameter1: This parameter is the path to the root directory of the github repository.
save_build_binaries() {
	docker_buildroot_shared_dir=/var/aesd/buildroot-shared
	student_folder=$(basename ${1})
	student_folder_path=${docker_buildroot_shared_dir}/students_build_binaries/${student_folder}
	mkdir -p ${student_folder_path}
	echo "Directory consisting of build binaries at ${student_folder_path} created"
	cp buildroot/output/images/Image ${student_folder_path}
       	cp buildroot/output/images/rootfs.ext4 ${student_folder_path}
}


# THIS FUNCTION IS NO LONGER REQUIRED
# This function fetches the output file from qemu to the host machine
fetch_output_file() {
#	for i in $( seq 1 20)
#	do
		ssh_cmd "tester.sh"
		rc=$?
		if [ $rc -eq 0 ]; then
			sshpass -p 'root' scp -P 10022 root@localhost:~/assignments/assignment4/assignment-4-result.txt test_result
			rc=$?
			if [ $rc -ne 0 ]; then
				sshpass -p 'root' scp -P 10022 root@localhost:/root/assignment-4-result.txt test_result
				rc=$?
				if [ $rc -ne 0 ]; then
					add_validate_error "Failed to SCP assignment-4-result.txt from remote !!!"
				fi
			else
				add_validate_error "assignment-4-result.txt found but not located at ~/ Dir"
			fi

			sshpass -p 'root' scp -P 10022 root@localhost:/tmp/ecen5013/ECEN_5013_IS_AWESOME10 test_result
			rc=$?
			if [ $rc -ne 0 ]; then
				sshpass -p 'root' scp -P 10022 root@localhost:/tmp/aesd-data/AESD_IS_AWESOME10 test_result
				rc=$?
				if [ $rc -ne 0 ]; then
					add_validate_error "Failed to SCP ECEN_5013_IS_AWESOME10 from remote !!!"
				fi
			fi

			break;
		fi

#		if [ $i -eq 20 ]; then
#			add_validate_error "Failed to SSH in QEMU !!!"
#		fi
#		sleep 5s
#	done
}


# THIS FUNCTION IS NO LONGER REQUIRED
# This function validates the output file.
validate_output_file() {
	fetch_output_file

	cat test_result/assignment-4-result.txt | grep "The number of files are 10 and the number of matching lines are 10"
	rc=$?
	if [ $rc -ne 0 ]; then
		add_validate_error "Text in assignment4-result.txt file not as expected !!!"
	fi

	cat test_result/ECEN_5013_IS_AWESOME10 | grep "${githubstudent}"
	rc=$?
	if [ $rc -ne 0 ]; then
		cat test_result/AESD_IS_AWESOME10 | grep "${githubstudent}"
		rc=$?
		if [ $rc -ne 0 ]; then
			add_validate_error "Expected Github Usename: ${githubstudent} but found no match"
		fi
	fi

	cat test_result/ECEN_5013_IS_AWESOME10 | grep "1970"
	rc=$?
	if [ $rc -ne 0 ]; then
		cat test_result/AESD_IS_AWESOME10 | grep "${githubstudent}"
		rc=$?
		if [ $rc -ne 0 ]; then
			add_validate_error "Expected EPOCH time but found no match !!!"
		fi
	fi
}

# See logic used for gitlab runners in https://docs.gitlab.com/ee/ci/ssh_keys/#ssh-keys-when-using-the-docker-executor
# We will use this logic in a before_script execution so we can use the same strategy
# inside or outside a docker container
before_script() {
	if [ -n "${SSH_PRIVATE_KEY_BASE64}" ]; then
		# See https://serverfault.com/a/978369
		# Use this to support gitlab CI requirements for environment variable masking
		echo "Converting base64 key"
		SSH_PRIVATE_KEY=`echo ${SSH_PRIVATE_KEY_BASE64} | openssl base64 -A -d`
		SSH_PRIVATE_KEY_BASE64=
	fi

    if [ -z "${SSH_PRIVATE_KEY}" ]; then
        echo "Private key is not set, attempts to clone may fail"
        echo "Or CI environment may have setup SSH authentication already..."
    else
        echo "Setting private key"
        ##
        ## Install ssh-agent if not already installed, it is required by Docker.
        ## (change apt-get to yum if you use an RPM-based image)
        ##
        which ssh-agent || ( apt-get update -y && apt-get install openssh-client -y )

        ##
        ## Run ssh-agent (inside the build environment)
        ##
        eval $(ssh-agent -s)

        set -e
        ##
        ## Add the SSH key stored in SSH_PRIVATE_KEY variable to the agent store
        ## We're using tr to fix line endings which makes ed25519 keys work
        ## without extra base64 encoding.
        ## https://gitlab.com/gitlab-examples/ssh-private-key/issues/1#note_48526556
        ##
        echo "$SSH_PRIVATE_KEY" | tr -d '\r' | ssh-add -
        set +e
        # Now that we don't need the private key anymore zero it out
        export SSH_PRIVATE_KEY=
    fi

    echo "Running as:"
    echo `whoami`
	##
	## Create the SSH directory and give it the right permissions
	##
	mkdir -p ~/.ssh

    # add known host for github
	touch ~/.ssh/known_hosts
	ssh-keyscan github.com >> ~/.ssh/known_hosts
    echo "Added known host github.com:"
}

# Validate the assignment 6 implementation against a running qemu instance
# This means making sure we can run sockettest.sh against qemu after startup
validate_assignment5_qemu() {
	script_dir=${1}
    pushd ${script_dir}
    ./sockettest.sh
    rc=$?
    if [ $rc -ne 0 ]; then
        add_validate_error "sockettest.sh returned $rc attempting to run against qemu instance"
    fi
    popd
}


# Validate the assignment 6 implementation against a running qemu instance
# This means making sure we can run sockettest.sh against qemu after startup
validate_assignment6_qemu() {
    validate_assignment5_qemu $@
}

# First argument: The marker file to remove when exiting
valgrind_assignment6_assignment5() {
    valgrind_marker=$1
    echo "Starting valgrind"
    valgrind --error-exitcode=1 --leak-check=full --show-leak-kinds=all --track-origins=yes --errors-for-leak-kinds=definite --verbose --log-file=valgrind-out.txt ./aesdsocket
    rc=$?
    echo "Valgrind and aesdsocket complete"
    if [ $rc -ne 0 ]; then
        add_validate_error "Valgrind failed with $rc"
        echo "Valgrind output error log:"
        cat valgrind-out.txt
    fi
    echo deleting marker file $valgrind_marker
    rm $valgrind_marker
}

assignment6_assignment5_run_valgrind()
{
	echo "Waiting for aesdsocket application with pid $PID to terminate"
    wait_exit=1
    while [ $wait_exit -ne 0 ]; do
        kill -0 ${PID}
        wait_exit=$?
        if [ $wait_exit -ne 0 ]; then
            ps -q $PID | grep "defunct"
            wait_exit=$?
            if [ $wait_exit -ne 0 ]; then
                echo "aesdsocket still running"
                sleep 1
            fi
        fi
    done

    echo "Re-running sockettest.sh with valgrind"
    pushd ${source_dir}
    valgrind_marker=$(mktemp)
    valgrind_assignment6_assignment5 $valgrind_marker &
    pushd ${script_dir}
}

# Validate the assignment 5 implementation against native code
# This means compiling natively, then starting aesdsocket as daemon, then
# running sockettest.sh against the running instance
# Arguments: 1) The script directory containing the sockettest executable
#            2) The source directory containing the aesdsocket makefile and output file
validate_assignment5_native() {
	script_dir=${1}
    source_dir=${2}
    pushd ${source_dir}
    make clean && make
    rc=$?
    if [ $rc -ne 0 ]; then
        add_validate_error "make returned $rc attempting to build native application"
    fi
    ./aesdsocket -d
    rc=$?
    if [ $rc -ne 0 ]; then
        add_validate_error "starting aesdocket failed with $rc"
    fi
    pushd ${script_dir}
    ./sockettest.sh
    rc=$?
    if [ $rc -ne 0 ]; then
        add_validate_error "sockettest.sh returned $rc attempting to run against native compiled aesdsocket instance"
    fi
	PID=$(pgrep aesdsocket)
    kill $PID
    popd
    popd
	assignment6_assignment5_run_valgrind
    echo "Waiting for aesdsocket application to start"
    sleep 3
    ./sockettest.sh
    rc=$?
    if [ $rc -ne 0 ]; then
        add_validate_error "sockettest.sh returned $rc attempting to run against native compiled aesdsocket instance running under valgrind"
    fi
    PID=$(pgrep -f "valgrind.*aesdsocket")
    echo "Stopping valgrind and aesdsocket process at pid $PID"
    kill $PID
    while [ -f $valgrind_marker ]; do
        echo "Waiting for aesdsocket and valgrind to exit"
        sleep 1
    done
}

# Validate the assignment 6 implementation against native code
# This means compiling natively, then starting aesdsocket as daemon, then
# running sockettest.sh against the running instance
# Arguments: 1) The script directory containing the sockettest executable
#            2) The source directory containing the aesdsocket application source code and makefile
validate_assignment6_native() {
    script_dir=${1}
    source_dir=${2}
    pushd ${source_dir}
    make clean && make
    rc=$?
    if [ $rc -ne 0 ]; then
        add_validate_error "make returned $rc attempting to build native application"
    fi
    ./aesdsocket -d
    rc=$?
    if [ $rc -ne 0 ]; then
        add_validate_error "starting aesdocket failed with $rc"
    fi
    pushd ${script_dir}
    ./sockettest.sh
    rc=$?
    if [ $rc -ne 0 ]; then
        add_validate_error "sockettest.sh returned $rc attempting to run against native compiled aesdsocket instance"
    fi
    PID=$(pgrep aesdsocket)
    kill $PID
    popd
    popd

	assignment6_assignment5_run_valgrind
    while [ 1 ]; do
       # Write timestamp: while waiting for start since these get filtered out during the diff check
       echo "timestamp:wait-for-startup" | nc localhost 9000 -w 1 | grep "timestamp:wait-for-startup"
       if [ $? -eq 0 ]; then
           break;
       fi
       echo "Waiting for aesdsocket application to start"
       sleep 1
    done
    ./sockettest.sh
    rc=$?
    if [ $rc -ne 0 ]; then
        add_validate_error "sockettest.sh returned $rc attempting to run against native compiled aesdsocket instance running under valgrind"
    fi
    PID=$(pgrep -f "valgrind.*aesdsocket")
    echo "Stopping valgrind and aesdsocket process at pid $PID"
    kill $PID
    while [ -f $valgrind_marker ]; do
        echo "Waiting for aesdsocket and valgrind to exit"
        sleep 1
    done
}

validate_assignment7_qemu() {
	echo "Validating assignment 7 in QEMU"

    validate_driver_assignment7

	cat result.txt | grep "hello"
	if [ $? -ne 0 ]; then
		add_validate_error "hello module not loaded on boot !!!"
	fi

	cat result.txt | grep "faulty"
	if [ $? -ne 0 ]; then
		add_validate_error "faulty module not loaded on boot !!!"
	fi

	cat result.txt | grep "scull"
	if [ $? -ne 0 ]; then
		add_validate_error "scull module not loaded on boot !!!"
	fi

	cat result.txt | grep "${githubstudent}"
	if [ $? -ne 0 ]; then
		add_validate_error "Github Username not found in hello module !!!"
	fi

	rm -f result.txt
}

validate_aesdchar() {
        echo "Adding and removing aesdchar driver"
		ssh_cmd "lsmod | grep \"aesdchar\""
		if [ $? -eq 0 ]; then
		    ssh_cmd "rmmod aesdchar"
        else
		    add_validate_error "aesdchar driver not loaded at startup"
		fi
		ssh_cmd "modprobe aesdchar"

}
validate_driver_assignment8() {

       	echo "Validation of driver"

		validate_aesdchar
       	ssh_cmd "test -f /usr/bin/drivertest.sh"
        if [ $? -eq 0 ]; then
                ssh_cmd "/usr/bin/drivertest.sh"
                if [ $? -ne 0 ]; then
                        add_validate_error "Driver test failed"
                fi

        else
                add_validate_error "drivertest - not present in /usr/bin"
        fi
}

validate_application_assignment8() {
        script_dir=$1
       	echo "Validation of aesdsocket"

		validate_aesdchar

       	ssh_cmd "ps | grep -v grep| grep aesdsocket"
        if [ $? -ne 0 ]; then
                add_validate_error "Socket application is not running on boot"
                ssh_cmd "test -f /usr/bin/aesdsocket"
                if [ $? -ne 0 ]; then
                    add_validate_error "aesdsocket missing from the filesystem"
                fi
        fi

        ${script_dir}/sockettest.sh
        if [ $? -ne 0 ]; then
                add_validate_error "sockettest.sh failed"
        fi
}


validate_driver_assignment9() {
    validate_driver_assignment8
}

validate_application_assignment9() {
    validate_application_assignment8 "$@"
}
