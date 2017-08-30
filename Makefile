# ##############################################################################
# You do no need to modify anything in this file.
# ##############################################################################

# ##############################################################################
# Version of the current file

# git describe --tags --always
MAKEFILE_VERSION_GIT_DESCRIBE := v1.3
# date
MAKEFILE_VERSION_DATE := Mon 28 Aug 2017 12:42:28 EDT
# git symbolic-ref --short HEAD
MAKEFILE_VERSION_GIT_BRANCH := master

# Set the default shell used throughout the file to bash.
# Many shell commands are used and expect bash, but on Ubuntu the
# default shell (/bin/sh) is dash which does not support the shell code
# in here (see issue #10).
SHELL = /bin/bash


# ##############################################################################

# Configuration file where values are saved and read from.
MAKEFILE_CONFIG_FILE := Makefile.cfg
# Configuration file where Jupyter and Tensorboard ports are saved.
MAKEFILE_PORTS_FILE := .Makefile.ports

# Extra Makefile so that user can add new custom targets. This Makefile will
# included at the end of the current one, after all targets have been defined.
MAKEFILE_USER_EXTRA_TARGETS := Makefile.user

# Default values
DEFAULT_DOCKER := docker
DEFAULT_DOCKER_IMAGE_VERSION := 0.1
DEFAULT_PORTS_TO_PUBLISH :=
DEFAULT_VOLUMES_TO_MOUNT :=
DEFAULT_ENV_VAR_TO_EXPORT :=
DEFAULT_IMAGE_FILES_DEPENDENCIES := Dockerfile
DEFAULT_TENSORBOARD_DIR := tensorboard_logs
DEFAULT_DOCKER_BUILD_EXTRA :=

# Environment variables always exported to a running container
ALWAYS_DOCKER_ENV_VAR = HOST_HOSTNAME=$(HOSTNAME) HOST_USERNAME=$(shell whoami)
# Volumes to always mount in a running container.
# Note: Quote the current working directory
ALWAYS_DOCKER_VOLUMES = "$(CURDIR)":/eai

# Define an empty variable so we can then define a variable containing a space
EMPTY :=
SPACE := $(EMPTY) $(EMPTY)

# Spaces will be replaced with this placeholder in paths. Required since make
# commands like $(foreach) will use spaces as separators.
SPACE_PLACEHOLDER := _@_

# Escape the spaces in current working directory
ESCAPED_PWD = $(subst $(SPACE),$(SPACE_PLACEHOLDER),$(CURDIR))


# ##############################################################################
# Functions used to save and load configuration from file.

# Function that will either read a variable from the config file or ask the
# user to provide a value and save it to the config file.
# $(1): Variable to verify presence
# $(2): Question to ask user
# $(3): Default answer value
# $(4): 'REQUIRED' if a value is required
define add_if_not_present
$(strip $(shell tmp_val="$(3)" && \
if [[ -f $(MAKEFILE_CONFIG_FILE) ]]; then line=`grep "$(1)\s*:=" $(MAKEFILE_CONFIG_FILE)`; true; fi && \
if [[ "$${line}" != "" ]]; then tmp_val=`echo "$${line}" | cut -f 2- -d "="`; true; fi && \
if [[ "$(3)" == "" ]]; then \
    msg_default=""; \
else \
    msg_default=" [default: $${tmp_val}]"; \
fi && \
if [[ "$${line}" == "" ]]; then \
    read -p "$(2)$${msg_default}: " answer; \
    tmp_val=$${answer:-$${tmp_val}}; \
    if [[ "$(4)" == "REQUIRED" && "$${tmp_val}" == "" ]]; then \
        pass; \
    else \
        echo "# $(2)$${msg_default}:" >> $(MAKEFILE_CONFIG_FILE); \
        echo "$(1) := $${tmp_val}" >> $(MAKEFILE_CONFIG_FILE); \
        echo "" >> $(MAKEFILE_CONFIG_FILE); \
    fi; \
fi && \
echo "$${tmp_val}"))
endef

