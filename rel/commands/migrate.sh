#!/usr/bin/env bash

release_ctl eval --mfa "MixSystemdDeploy.Tasks.Migrate.run/1" --argv -- "$@"
