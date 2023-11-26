#!/bin/bash
# start.sh

set -e

# The _log function is used for everything this script wants to log.
# It will always log errors and warnings but can be silenced for other messages
# by setting the BROADSEA_QUIET environment variable.
_log () {
    if [[ "$*" == "ERROR:"* ]] || [[ "$*" == "WARNING:"* ]] || [[ "${BROADSEA_QUIET}" == "" ]]; then
        echo "$@"
    fi
}
_log "Entered start.sh with args:" "$@"

# A helper function to unset env vars listed in the value of the env var
# JUPYTER_ENV_VARS_TO_UNSET.
unset_explicit_env_vars () {
    if [ -n "${JUPYTER_ENV_VARS_TO_UNSET}" ]; then
        for env_var_to_unset in $(echo "${JUPYTER_ENV_VARS_TO_UNSET}" | tr ',' ' '); do
            _log "Unset ${env_var_to_unset} due to JUPYTER_ENV_VARS_TO_UNSET"
            unset "${env_var_to_unset}"
        done
        unset JUPYTER_ENV_VARS_TO_UNSET
    fi
}


# Default to starting bash if no command was specified
if [ $# -eq 0 ]; then
    cmd=( "bash" )
else
    cmd=( "$@" )
fi

# NOTE: This hook will run as the user the container was started with!
# shellcheck disable=SC1091
source /usr/local/bin/run-hooks.sh /usr/local/bin/start-notebook.d

# If the container started as the root user, then we have permission to refit
# the Odysseus user, and ensure file permissions, grant sudo rights, and such
# things before we run the command passed to start.sh as the desired user
# (OHDSI_USER).
#
if [ "$(id -u)" == 0 ]; then
    # Environment variables:
    # - OHDSI_USER: the desired username and associated home folder
    # - OHDSI_UID: the desired user id
    # - OHDS_GID: a group id we want our user to belong to
    # - OHDSI_GROUP: a group name we want for the group
    # - GRANT_SUDO: a boolean ("1" or "yes") to grant the user sudo rights
    # - CHOWN_HOME: a boolean ("1" or "yes") to chown the user's home folder
    # - CHOWN_EXTRA: a comma-separated list of paths to chown
    # - CHOWN_HOME_OPTS / CHOWN_EXTRA_OPTS: arguments to the chown commands

    # Refit the Odysseus user to the desired user (OHDSI_USER)
    if id Odysseus &> /dev/null; then
        if ! usermod --home "/home/${OHDSI_USER}" --login "${OHDSI_USER}" Odysseus 2>&1 | grep "no changes" > /dev/null; then
            _log "Updated the Odysseus user:"
            _log "- username: Odysseus       -> ${OHDSI_USER}"
            _log "- home dir: /home/Odysseus -> /home/${OHDSI_USER}"
        fi
    elif ! id -u "${OHDSI_USER}" &> /dev/null; then
        _log "ERROR: Neither the Odysseus user nor '${OHDSI_USER}' exists. This could be the result of stopping and starting, the container with a different OHDSI_USER environment variable."
        exit 1
    fi
    # Ensure the desired user (OHDSI_USER) gets its desired user id (OHDSI_UID) and is
    # a member of the desired group (OHDSI_GROUP, OHDS_GID)
    if [ "${OHDSI_UID}" != "$(id -u "${OHDSI_USER}")" ] || [ "${OHDS_GID}" != "$(id -g "${OHDSI_USER}")" ]; then
        _log "Update ${OHDSI_USER}'s UID:GID to ${OHDSI_UID}:${OHDS_GID}"
        # Ensure the desired group's existence
        if [ "${OHDS_GID}" != "$(id -g "${OHDSI_USER}")" ]; then
            groupadd --force --gid "${OHDS_GID}" --non-unique "${OHDSI_GROUP:-${OHDSI_USER}}"
        fi
        # Recreate the desired user as we want it
        userdel "${OHDSI_USER}"
        useradd --no-log-init --home "/home/${OHDSI_USER}" --shell /bin/bash --uid "${OHDSI_UID}" --gid "${OHDS_GID}" --groups 100 "${OHDSI_USER}"
    fi

    # Move or symlink the Odysseus home directory to the desired user's home
    # directory if it doesn't already exist, and update the current working
    # directory to the new location if needed.
    if [[ "${OHDSI_USER}" != "Odysseus" ]]; then
        if [[ ! -e "/home/${OHDSI_USER}" ]]; then
            _log "Attempting to copy /home/Odysseus to /home/${OHDSI_USER}..."
            mkdir "/home/${OHDSI_USER}"
            if cp -a /home/Odysseus/. "/home/${OHDSI_USER}/"; then
                _log "Success!"
            else
                _log "Failed to copy data from /home/Odysseus to /home/${OHDSI_USER}!"
                _log "Attempting to symlink /home/Odysseus to /home/${OHDSI_USER}..."
                if ln -s /home/Odysseus "/home/${OHDSI_USER}"; then
                    _log "Success creating symlink!"
                else
                    _log "ERROR: Failed copy data from /home/Odysseus to /home/${OHDSI_USER} or to create symlink!"
                    exit 1
                fi
            fi
        fi
        # Ensure the current working directory is updated to the new path
        if [[ "${PWD}/" == "/home/Odysseus/"* ]]; then
            new_wd="/home/${OHDSI_USER}/${PWD:13}"
            _log "Changing working directory to ${new_wd}"
            cd "${new_wd}"
        fi
    fi

    # Optionally ensure the desired user gets filesystem ownership of its home
    # folder and/or additional folders
    if [[ "${CHOWN_HOME}" == "1" || "${CHOWN_HOME}" == "yes" ]]; then
        _log "Ensuring /home/${OHDSI_USER} is owned by ${OHDSI_UID}:${OHDS_GID} ${CHOWN_HOME_OPTS:+(chown options: ${CHOWN_HOME_OPTS})}"
        # shellcheck disable=SC2086
        chown ${CHOWN_HOME_OPTS} "${OHDSI_UID}:${OHDS_GID}" "/home/${OHDSI_USER}"
    fi
    if [ -n "${CHOWN_EXTRA}" ]; then
        for extra_dir in $(echo "${CHOWN_EXTRA}" | tr ',' ' '); do
            _log "Ensuring ${extra_dir} is owned by ${OHDSI_UID}:${OHDS_GID} ${CHOWN_EXTRA_OPTS:+(chown options: ${CHOWN_EXTRA_OPTS})}"
            # shellcheck disable=SC2086
            chown ${CHOWN_EXTRA_OPTS} "${OHDSI_UID}:${OHDS_GID}" "${extra_dir}"
        done
    fi

    # Prepend ${CONDA_DIR}/bin to sudo secure_path
    sed -r "s#Defaults\s+secure_path\s*=\s*\"?([^\"]+)\"?#Defaults secure_path=\"${CONDA_DIR}/bin:\1\"#" /etc/sudoers | grep secure_path > /etc/sudoers.d/path

    # Optionally grant passwordless sudo rights for the desired user
    if [[ "$GRANT_SUDO" == "1" || "$GRANT_SUDO" == "yes" ]]; then
        _log "Granting ${OHDSI_USER} passwordless sudo rights!"
        echo "${OHDSI_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/added-by-start-script
    fi

    # NOTE: This hook is run as the root user!
    # shellcheck disable=SC1091
    source /usr/local/bin/run-hooks.sh /usr/local/bin/before-notebook.d
    unset_explicit_env_vars

    _log "Running as ${OHDSI_USER}:" "${cmd[@]}"
    exec sudo --preserve-env --set-home --user "${OHDSI_USER}" \
        LD_LIBRARY_PATH="${LD_LIBRARY_PATH}" \
        PATH="${PATH}" \
        PYTHONPATH="${PYTHONPATH:-}" \
        "${cmd[@]}"
        # Notes on how we ensure that the environment that this container is started
        # with is preserved (except vars listed in JUPYTER_ENV_VARS_TO_UNSET) when
        # we transition from running as root to running as OHDSI_USER.
        #
        # - We use `sudo` to execute the command as OHDSI_USER. What then
        #   happens to the environment will be determined by configuration in
        #   /etc/sudoers and /etc/sudoers.d/* as well as flags we pass to the sudo
        #   command. The behavior can be inspected with `sudo -V` run as root.
        #
        #   ref: `man sudo`    https://linux.die.net/man/8/sudo
        #   ref: `man sudoers` https://www.sudo.ws/docs/man/sudoers.man/
        #
        # - We use the `--preserve-env` flag to pass through most environment
        #   variables, but understand that exceptions are caused by the sudoers
        #   configuration: `env_delete` and `env_check`.
        #
        # - We use the `--set-home` flag to set the HOME variable appropriately.
        #
        # - To reduce the default list of variables deleted by sudo, we could have
        #   used `env_delete` from /etc/sudoers. It has a higher priority than the
        #   `--preserve-env` flag and the `env_keep` configuration.
        #
        # - We preserve LD_LIBRARY_PATH, PATH and PYTHONPATH explicitly. Note however that sudo
        #   resolves `${cmd[@]}` using the "secure_path" variable we modified
        #   above in /etc/sudoers.d/path. Thus PATH is irrelevant to how the above
        #   sudo command resolves the path of `${cmd[@]}`. The PATH will be relevant
        #   for resolving paths of any subprocesses spawned by `${cmd[@]}`.

# The container didn't start as the root user, so we will have to act as the
# user we started as.
else
    # Warn about misconfiguration of: granting sudo rights
    if [[ "${GRANT_SUDO}" == "1" || "${GRANT_SUDO}" == "yes" ]]; then
        _log "WARNING: container must be started as root to grant sudo permissions!"
    fi

    Odysseus_UID="$(id -u Odysseus 2>/dev/null)"  # The default UID for the Odysseus user
    Odysseus_GID="$(id -g Odysseus 2>/dev/null)"  # The default GID for the Odysseus user

    # Attempt to ensure the user uid we currently run as has a named entry in
    # the /etc/passwd file, as it avoids software crashing on hard assumptions
    # on such entry. Writing to the /etc/passwd was allowed for the root group
    # from the Dockerfile during the build.
    #
    # ref: https://github.com/jupyter/docker-stacks/issues/552
    if ! whoami &> /dev/null; then
        _log "There is no entry in /etc/passwd for our UID=$(id -u). Attempting to fix..."
        if [[ -w /etc/passwd ]]; then
            _log "Renaming old Odysseus user to nayvoj ($(id -u Odysseus):$(id -g Odysseus))"

            # We cannot use "sed --in-place" since sed tries to create a temp file in
            # /etc/ and we may not have write access. Apply sed on our own temp file:
            sed --expression="s/^Odysseus:/nayvoj:/" /etc/passwd > /tmp/passwd
            echo "${OHDSI_USER}:x:$(id -u):$(id -g):,,,:/home/Odysseus:/bin/bash" >> /tmp/passwd
            cat /tmp/passwd > /etc/passwd
            rm /tmp/passwd

            _log "Added new ${OHDSI_USER} user ($(id -u):$(id -g)). Fixed UID!"

            if [[ "${OHDSI_USER}" != "Odysseus" ]]; then
                _log "WARNING: user is ${OHDSI_USER} but home is /home/Odysseus. You must run as root to rename the home directory!"
            fi
        else
            _log "WARNING: unable to fix missing /etc/passwd entry because we don't have write permission. Try setting gid=0 with \"--user=$(id -u):0\"."
        fi
    fi

    # Warn about misconfiguration of: desired username, user id, or group id.
    # A misconfiguration occurs when the user modifies the default values of
    # OHDSI_USER, OHDSI_UID, or OHDS_GID, but we cannot update those values because we
    # are not root.
    if [[ "${OHDSI_USER}" != "Odysseus" && "${OHDSI_USER}" != "$(id -un)" ]]; then
        _log "WARNING: container must be started as root to change the desired user's name with OHDSI_USER=\"${OHDSI_USER}\"!"
    fi
    if [[ "${OHDSI_UID}" != "${Odysseus_UID}" && "${OHDSI_UID}" != "$(id -u)" ]]; then
        _log "WARNING: container must be started as root to change the desired user's id with OHDSI_UID=\"${OHDSI_UID}\"!"
    fi
    if [[ "${OHDS_GID}" != "${Odysseus_GID}" && "${OHDS_GID}" != "$(id -g)" ]]; then
        _log "WARNING: container must be started as root to change the desired user's group id with OHDS_GID=\"${OHDS_GID}\"!"
    fi

    # Warn if the user isn't able to write files to ${HOME}
    if [[ ! -w /home/Odysseus ]]; then
        _log "WARNING: no write access to /home/Odysseus. Try starting the container with group 'users' (100), e.g. using \"--group-add=users\"."
    fi

    # NOTE: This hook is run as the user we started the container as!
    # shellcheck disable=SC1091
    source /usr/local/bin/run-hooks.sh /usr/local/bin/before-notebook.d
    unset_explicit_env_vars

    _log "Executing the command:" "${cmd[@]}"
    exec "${cmd[@]}"
fi