# Function that will either read a port from the config file or generate a
# random one between 1024 and 65535 using Python.
# $(1): Variable to verify presence
define get_random_port
$(strip $(shell port="" && \
if [[ -f $(MAKEFILE_PORTS_FILE) ]]; then line=`grep "$(1)\s*:=" $(MAKEFILE_PORTS_FILE)`; true; fi && \
if [[ "$${line}" != "" ]]; then port=`echo "$${line}" | cut -f 2- -d "="`; true; fi && \
if [[ "$${line}" == "" ]]; then \
    port=`python -c 'from random import randint; print(randint(1024, 65535));'`; \
    echo "# Port randomly generated (can be safely changed):" >> $(MAKEFILE_PORTS_FILE); \
    echo "$(1) := $${port}" >> $(MAKEFILE_PORTS_FILE); \
    echo "" >> $(MAKEFILE_PORTS_FILE); \
fi && \
echo "$${port}"))
endef


# ##############################################################################
# Project specific variables, read from the configuration file.

PROJECT_NAME := $(call add_if_not_present,PROJECT_NAME,Enter project name,,REQUIRED)
ifeq ($(strip $(PROJECT_NAME)),)
    $(error Please provide a name)
endif

DOCKER := $(call add_if_not_present,DOCKER,Enter command to run docker,$(DEFAULT_DOCKER))
DOCKER_IMAGE_VERSION := $(call add_if_not_present,DOCKER_IMAGE_VERSION,Enter image version,$(DEFAULT_DOCKER_IMAGE_VERSION))
PORTS_TO_PUBLISH := $(call add_if_not_present,PORTS_TO_PUBLISH,Enter list of ports to publish (NOTE: Jupyter and Tensorboard ports are automatically published),$(DEFAULT_PORTS_TO_PUBLISH))
VOLUMES_TO_MOUNT := $(call add_if_not_present,VOLUMES_TO_MOUNT,Enter list of volumes to mount (NOTE: The current directory is automatically mounted as /eai),$(DEFAULT_VOLUMES_TO_MOUNT))
ENV_VAR_TO_EXPORT := $(call add_if_not_present,ENV_VAR_TO_EXPORT,Enter list of envirnment variables to export inside container (NOTE: Hostname and username are automatically exported as 'HOST_HOSTNAME' and 'HOST_USERNAME'),$(DEFAULT_ENV_VAR_TO_EXPORT))
IMAGE_FILES_DEPENDENCIES := $(call add_if_not_present,IMAGE_FILES_DEPENDENCIES,Enter list of files dependency (to trigger image rebuild),$(DEFAULT_IMAGE_FILES_DEPENDENCIES))
TENSORBOARD_DIR := $(call add_if_not_present,TENSORBOARD_DIR,Enter Tensorboard logs directory (NOTE: This directory should relative to the current directory, which gets mounted as /eai in the container.),$(DEFAULT_TENSORBOARD_DIR))
DOCKER_BUILD_EXTRA := $(call add_if_not_present,DOCKER_BUILD_EXTRA,Enter 'docker build' extra arguments,$(DEFAULT_DOCKER_BUILD_EXTRA))

JUPYTER_PORT := $(call get_random_port,JUPYTER_PORT)
TENSORBOARD_PORT := $(call get_random_port,TENSORBOARD_PORT)


# ##############################################################################
# Makefile configuration

# Name of the docker image to build
DOCKER_IMAGE_TAG := $(shell whoami)_$(PROJECT_NAME):$(DOCKER_IMAGE_VERSION)
# Name of the docker container to create when running
DOCKER_CONTAINER_NAME := $(shell whoami)_$(PROJECT_NAME)

# File used to track state of 'docker build'
TARGET_DONE_FILE_BUILD := .docker_built

# Default command to execute as the container entrypoint
CMD = /bin/bash


# ##############################################################################
# Makefile's variables

HOSTNAME := $(shell hostname)

# Command to execute to launch a Jupyter notebook
JUPYTER_COMMAND = jupyter notebook \
    --no-browser \
    --ip=0.0.0.0 \
    --port=$(JUPYTER_PORT) \
    --NotebookApp.iopub_data_rate_limit=10000000000

# Command to execute to launch tensorboard
TENSORBOARD_COMMAND = tensorboard \
    --logdir=/eai/$(TENSORBOARD_DIR) \
    --host 0.0.0.0 \
    --port $(TENSORBOARD_PORT)


# The $(foreach) used to prepend '--volume' to every volume entry cannot
# work with spaces, even if they are enclosed in quotes. We thus
# construct the list of volumes by replacing the spaces in paths with a
# placeholder, append the '--volume' flag and finally replace back the
# placeholder with spaces.

