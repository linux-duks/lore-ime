# Container runtime and compose command detection
# 
# This file provides auto-detection for container runtime and compose command.
# Priority: podman > docker compose (v2) > docker-compose (v1)
#
# Users can override by setting CONTAINER and/or COMPOSE variables:
#   make run CONTAINER=nerdctl COMPOSE="nerdctl compose"
#
# Include this file in your Makefile with: include containers.mk

CONTAINER ?=
COMPOSE ?=

ifeq ($(CONTAINER),)
    # Auto-detect container runtime
    ifeq ($(shell command -v podman 2> /dev/null),)
        CONTAINER=docker
        # Check for docker compose (v2 plugin) first, then docker-compose (v1 standalone)
        ifeq ($(shell docker compose version 2> /dev/null),)
            COMPOSE=docker-compose
        else
            COMPOSE=docker compose
        endif
    else
        CONTAINER=podman
        COMPOSE=podman-compose
    endif
endif

ifeq ($(COMPOSE),)
    # COMPOSE not set but CONTAINER was - build default based on CONTAINER
    ifeq ($(CONTAINER),podman)
        COMPOSE=podman-compose
    else ifeq ($(CONTAINER),nerdctl)
        COMPOSE=nerdctl compose
    else
        # Default to docker compose (v2), fallback to docker-compose (v1)
        ifeq ($(shell docker compose version 2> /dev/null),)
            COMPOSE=docker-compose
        else
            COMPOSE=docker compose
        endif
    endif
endif

# Safely determine the real user/group ID, even if run with sudo
REAL_UID := $(if $(SUDO_UID),$(SUDO_UID),$(shell id -u))
REAL_GID := $(if $(SUDO_GID),$(SUDO_GID),$(shell id -g))

# Export them so docker compose picks them up automatically
export UID = $(REAL_UID)
export GID = $(REAL_GID)
# ----------------------
