SHELL := /bin/sh

GO ?= go
CMAKE ?= cmake
TARGET ?=
PLATFORM ?=
RUN_PLATFORM ?= $(if $(TARGET),$(TARGET),$(PLATFORM))

# `make build android` is accepted in addition to `make build TARGET=android`.
GOAL_TARGET := $(filter macos android web,$(MAKECMDGOALS))
ifneq ($(GOAL_TARGET),)
TARGET := $(firstword $(GOAL_TARGET))
endif

RUN_GOAL_PLATFORM := $(filter macos android web phone pc,$(MAKECMDGOALS))
ifneq ($(RUN_GOAL_PLATFORM),)
RUN_PLATFORM := $(firstword $(RUN_GOAL_PLATFORM))
endif

.PHONY: setup submodules tdlib tdlib-macos tdlib-android tdlib-web build run macos android phone pc web clean clean-tdlib

setup:
	@GO="$(GO)" CMAKE="$(CMAKE)" ./scripts/build.sh setup

submodules:
	@GO="$(GO)" CMAKE="$(CMAKE)" ./scripts/build.sh submodules

tdlib:
	@GO="$(GO)" CMAKE="$(CMAKE)" ./scripts/build.sh tdlib

tdlib-macos:
	@GO="$(GO)" CMAKE="$(CMAKE)" ./scripts/build.sh tdlib-macos

tdlib-android:
	@GO="$(GO)" CMAKE="$(CMAKE)" ./scripts/build.sh tdlib-android

tdlib-web:
	@GO="$(GO)" CMAKE="$(CMAKE)" ./scripts/build.sh tdlib-web

build:
	@if [ -z "$(TARGET)" ]; then \
		echo "Usage: make build macos|android|web or make build TARGET=macos|android|web" >&2; \
		exit 2; \
	fi
	@GO="$(GO)" CMAKE="$(CMAKE)" ./scripts/build.sh build "$(TARGET)"

run:
	@GO="$(GO)" CMAKE="$(CMAKE)" ./scripts/build.sh run "$(RUN_PLATFORM)"

# No-op goals used by the `make build android` dispatcher.
macos android phone pc web:
	@:

clean:
	rm -rf build dist

clean-tdlib:
	rm -rf tdlib/src tdlib/build tdlib/install