# Replace spaces in the current working directory with the placeholder as to
# not confuse $(foreach)
VOLUMES_ESCAPED_CURDIR = $(subst $(SPACE),$(SPACE_PLACEHOLDER),$(ALWAYS_DOCKER_VOLUMES))
# Make sure we expand any variable contained in `VOLUMES_TO_MOUNT`
$(eval VOLUMES_TO_MOUNT = $(VOLUMES_TO_MOUNT))
# All volumes to mount
VOLUMES_ESCAPED_ALL = $(VOLUMES_ESCAPED_CURDIR) $(VOLUMES_TO_MOUNT)
# Prepend '--volume' to all (space escaped) volumes
VOLUMES_ESCAPED = $(foreach volume,$(VOLUMES_ESCAPED_ALL),--volume $(volume))
# Replace back the escaped spaces with actual spaces
DOCKER_VOLUMES = $(subst $(SPACE_PLACEHOLDER),$(SPACE),$(VOLUMES_ESCAPED))

DOCKER_ENV_VAR = $(foreach envvar,$(ENV_VAR_TO_EXPORT) $(ALWAYS_DOCKER_ENV_VAR),--env $(envvar))


PUBLISH := $(PORTS_TO_PUBLISH) \
    $(JUPYTER_PORT):$(JUPYTER_PORT) \
    $(TENSORBOARD_PORT):$(TENSORBOARD_PORT) \


DOCKER_USER = --user `id -u`:`id -g`
DOCKER_PORTS = $(foreach port,$(PUBLISH),--publish $(port))

DOCKER_COMMAND_RUN := $(DOCKER) run -it \
	$(DOCKER_ENV_VAR) \
	$(DOCKER_PORTS) \
	$(DOCKER_VOLUMES) \
	--name $(DOCKER_CONTAINER_NAME) \
	--rm \
	$(DOCKER_USER) \
	$(DOCKER_IMAGE_TAG)


# Note: The tensorboard port does not need to be published because it
#       is _not_ launched from the `Dockerfile`, but through
#       the `tensorboard` target.
DOCKER_COMMAND_BUILD := $(DOCKER) build --tag $(DOCKER_IMAGE_TAG) $(DOCKER_BUILD_EXTRA) .

# Command used to get version information
CMD_GIT_DESC := git describe --tags --always
CMD_GIT_BRANCH := git symbolic-ref --short HEAD
CMD_DATE := date


# ##############################################################################
# Targets

# Default target (used when `make` is called without a target) is the first
# target to be found in the Makefile.
# To extract all targets from the makefile: grep "^[^ ]*: " Makefile
.PHONY: usage
usage: print_makefile_version
	@echo ""
	@echo "Makefile and Dockerfile helping reproducible runs."
	@echo ""
	@echo "Usage:"
	@echo "    * make build"
	@echo "        Build the Docker image named '$(DOCKER_IMAGE_TAG)'."
	@echo "    * make notebook"
	@echo "        Create a container named '$(DOCKER_CONTAINER_NAME)' from image"
	@echo "        and run a Jupyter Notebook in it."
	@echo "        Short version: 'nb'"
	@echo "        NOTE: The same user id (uid) and group id (gid) as the user"
	@echo "              invoking make will be used, so files created inside the"
	@echo "              container will be owned properly (and deletable)."
	@echo "    * make tensorboard"
	@echo "        Attach to the running container '$(DOCKER_CONTAINER_NAME)'"
	@echo "        and launch Tensorboard in it."
	@echo "        Short version: 'tb'"
	@echo "    * make runi"
	@echo "        Run an interactive shell inside the container."
	@echo "        NOTE: The same user id (uid) and group id (gid) as the user"
	@echo "              invoking make will be used, so files created inside the"
	@echo "              container will be owned properly (and deletable)."
	@echo "              The shell will report 'I have no name!' as the user."
	@echo "    * make runi-root"
	@echo "        Run an interactive shell as root inside the container."
	@echo "        NOTE: The container is stateless, any modification to it"
	@echo "              will be lost on exit!"
	@echo "    * make attach"
	@echo "        Run a command from inside the running container."
	@echo "        The command run is controlled by the CMD environment variable"
	@echo "        (with default value: $(CMD))."
	@echo "        NOTE: This runs 'docker exec', not 'docker attach'."
	@echo "    * make cmd CMD='<command to run>'"
	@echo "        Run the command in the 'CMD' environment variable"
	@echo "        inside the container."
	@echo "    * make clean"
	@echo "        Delete Docker image and (automatically generated) port files."
	@echo "    * make debug"
	@echo "        Print variables defined in the Makefile for debugging."
	@echo "    * make usage"
	@echo "        This usage message."
	@echo "        '$(DOCKER_IMAGE_TAG)' and run a jupyter notebook inside it."
	@echo ""
	@echo "NOTES: "
	@echo "    * Here's the command used to run the container:"
	@echo "        $(DOCKER_COMMAND_RUN)"
	@echo "    * Since the '--name' option is used to run the container, only"
	@echo "      a single instance can be run at any given time."
	@echo "    * The container is stateless (since '--rm' is used) so any"
	@echo "      modification to it will be dropped when exiting the container."


