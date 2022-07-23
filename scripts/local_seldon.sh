#!/usr/bin/env bash
. "$( dirname "${BASH_SOURCE[0]}" )/_kind_cluster.sh"
kind::perform_kind_cluster_operation $1