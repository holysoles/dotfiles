#!/bin/bash

__kube_ps1()
{
    if [ -z "$KUBE_INSTALLED" ]; then
        exit 0
    fi
    KUBE_CONTEXT=$(kubectl config current-context 2>/dev/null)

    if [ -n "$KUBE_CONTEXT" ]; then
	    C_DEEPSKYBLUE='\e[38;5;39m'
	    NO_FORMAT='\e[0m'

        echo -e "(k8s: \001${C_DEEPSKYBLUE}\002${KUBE_CONTEXT}\001${NO_FORMAT}\002)"
    fi
}