# Clean automatically generated files and Docker image to re-trigger builds and
# port generation.
.PHONY: clean
clean:
	rm -f $(TARGET_DONE_FILE_BUILD)
	rm -f $(MAKEFILE_PORTS_FILE)
	$(DOCKER) rmi $(DOCKER_IMAGE_TAG) || true


# Target that actually build (`docker build`) the image.
$(TARGET_DONE_FILE_BUILD): $(IMAGE_FILES_DEPENDENCIES) $(JUPYTER_PORT_FILE) .dockerignore
	$(DOCKER_COMMAND_BUILD)
	LANG=C date > $(TARGET_DONE_FILE_BUILD)
	docker images $(DOCKER_IMAGE_TAG) >> $(TARGET_DONE_FILE_BUILD)
	@echo ""


# Phony target to build image through dependency
.PHONY: build
build: print_makefile_version $(TARGET_DONE_FILE_BUILD)
	@echo "Docker image '$(DOCKER_IMAGE_TAG)' last built on `cat $(TARGET_DONE_FILE_BUILD)`"


# Phony target to run a Jupyter Notebook using the `cmd` target as a dependency
.PHONY: notebook
notebook: print_makefile_version $(TARGET_DONE_FILE_BUILD)
	$(MAKE) cmd CMD="$(JUPYTER_COMMAND)"


# Shorthand phony target
.PHONY: nb
nb: notebook


# Create the directory where Tensorboard should be reading its logs
$(TENSORBOARD_DIR):
	mkdir -p $(TENSORBOARD_DIR)


# Phony target to run a Tensorboard using the `attach` target as a dependency
.PHONY: tensorboard
tensorboard: print_makefile_version $(TARGET_DONE_FILE_BUILD) $(TENSORBOARD_DIR)
	$(MAKE) attach CMD="$(TENSORBOARD_COMMAND)"


# Shorthand phony target
.PHONY: tb
tb: tensorboard


# Phony target to run an interactive shell (as same user as the one
# invoking `make`) inside the container.
.PHONY: runi
runi: print_makefile_version $(TARGET_DONE_FILE_BUILD)
	$(DOCKER_COMMAND_RUN) /bin/bash


# Phony target to run an interactive shell as root.
# Re-launch `make` with the `runi` (run interactive) target, unsetting
# the variable `DOCKER_USER` so as to run as root.
.PHONY: runi-root
runi-root: print_makefile_version $(TARGET_DONE_FILE_BUILD)
	$(MAKE) runi DOCKER_USER=


# Phony target to "attach" to a running container. Since attaching would give
# the same prompt as the already running container, "exec" is used here to
# run a specific command inside the container. By default this command,
# stored in `CMD`, is a bash shell (/bin/bash).
.PHONY: attach
attach: print_makefile_version
	docker exec -it $(DOCKER_CONTAINER_NAME) $(CMD)


# Phony target to kill a running container. Useful when Jupyter does not want
# to exit after a Ctrl+C event.
.PHONY: kill
kill: print_makefile_version
	docker kill $(DOCKER_CONTAINER_NAME)


# Phony target to run a specific command stored in environment variable `CMD`
# inside the container.
.PHONY: cmd
cmd: print_makefile_version $(TARGET_DONE_FILE_BUILD)
	$(DOCKER_COMMAND_RUN) $(CMD)


# Automatically create a .dockerignore file with files and directories that
# should, most of the time, be ignored from the Docker context.
.dockerignore:
	echo ".git" > $@
	echo "Dockerfile" >> $@
	echo "$(MAKEFILE_CONFIG_FILE)" >> $@
	echo "data" >> $@
	echo "datasets" >> $@


