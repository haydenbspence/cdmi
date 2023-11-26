# Use Ubuntu 22.04 (jammy) as the base image
ARG ROOT_CONTAINER=ubuntu:22.04
FROM $ROOT_CONTAINER

LABEL maintainer="Hayden Spence <haydenbspence@gmail.com>"

ARG OHDSI_USER="Odysseus"
ARG OHDSI_UID="1000"
ARG OHDSI_GID="100"

# Set the shell to use and switch to the root user
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
USER root

# Set environment variables and perform initial system setup
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update --yes && \
   apt-get upgrade --yes && \
   apt-get install --yes --no-install-recommends \
       bzip2 \
       ca-certificates \
       locales \
       sudo \
       tini \
       curl && \
   apt-get clean && rm -rf /var/lib/apt/lists/* && \
   echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
   locale-gen

ENV CONDA_DIR=/opt/conda \
   SHELL=/bin/bash \
   OHDSI_USER="${OHDSI_USER}" \
   OHDSI_UID="${OHDSI_UID}" \
   OHDSI_GID="${OHDSI_GID}" \
   LC_ALL=en_US.UTF-8 \
   LANG=en_US.UTF-8 \
   LANGUAGE=en_US.UTF-8
ENV PATH="${CONDA_DIR}/bin:${PATH}" \
   HOME="/home/${OHDSI_USER}"

# Copy the 'permission-edits' script and set permissions
COPY permission-edits /usr/local/bin/permission-edits
RUN chmod a+rx /usr/local/bin/permission-edits

# Configure shell and user permissions
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc && \
   echo 'eval "$(command conda shell.bash hook 2> /dev/null)"' >> /etc/skel/.bashrc && \
   echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
   sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
   sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
   useradd --no-log-init --create-home --shell /bin/bash --uid "${OHDSI_UID}" --gid "${OHDSI_GID}" "${OHDSI_USER}" && \
   mkdir -p "${CONDA_DIR}" && \
   chown "${OHDSI_USER}:${OHDSI_GID}" "${CONDA_DIR}" && \
   chmod g+w /etc/passwd && \
   permission-edits "${CONDA_DIR}" && \
   permission-edits "/home/${OHDSI_USER}"

# Switch to the OHDSI user
USER ${OHDSI_UID}

ARG PYTHON_VERSION=3.11

# Create a 'work' directory for the OHDSI user
RUN mkdir "/home/${OHDSI_USER}/work"

# Copy the 'condarc' file and set its ownership
COPY --chown="${OHDSI_UID}:${OHDSI_GID}" condarc "${CONDA_DIR}/.condarc"
WORKDIR /tmp
RUN set -x && \
   arch=$(uname -m) && \
   if [ "${arch}" = "x86_64" ]; then \
       arch="64"; \
   fi && \
   curl -L -o /tmp/micromamba.tar.bz2 \
       "https://micromamba.snakepit.net/api/micromamba/linux-${arch}/latest" && \
   tar -xvjf /tmp/micromamba.tar.bz2 --strip-components=1 bin/micromamba && \
   rm /tmp/micromamba.tar.bz2 && \
   PYTHON_SPECIFIER="python=${PYTHON_VERSION}" && \
   if [[ "${PYTHON_VERSION}" == "default" ]]; then PYTHON_SPECIFIER="python"; fi && \
   ./micromamba install \
       --root-prefix="${CONDA_DIR}" \
       --prefix="${CONDA_DIR}" \
       --yes \
       "${PYTHON_SPECIFIER}" \
       'mamba' \
       'jupyter_core' && \
   rm micromamba && \
   mamba list python | grep '^python ' | tr -s ' ' | cut -d ' ' -f 1,2 >> "${CONDA_DIR}/conda-meta/pinned" && \
   mamba clean --all -f -y && \
   permission-edits "${CONDA_DIR}" && \
   permission-edits "/home/${OHDSI_USER}"

# Set the entrypoint and default command
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start.sh"]

# Copy additional scripts to /usr/local/bin/
COPY hooks.sh start.sh /usr/local/bin/

# Switch back to the OHDSI user and create some directories
USER ${OHDSI_UID}
RUN mkdir /usr/local/bin/start-notebook.d && \
   mkdir /usr/local/bin/before-notebook.d

# Set the working directory
WORKDIR "${HOME}"