# Phony target to print debug information, mainly variables used in the Makefile.
.PHONY: debug
debug: print_makefile_version
	@echo "MAKEFILE_VERSION_DATE:            $(MAKEFILE_VERSION_DATE)"
	@echo "MAKEFILE_VERSION_GIT_DESCRIBE:    $(MAKEFILE_VERSION_GIT_DESCRIBE)"
	@echo "MAKEFILE_VERSION_GIT_BRANCH:      $(MAKEFILE_VERSION_GIT_BRANCH)"
	@echo "PROJECT_NAME:                     $(PROJECT_NAME)"
	@echo "DOCKER:                           $(DOCKER)"
	@echo "DOCKER_IMAGE_VERSION:             $(DOCKER_IMAGE_VERSION)"
	@echo "DOCKER_IMAGE_TAG:                 $(DOCKER_IMAGE_TAG)"
	@echo "DOCKER_CONTAINER_NAME:            $(DOCKER_CONTAINER_NAME)"
	@echo "PORTS_TO_PUBLISH:                 $(PORTS_TO_PUBLISH)"
	@echo "VOLUMES_TO_MOUNT:                 $(VOLUMES_TO_MOUNT)"
	@echo "ENV_VAR_TO_EXPORT:                $(ENV_VAR_TO_EXPORT)"
	@echo "VOLUMES_TO_MOUNT:                 $(VOLUMES_TO_MOUNT)"
	@echo "IMAGE_FILES_DEPENDENCIES:         $(IMAGE_FILES_DEPENDENCIES)"
	@echo "DOCKER_BUILD_EXTRA:               $(DOCKER_BUILD_EXTRA)"
	@echo "TARGET_DONE_FILE_BUILD:           $(TARGET_DONE_FILE_BUILD)"
	@echo "JUPYTER_PORT:                     $(JUPYTER_PORT)"
	@echo "JUPYTER_COMMAND:                  $(JUPYTER_COMMAND)"
	@echo "TENSORBOARD_PORT:                 $(TENSORBOARD_PORT)"
	@echo "TENSORBOARD_COMMAND:              $(TENSORBOARD_COMMAND)"
	@echo "HOSTNAME:                         $(HOSTNAME)"
	@echo "VOLUMES:                          $(VOLUMES)"
	@echo "PUBLISH:                          $(PUBLISH)"
	@echo "DOCKER_USER:                      $(DOCKER_USER)"
	@echo "DOCKER_ENV_VAR:                   $(DOCKER_ENV_VAR)"
	@echo "DOCKER_PORTS:                     $(DOCKER_PORTS)"
	@echo "DOCKER_VOLUMES:                   $(DOCKER_VOLUMES)"
	@echo "DOCKER_COMMAND_RUN:               $(DOCKER_COMMAND_RUN)"
	@echo "DOCKER_COMMAND_BUILD:             $(DOCKER_COMMAND_BUILD)"
	@echo "CMD_GIT_DESC:                     $(CMD_GIT_DESC)"
	@echo "CMD_GIT_BRANCH:                   $(CMD_GIT_BRANCH)"
	@echo "CMD_DATE:                         $(CMD_DATE)"


# Phony target used to print the Makefile's version. Most of other target
# depend on this one.
.PHONY: print_makefile_version
print_makefile_version:
	@echo "Makefile version: $(MAKEFILE_VERSION_GIT_DESCRIBE)"
	@echo "                  git branch: $(MAKEFILE_VERSION_GIT_BRANCH)"
	@echo "                  $(MAKEFILE_VERSION_DATE)"


# Update the Makefile version information at the top of the file.
.PHONY: update_makefile_version
update_makefile_version:
	cp Makefile .Makefile.bak.`date +%Y%m%d_%Hh%M`
	sed \
	    -e "s|\(MAKEFILE_VERSION_GIT_DESCRIBE :=\) .*|\1 `$(CMD_GIT_DESC)`|g" \
	    -e "s|\(MAKEFILE_VERSION_GIT_BRANCH :=\) .*|\1 `$(CMD_GIT_BRANCH)`|g" \
	    -e "s|\(MAKEFILE_VERSION_DATE :=\) .*|\1 `$(CMD_DATE)`|g" \
	    Makefile > Makefile.new
	mv Makefile.new Makefile


# ##############################################################################
# Add extra targets defined by the user in the

ifneq (,$(wildcard $(MAKEFILE_USER_EXTRA_TARGETS)))
    include $(MAKEFILE_USER_EXTRA_TARGETS)
endif
